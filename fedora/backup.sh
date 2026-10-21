#!/usr/bin/env bash
# 43PR/dotfiles — Fedora port: backup before installing
#
# Usage:
#   ./fedora/backup.sh [--out DIR] [--snapshot]
#
#   --out DIR    where to write the backup (default: ~/43pr-backups)
#   --snapshot   also take a read-only btrfs snapshot of /home (needs sudo)
#
# Saves everything fedora/install.sh changes, so fedora/restore.sh can put
# your desktop back:
#   - every ~/.config entry this repo manages, ~/.zshrc, ~/.config/mimeapps.list
#   - fonts, zsh plugin and state dirs the installer adds
#   - GNOME settings (dconf), login shell
#   - package list, enabled repos, Flatpaks, the last dnf transaction ID,
#     /usr/local/bin contents
#
# Output: ~/43pr-backups/pre-43pr-<timestamp>/ plus a .tar.gz of it. Copy the
# .tar.gz off this machine (NAS, another host, USB drive). dconf.ini holds
# your GNOME settings, so don't publish it.

set -uo pipefail

# shellcheck source=fedora/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

OUT_ROOT="$HOME/43pr-backups"
SNAPSHOT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)      OUT_ROOT="${2:?--out needs a directory}"; shift ;;
        --snapshot) SNAPSHOT=1 ;;
        -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

if [[ "${EUID}" -eq 0 ]]; then
    error "Run as your normal user, not root."
    exit 1
fi

# Paths relative to $HOME
backup_paths() {
    local e
    printf '%s\n' ".zshrc" ".config/mimeapps.list" \
        ".local/share/fonts/NerdFonts" ".local/share/zsh/zsh-autocomplete" \
        ".local/state/43pr" ".config/systemd/user/hyprland-session.target"
    for e in "$SRC"/* "$SRC"/.[!.]*; do
        [[ -e "$e" ]] || continue
        printf '.config/%s\n' "$(basename "$e")"
    done
}

# An entry is "already from this repo" if it's a symlink into the repo, or a
# directory whose files are mostly symlinks into it.
from_repo() {
    local p="$HOME/$1" total linked
    if [[ -L "$p" ]]; then
        [[ "$(readlink -f "$p")" == "$REPO_DIR"/* ]]
        return
    fi
    [[ -d "$p" ]] || return 1
    total=$(find "$p" \( -type f -o -type l \) 2>/dev/null | wc -l)
    linked=$(find "$p" -type l -lname "$REPO_DIR/*" 2>/dev/null | wc -l)
    (( total > 0 && linked * 2 > total ))
}

TS="$(date '+%Y-%m-%d_%H-%M-%S')"
NAME="pre-43pr-$TS"
DEST="$OUT_ROOT/$NAME"
mkdir -p "$DEST"
chmod 700 "$OUT_ROOT" "$DEST"

info "Backing up to $DEST"

# --------------------------------------------------
# Files
# --------------------------------------------------

mapfile -t PATHS < <(backup_paths)
present=()
already=()
for p in "${PATHS[@]}"; do
    [[ -e "$HOME/$p" || -L "$HOME/$p" ]] || continue
    present+=("$p")
    from_repo "$p" && already+=("$p")
done

printf '%s\n' "${present[@]}" > "$DEST/present.txt"

if [[ "${#already[@]}" -gt 0 ]]; then
    warning "These already come from the dotfiles repo, so this backup can't hold your pre-install versions:"
    printf '    %s\n' "${already[@]}"
    if compgen -G "$HOME/.config-backups/*" >/dev/null; then
        warning "The installer saved what it replaced in ~/.config-backups/ (newest = most recent install)."
    fi
fi

if [[ "${#present[@]}" -gt 0 ]]; then
    # -h is NOT used: symlinks are stored as symlinks, so a backup taken after
    # install doesn't silently copy the repo's files as if they were yours.
    if tar -C "$HOME" -czf "$DEST/files.tar.gz" -- "${present[@]}" 2>"$DEST/tar-warnings.txt"; then
        success "Saved ${#present[@]} config path(s)."
    else
        warning "tar reported problems (see $DEST/tar-warnings.txt); the backup may be partial."
    fi
    [[ -s "$DEST/tar-warnings.txt" ]] || rm -f "$DEST/tar-warnings.txt"
else
    info "None of the managed config paths exist yet; nothing to archive."
fi

# --------------------------------------------------
# Settings and system state
# --------------------------------------------------

if command -v dconf >/dev/null 2>&1; then
    dconf dump / > "$DEST/dconf.ini" && chmod 600 "$DEST/dconf.ini"
fi
getent passwd "$USER" | cut -d: -f7 > "$DEST/login-shell.txt"
rpm -qa --qf '%{NAME}\n' 2>/dev/null | sort -u > "$DEST/packages.txt"
ls -1 /etc/yum.repos.d/ > "$DEST/repo-files.txt" 2>/dev/null
dnf repo list --enabled > "$DEST/repos-enabled.txt" 2>/dev/null
command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application > "$DEST/flatpaks.txt" 2>/dev/null
ls -1 /usr/local/bin > "$DEST/usr-local-bin.txt" 2>/dev/null

# Highest transaction ID = the state to roll back to
dnf history list 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && $1 > m { m = $1 } END { if (m) print m }' > "$DEST/dnf-last-id.txt"
[[ -s "$DEST/dnf-last-id.txt" ]] || warning "Couldn't read the dnf history ID; restore.sh won't be able to roll back packages."

cat > "$DEST/manifest.env" <<EOF
created=$TS
host=$(hostname)
user=$USER
repo=$REPO_DIR
repo_commit=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
already_installed=${#already[@]}
EOF

# --------------------------------------------------
# Optional btrfs snapshot
# --------------------------------------------------

if [[ "$SNAPSHOT" -eq 1 ]]; then
    if [[ "$(findmnt -no FSTYPE /home 2>/dev/null)" == "btrfs" ]]; then
        snap="/home/.snapshots/home-$NAME"
        sudo mkdir -p /home/.snapshots \
            && sudo btrfs subvolume snapshot -r /home "$snap" >/dev/null \
            && success "btrfs snapshot: $snap (read-only, same disk)" \
            && echo "snapshot=$snap" >> "$DEST/manifest.env" \
            || warning "Snapshot failed."
    else
        warning "/home isn't btrfs; skipping snapshot."
    fi
fi

# --------------------------------------------------
# Single archive to copy elsewhere
# --------------------------------------------------

tar -C "$OUT_ROOT" -czf "$OUT_ROOT/$NAME.tar.gz" "$NAME" && chmod 600 "$OUT_ROOT/$NAME.tar.gz"

success "Backup complete."
cat <<EOF

  Folder:  $DEST
  Archive: $OUT_ROOT/$NAME.tar.gz  ($(du -h "$OUT_ROOT/$NAME.tar.gz" | cut -f1))

Copy the archive off this machine, e.g.:
  scp "$OUT_ROOT/$NAME.tar.gz" you@nas:backups/

Restore later with:
  ./fedora/restore.sh "$OUT_ROOT/$NAME.tar.gz"
EOF
