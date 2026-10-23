#!/usr/bin/env bash
# 43PR/dotfiles — Fedora port: put your desktop back the way backup.sh found it
#
# Usage:
#   ./fedora/restore.sh [BACKUP] [--yes] [--configs-only]
#
#   BACKUP          a backup folder or .tar.gz from backup.sh
#                   (default: newest in ~/43pr-backups)
#   --yes           don't ask before each step
#   --configs-only  restore files, settings and login shell; leave packages,
#                   repos and Flatpaks alone
#
# Steps (each asks first unless --yes):
#   1. Configs: everything this repo manages in ~/.config and ~/.zshrc is moved
#      to ~/43pr-backups/replaced-<timestamp>/ (nothing is deleted), then the
#      backed-up versions are unpacked. Paths that didn't exist before stay gone.
#   2. GNOME settings (dconf) and the login shell.
#   3. Packages: `dnf history rollback` to the transaction recorded at backup
#      time (dnf shows the list and asks before changing anything), disable
#      COPRs added since, remove the Flatpak recorder and the /usr/local/bin
#      tools the installer built, reset papirus-folders.
#
# The repo itself (~/dotfiles) is not touched. Delete it yourself afterwards.

set -uo pipefail

# shellcheck source=fedora/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BACKUP=""
ASSUME_YES=0
CONFIGS_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y)        ASSUME_YES=1 ;;
        --configs-only)  CONFIGS_ONLY=1 ;;
        -h|--help)       sed -n '2,24p' "$0"; exit 0 ;;
        -*) error "Unknown option: $arg"; exit 1 ;;
        *)  BACKUP="$arg" ;;
    esac
done

confirm() {
    [[ "$ASSUME_YES" -eq 1 ]] && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

if [[ "${EUID}" -eq 0 ]]; then
    error "Run as your normal user, not root."
    exit 1
fi

# --------------------------------------------------
# Locate and unpack the backup
# --------------------------------------------------

# Default: newest backup taken BEFORE the port was installed (a backup made
# afterwards mostly holds links to the repo), else the newest of any.
if [[ -z "$BACKUP" ]]; then
    shopt -s nullglob
    candidates=("$HOME"/43pr-backups/pre-43pr-*/)
    shopt -u nullglob
    for (( i = ${#candidates[@]} - 1; i >= 0; i-- )); do   # glob is sorted; timestamps sort by time
        d="${candidates[i]%/}"
        [[ -z "$BACKUP" ]] && BACKUP="$d"
        if grep -q '^already_installed=0$' "$d/manifest.env" 2>/dev/null; then BACKUP="$d"; break; fi
    done
    [[ -n "$BACKUP" ]] || { error "No backup found in ~/43pr-backups. Pass a path."; exit 1; }
fi

WORK=""
cleanup() { [[ -n "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT

if [[ -f "$BACKUP" && "$BACKUP" == *.tar.gz ]]; then
    WORK="$(mktemp -d)"
    tar -C "$WORK" -xzf "$BACKUP" || { error "Couldn't unpack $BACKUP"; exit 1; }
    B="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'pre-43pr-*' | head -n1)"
elif [[ -d "$BACKUP" ]]; then
    B="$(cd "$BACKUP" && pwd)"
else
    error "Not a backup folder or .tar.gz: $BACKUP"
    exit 1
fi

[[ -f "$B/manifest.env" && -f "$B/present.txt" ]] || { error "$BACKUP doesn't look like a backup.sh backup."; exit 1; }

info "Backup: $(basename "$B")"
sed 's/^/    /' "$B/manifest.env"
if grep -q '^already_installed=[1-9]' "$B/manifest.env"; then
    warning "This backup was taken after the port was installed; some configs in it are just links to the repo."
fi

# --------------------------------------------------
# 1. Configs
# --------------------------------------------------

mapfile -t PRESENT < "$B/present.txt"

# Every path backup.sh considers, now (current repo layout) and then
managed_paths() {
    local e
    printf '%s\n' ".zshrc" ".config/mimeapps.list" \
        ".local/share/fonts/NerdFonts" ".local/share/zsh/zsh-autocomplete" \
        ".local/state/43pr" ".config/systemd/user/hyprland-session.target"
    for e in "$SRC"/* "$SRC"/.[!.]*; do
        [[ -e "$e" ]] || continue
        printf '.config/%s\n' "$(basename "$e")"
    done
    printf '%s\n' "${PRESENT[@]}"
}

if confirm "Restore configs (current ones are moved aside, not deleted)?"; then
    ASIDE="$HOME/43pr-backups/replaced-$(date '+%Y-%m-%d_%H-%M-%S')"
    moved=0
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        if [[ -e "$HOME/$p" || -L "$HOME/$p" ]]; then
            mkdir -p "$ASIDE/$(dirname "$p")"
            mv -- "$HOME/$p" "$ASIDE/$p" && moved=$((moved + 1))
        fi
    done < <(managed_paths | sort -u)
    [[ "$moved" -gt 0 ]] && info "Moved $moved current path(s) to $ASIDE"

    if [[ -f "$B/files.tar.gz" ]]; then
        tar -C "$HOME" -xzf "$B/files.tar.gz" && success "Configs restored."
    else
        info "Backup has no config files (none existed before install)."
    fi
    systemctl --user daemon-reload 2>/dev/null || true
    fc-cache -f >/dev/null 2>&1 || true
fi

# --------------------------------------------------
# 2. GNOME settings, login shell
# --------------------------------------------------

if [[ -s "$B/dconf.ini" ]] && command -v dconf >/dev/null 2>&1; then
    if confirm "Restore GNOME settings (dconf)? Settings changed since the backup are reverted."; then
        dconf load / < "$B/dconf.ini" && success "GNOME settings restored."
    fi
fi

if [[ -s "$B/login-shell.txt" ]]; then
    old_shell="$(cat "$B/login-shell.txt")"
    cur_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$old_shell" != "$cur_shell" ]] && confirm "Change login shell back to $old_shell?"; then
        sudo usermod --shell "$old_shell" "$USER" && success "Login shell: $old_shell (next login)."
    fi
fi

# --------------------------------------------------
# 3. Packages, repos, Flatpaks, tools
# --------------------------------------------------

if [[ "$CONFIGS_ONLY" -eq 0 ]]; then
    # papirus-folders changes system icon folders; reset before it's removed
    if command -v papirus-folders >/dev/null 2>&1 && confirm "Reset Papirus folder color to default?"; then
        papirus-folders -D || warning "papirus-folders reset failed."
    fi

    last_id="$(cat "$B/dnf-last-id.txt" 2>/dev/null)"
    # Rolling back removes zsh if the backup predates it. If zsh is still the
    # login shell, that would leave an account GDM can't log into.
    cur_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$last_id" =~ ^[0-9]+$ && "$(basename "$cur_shell")" == "zsh" ]] \
        && [[ -f "$B/packages.txt" ]] && ! grep -qx zsh "$B/packages.txt"; then
        warning "Your login shell is zsh, but zsh wasn't installed at backup time, so the rollback would remove it."
        warning "Skipping the package rollback. Change your shell first (re-run and accept the login-shell step,"
        warning "or: sudo usermod --shell /bin/bash $USER), then run restore.sh again."
        last_id=""
    fi
    if [[ "$last_id" =~ ^[0-9]+$ ]]; then
        info "Package rollback: undoes every dnf transaction after #$last_id."
        info "Review dnf's list before answering: it includes anything else you installed since the backup."
        if confirm "Run 'sudo dnf history rollback $last_id'?"; then
            sudo dnf history rollback "$last_id" || warning "Rollback failed or was cancelled."
        fi
    elif [[ ! -s "$B/dnf-last-id.txt" ]]; then
        warning "No dnf transaction ID in the backup; skipping package rollback."
    fi

    # Repo files added since the backup
    if [[ -f "$B/repo-files.txt" ]]; then
        mapfile -t new_repos < <(comm -13 <(sort "$B/repo-files.txt") <(ls -1 /etc/yum.repos.d/ 2>/dev/null | sort))
        for f in "${new_repos[@]}"; do
            [[ -n "$f" ]] || continue
            if [[ "$f" =~ ^_copr:copr\.fedorainfracloud\.org:([^:]+):(.+)\.repo$ ]]; then
                copr="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
                confirm "Remove COPR $copr (added since backup)?" \
                    && sudo dnf copr remove -y "$copr" >/dev/null 2>&1 \
                    && success "Removed COPR $copr."
            else
                confirm "Remove repo file /etc/yum.repos.d/$f (added since backup)?" \
                    && sudo rm -f "/etc/yum.repos.d/$f" \
                    && success "Removed $f."
            fi
        done
    fi

    # Flatpak recorder installed by the port
    gsr="com.dec05eba.gpu_screen_recorder"
    if command -v flatpak >/dev/null 2>&1 && flatpak info "$gsr" >/dev/null 2>&1 \
        && ! grep -qx "$gsr" "$B/flatpaks.txt" 2>/dev/null \
        && confirm "Uninstall Flatpak $gsr?"; then
        sudo flatpak uninstall -y --system "$gsr" >/dev/null 2>&1 \
            || flatpak uninstall -y "$gsr" >/dev/null 2>&1
    fi

    # Tools the installer built into /usr/local/bin (only ones that weren't there before)
    for t in matugen starship eza cliphist papirus-folders; do
        [[ -e "/usr/local/bin/$t" ]] || continue
        grep -qx "$t" "$B/usr-local-bin.txt" 2>/dev/null && continue
        confirm "Remove /usr/local/bin/$t (installed by the port)?" && sudo rm -f "/usr/local/bin/$t"
    done
fi

success "Restore finished."
cat <<'EOF'

Log out and pick GNOME (or your previous session) at the login screen.
What was replaced is in ~/43pr-backups/replaced-*; delete it once you're happy.
The dotfiles repo is untouched; remove it with: rm -rf ~/dotfiles
EOF
