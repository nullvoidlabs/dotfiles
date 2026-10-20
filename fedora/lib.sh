#!/usr/bin/env bash
# Shared helpers for fedora/install.sh and fedora/update.sh.
# Sourced, not executed.

FEDORA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$FEDORA_DIR/.." && pwd)"
SRC="$REPO_DIR/.config"
CONFIG_DIR="$HOME/.config"
PACKAGE_FILE="$FEDORA_DIR/packages.txt"

# COPRs this port relies on. Printed and confirmed before anything is enabled.
COPR_HYPRLAND="nikromen/hyprland"            # hyprland 0.56.x, hyprlock, hyprpolkitagent, awww, xdph
COPR_QUICKSHELL="errornointernet/quickshell" # only if quickshell isn't in the Fedora repos

# --------------------------------------------------
# Output
# --------------------------------------------------

info()    { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$1"; }
success() { printf '\n\033[1;32m[DONE]\033[0m %s\n' "$1"; }
warning() { printf '\n\033[1;33m[WARN]\033[0m %s\n' "$1"; }
error()   { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; }

# --------------------------------------------------
# Generated files
# --------------------------------------------------
# theme.py writes these at runtime, so they are copied once instead of
# symlinked. The list is read from upstream install.sh so it can't drift when
# upstream adds a file; the hardcoded list is only a fallback.

load_generated_files() {
    GENERATED_FILES=()
    if [[ -f "$REPO_DIR/install.sh" ]]; then
        mapfile -t GENERATED_FILES < <(
            sed -n '/^GENERATED_FILES=(/,/^)/p' "$REPO_DIR/install.sh" \
                | grep -oE '"[^"]+"' | tr -d '"'
        )
    fi
    if [[ "${#GENERATED_FILES[@]}" -eq 0 ]]; then
        GENERATED_FILES=(
            "kitty/matugen.conf"
            "hypr/hyprlock-colors.conf"
            "gtk-3.0/colors.css"
            "gtk-4.0/colors.css"
            "gtk-3.0/settings.ini"
            "gtk-4.0/settings.ini"
            "rofi/colors.rasi"
            "quickshell/Theme.qml"
        )
    fi
}

is_generated() {
    local rel="$1" g
    for g in "${GENERATED_FILES[@]}"; do
        [[ "$rel" == "$g" ]] && return 0
    done
    return 1
}

# --------------------------------------------------
# System checks
# --------------------------------------------------

require_fedora() {
    if [[ "${EUID}" -eq 0 ]]; then
        error "Do not run this script as root (it calls sudo itself)."
        exit 1
    fi
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine the operating system."
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "fedora" && "${ID_LIKE:-}" != *fedora* ]]; then
        error "This installer is for Fedora. Detected: ${PRETTY_NAME:-unknown}"
        error "On Arch-based systems use the upstream ./install.sh instead."
        exit 1
    fi
    for cmd in sudo dnf rpm; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "$cmd is required."
            exit 1
        fi
    done
    if [[ ! -d "$SRC" ]]; then
        error "No .config directory found at $SRC"
        exit 1
    fi
    if [[ "$(uname -m)" != "x86_64" ]]; then
        warning "Non-x86_64 system detected; some COPR builds may be missing."
    fi
}

fedora_version() {
    # shellcheck disable=SC1091
    (source /etc/os-release && printf '%s' "${VERSION_ID:-0}")
}

# --------------------------------------------------
# dnf helpers
# --------------------------------------------------

ensure_copr_command() {
    dnf copr --help >/dev/null 2>&1 && return 0
    info "Installing the dnf copr plugin..."
    sudo dnf install -y dnf5-plugins >/dev/null 2>&1 \
        || sudo dnf install -y dnf-plugins-core >/dev/null 2>&1
    dnf copr --help >/dev/null 2>&1
}

copr_enabled() {
    # dnf5 and dnf4 both name the repo file after owner:project
    local owner="${1%/*}" project="${1#*/}"
    compgen -G "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${owner}:${project}.repo" >/dev/null \
        || compgen -G "/etc/yum.repos.d/_copr_${owner}-${project}.repo" >/dev/null
}

enable_copr() {
    local repo="$1"
    if copr_enabled "$repo"; then
        info "COPR already enabled: $repo"
        return 0
    fi
    info "Enabling COPR: $repo"
    sudo dnf copr enable -y "$repo"
}

# Names (from the given list) that exist in enabled repos or are installed.
# One dnf call for the whole list instead of one per package.
available_names() {
    {
        dnf -q repoquery --qf '%{name}\n' "$@" 2>/dev/null
        rpm -q --qf '%{NAME}\n' "$@" 2>/dev/null | grep -v 'is not installed'
    } | sed '/^[[:space:]]*$/d' | sort -u
}

read_package_lines() {
    # strips comments and blank lines, one entry per line ("a|b|c")
    sed -e 's/#.*//' -e 's/[[:space:]]\+//g' "$PACKAGE_FILE" | sed '/^$/d'
}

# Fills RESOLVED_PACKAGES and UNKNOWN_PACKAGES from packages.txt.
# With "missing-only", already-installed entries are skipped.
resolve_packages() {
    local mode="${1:-all}"
    RESOLVED_PACKAGES=()
    UNKNOWN_PACKAGES=()

    local lines=() all=() line cand
    mapfile -t lines < <(read_package_lines)
    for line in "${lines[@]}"; do
        IFS='|' read -r -a cands <<< "$line"
        all+=("${cands[@]}")
    done

    declare -A have=()
    while IFS= read -r cand; do have["$cand"]=1; done < <(available_names "${all[@]}")

    declare -A installed=()
    if [[ "$mode" == "missing-only" ]]; then
        while IFS= read -r cand; do installed["$cand"]=1; done \
            < <(rpm -q --qf '%{NAME}\n' "${all[@]}" 2>/dev/null | grep -v 'is not installed')
    fi

    local picked
    for line in "${lines[@]}"; do
        IFS='|' read -r -a cands <<< "$line"
        picked=""
        for cand in "${cands[@]}"; do
            if [[ -n "${installed[$cand]:-}" ]]; then picked="__installed__"; break; fi
        done
        [[ "$picked" == "__installed__" ]] && continue
        for cand in "${cands[@]}"; do
            if [[ -n "${have[$cand]:-}" ]]; then picked="$cand"; break; fi
        done
        if [[ -n "$picked" ]]; then
            RESOLVED_PACKAGES+=("$picked")
        else
            UNKNOWN_PACKAGES+=("$line")
        fi
    done
}

# Installs a list; if the batch transaction fails, retries one by one so a
# single bad package can't block the rest.
install_packages() {
    [[ "$#" -eq 0 ]] && return 0
    if sudo dnf install -y "$@"; then
        return 0
    fi
    warning "Batch install failed; retrying packages individually..."
    FAILED_PACKAGES=()
    local p
    for p in "$@"; do
        sudo dnf install -y "$p" >/dev/null 2>&1 || FAILED_PACKAGES+=("$p")
    done
    if [[ "${#FAILED_PACKAGES[@]}" -gt 0 ]]; then
        warning "Failed to install: ${FAILED_PACKAGES[*]}"
        return 1
    fi
}

# --------------------------------------------------
# Tools Fedora may not package: build into /usr/local/bin
# --------------------------------------------------
# /usr/local/bin is on PATH for every session type, including Hyprland
# launched from GDM, so theme.py's shutil.which("matugen") always finds it.
# ~/.cargo/bin would only exist on PATH inside an interactive shell.

build_rust_tool() {
    local bin="$1" crate="$2"
    command -v "$bin" >/dev/null 2>&1 && return 0
    info "$bin isn't packaged for this Fedora; building $crate with cargo..."
    install_packages cargo rust gcc cmake >/dev/null || true
    local root
    root="$(mktemp -d)"
    if cargo install --locked --root "$root" "$crate" \
        && sudo install -m 0755 "$root/bin/$bin" /usr/local/bin/"$bin"; then
        success "$bin installed to /usr/local/bin."
    else
        warning "Could not build $bin. Install it manually and re-run."
        BUILD_FAILED+=("$bin")
    fi
    rm -rf "$root"
}

build_go_tool() {
    local bin="$1" module="$2"
    command -v "$bin" >/dev/null 2>&1 && return 0
    info "$bin isn't packaged for this Fedora; building $module with go..."
    install_packages golang >/dev/null || true
    local root
    root="$(mktemp -d)"
    if GOBIN="$root" GOPATH="$root/gopath" GOCACHE="$root/cache" go install "$module" \
        && sudo install -m 0755 "$root/$bin" /usr/local/bin/"$bin"; then
        success "$bin installed to /usr/local/bin."
    else
        warning "Could not build $bin. Install it manually and re-run."
        BUILD_FAILED+=("$bin")
    fi
    chmod -R u+w "$root" 2>/dev/null
    rm -rf "$root"
}

# --------------------------------------------------
# Symlinks (same model as upstream install.sh)
# --------------------------------------------------

# link_dotfiles <install|update> [dry-run]
#   install: back up real files that are in the way, then link
#   update:  only link new files, never touch real files
link_dotfiles() {
    local mode="$1" dry="${2:-0}"
    local timestamp backup_dir src rel dest
    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    backup_dir="$HOME/.config-backups/$timestamp"

    LINKED_COUNT=0
    BACKED_UP_COUNT=0
    SKIPPED_REAL_FILES=0
    LINK_FAILED=0
    BACKUP_DIR="$backup_dir"

    mkdir -p "$CONFIG_DIR"

    while IFS= read -r -d '' src; do
        rel="${src#"$SRC"/}"
        is_generated "$rel" && continue
        dest="$CONFIG_DIR/$rel"

        if [[ "$mode" == "update" ]]; then
            [[ -L "$dest" ]] && continue
            if [[ -e "$dest" ]]; then
                warning "A real file exists at $rel; leaving it. Re-run fedora/install.sh to back it up and link it."
                SKIPPED_REAL_FILES=$((SKIPPED_REAL_FILES + 1))
                continue
            fi
            if [[ "$dry" -eq 1 ]]; then
                info "Would link: $rel"
                LINKED_COUNT=$((LINKED_COUNT + 1))
                continue
            fi
            mkdir -p "$(dirname "$dest")"
            ln -s "$src" "$dest"
            LINKED_COUNT=$((LINKED_COUNT + 1))
            continue
        fi

        mkdir -p "$(dirname "$dest")"
        if [[ -L "$dest" ]]; then
            ln -sfn "$src" "$dest"
        elif [[ -e "$dest" ]]; then
            mkdir -p "$backup_dir/config/$(dirname "$rel")"
            mv "$dest" "$backup_dir/config/$rel"
            BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
            ln -s "$src" "$dest"
        else
            ln -s "$src" "$dest"
        fi

        if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
            LINKED_COUNT=$((LINKED_COUNT + 1))
        else
            LINK_FAILED=1
            error "Failed to link $rel"
        fi
    done < <(find "$SRC" \( -type f -o -type l \) -not -path '*/.git/*' -print0)

    [[ "$dry" -eq 1 ]] && return 0

    # ~/.zshrc lives outside ~/.config
    if [[ "$mode" == "install" && -f "$SRC/.zshrc" ]]; then
        if [[ -e "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
            mkdir -p "$backup_dir/home"
            mv "$HOME/.zshrc" "$backup_dir/home/.zshrc"
            BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
        fi
        ln -sfn "$SRC/.zshrc" "$HOME/.zshrc"
    fi

    # Generated files: real copies, created once
    local g
    for g in "${GENERATED_FILES[@]}"; do
        [[ -f "$SRC/$g" ]] || continue
        dest="$CONFIG_DIR/$g"
        if [[ ! -e "$dest" || -L "$dest" ]]; then
            [[ -L "$dest" ]] && rm -f "$dest"
            mkdir -p "$(dirname "$dest")"
            cp "$SRC/$g" "$dest"
        fi
    done
}

# Copies fedora/systemd/*.target into ~/.config/systemd/user. Copied, not
# symlinked: systemd would need `systemctl link`, and a copy keeps working if
# the repo moves. A different existing file is backed up first.
install_session_units() {
    local dry="${1:-0}" unit_dir="$HOME/.config/systemd/user" src dest changed=0
    for src in "$FEDORA_DIR"/systemd/*.target; do
        [[ -f "$src" ]] || continue
        dest="$unit_dir/$(basename "$src")"
        cmp -s "$src" "$dest" && continue
        if [[ "$dry" -eq 1 ]]; then
            info "Would install systemd unit: $(basename "$src")"
            continue
        fi
        mkdir -p "$unit_dir"
        if [[ -e "$dest" ]]; then
            mkdir -p "$HOME/.config-backups/systemd"
            cp "$dest" "$HOME/.config-backups/systemd/$(basename "$src").$(date +%s)"
        fi
        cp "$src" "$dest"
        changed=1
        success "Installed systemd user unit: $(basename "$src")"
    done
    if [[ "$changed" -eq 1 ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
}

run_theme() {
    if command -v python3 >/dev/null 2>&1; then
        python3 "$CONFIG_DIR/43pr/bin/theme.py" "$@"
    else
        warning "python3 not found; skipping theme.py $*"
        return 1
    fi
}
