#!/usr/bin/env bash
# 43PR/dotfiles installer — Fedora port
#
# Usage:
#   ./fedora/install.sh [--yes] [--with-hyprmod] [--skip-packages]
#
#   --yes            don't ask before enabling COPRs / Flathub
#   --with-hyprmod   also install HyprMod (GUI keybind/settings editor) via pipx
#   --with-brave     add Brave's official RPM repo and install brave-browser
#   --skip-packages  only (re)link configs and regenerate the theme
#
# What it does (same end state as upstream install.sh on Arch):
#   1. Enables the COPRs Fedora needs for Hyprland 0.56 + Quickshell
#   2. Installs fedora/packages.txt with dnf (first available name per line)
#   3. Builds anything Fedora doesn't package (matugen, starship, eza, cliphist)
#      into /usr/local/bin, fetches Nerd Fonts, papirus-folders, gpu-screen-recorder
#   4. Symlinks .config/ into ~/.config (backs up anything it replaces)
#   5. Enables services, sets zsh as login shell, generates the initial theme

set -uo pipefail

# shellcheck source=fedora/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ASSUME_YES=0
WITH_HYPRMOD=0
WITH_BRAVE=0
SKIP_PACKAGES=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y)        ASSUME_YES=1 ;;
        --with-hyprmod)  WITH_HYPRMOD=1 ;;
        --with-brave)    WITH_BRAVE=1 ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
        *) error "Unknown option: $arg"; exit 1 ;;
    esac
done

confirm() {
    [[ "$ASSUME_YES" -eq 1 ]] && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

require_fedora
load_generated_files

FEDORA_VER="$(fedora_version)"
info "Detected: ${PRETTY_NAME:-Fedora $FEDORA_VER}"

if [[ "$FEDORA_VER" =~ ^[0-9]+$ && "$FEDORA_VER" -lt 43 ]]; then
    warning "Fedora $FEDORA_VER is older than what the Hyprland COPR builds for (43+)."
    warning "Hyprland 0.56 (needed for this config's .lua files) will probably not install."
    confirm "Continue anyway?" || exit 1
fi

BUILD_FAILED=()
UNKNOWN_PACKAGES=()
RESOLVED_PACKAGES=()

# --------------------------------------------------
# Third-party repos
# --------------------------------------------------

if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
    cat <<EOF

This installer adds third-party package sources. Packages from them install
as root, so you're trusting their maintainers the same way you'd trust the AUR:

  COPR    $COPR_HYPRLAND   (Hyprland 0.56.x, hyprlock, hyprpolkitagent, awww, portal)
  COPR    $COPR_QUICKSHELL   (only if Fedora's own repos lack quickshell)
  Flathub com.dec05eba.gpu_screen_recorder   (screen recorder, Super+R)

Fedora itself retired its hyprland package, and 0.56 is required because
this config uses Hyprland's Lua format.
EOF
    if ! confirm "Enable these and continue?"; then
        error "Aborted. Nothing was changed."
        exit 1
    fi

    if ! ensure_copr_command; then
        error "Could not install the dnf copr plugin."
        exit 1
    fi

    enable_copr "$COPR_HYPRLAND" || { error "Failed to enable $COPR_HYPRLAND"; exit 1; }

    sudo dnf makecache -q >/dev/null 2>&1 || true
    if [[ -z "$(available_names quickshell quickshell-git)" ]]; then
        enable_copr "$COPR_QUICKSHELL" || warning "Failed to enable $COPR_QUICKSHELL"
    fi

    # ----------------------------------------------
    # Packages
    # ----------------------------------------------

    info "Resolving fedora/packages.txt against enabled repos..."
    resolve_packages all
    info "Installing ${#RESOLVED_PACKAGES[@]} package(s)..."
    install_packages "${RESOLVED_PACKAGES[@]}" \
        && success "dnf packages installed." \
        || warning "Some packages failed; continuing."

    # Hyprland must be new enough for the Lua config, or the session will
    # start with a blank error screen.
    if command -v Hyprland >/dev/null 2>&1; then
        hypr_ver="$(rpm -q --qf '%{VERSION}' hyprland 2>/dev/null || true)"
        if [[ -n "$hypr_ver" ]] && [[ "$(printf '%s\n0.55.0\n' "$hypr_ver" | sort -V | head -n1)" != "0.55.0" ]]; then
            warning "hyprland $hypr_ver is installed but this config needs 0.55+ (Lua config)."
            warning "Check: dnf list --showduplicates hyprland   (it should come from $COPR_HYPRLAND)"
        fi
    else
        warning "Hyprland did not install. Check: sudo dnf install hyprland"
    fi

    # ----------------------------------------------
    # Not packaged by Fedora: build or fetch
    # ----------------------------------------------

    build_rust_tool matugen  matugen
    build_rust_tool starship starship
    build_rust_tool eza      eza
    build_go_tool   cliphist go.senan.xyz/cliphist@latest

    if ! command -v awww >/dev/null 2>&1; then
        warning "awww (wallpaper daemon) is missing. It ships in $COPR_HYPRLAND; check: sudo dnf install awww"
        BUILD_FAILED+=("awww")
    fi

    # Nerd Fonts (Arch: ttf-jetbrains-mono-nerd, ttf-iosevka-nerd)
    font_root="$HOME/.local/share/fonts/NerdFonts"
    for font in JetBrainsMono Iosevka; do
        if fc-list 2>/dev/null | grep -qi "${font} Nerd Font"; then
            info "$font Nerd Font already installed."
            continue
        fi
        info "Downloading $font Nerd Font..."
        tmp="$(mktemp -d)"
        if curl -fL --retry 2 -o "$tmp/$font.tar.xz" \
                "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.tar.xz" \
            && mkdir -p "$font_root/$font" \
            && tar -xJf "$tmp/$font.tar.xz" -C "$font_root/$font"; then
            success "$font Nerd Font installed."
        else
            warning "Could not download $font Nerd Font."
            BUILD_FAILED+=("$font Nerd Font")
        fi
        rm -rf "$tmp"
    done
    fc-cache -f >/dev/null 2>&1 || true

    # papirus-folders (AUR on Arch). Installed to /usr/local/bin so you can
    # re-run it: papirus-icon-theme updates reset the folder color.
    if ! command -v papirus-folders >/dev/null 2>&1; then
        info "Installing papirus-folders..."
        tmp="$(mktemp -d)"
        if git clone -q --depth 1 https://github.com/PapirusDevelopmentTeam/papirus-folders.git "$tmp/pf" \
            && sudo install -m 0755 "$tmp/pf/papirus-folders" /usr/local/bin/papirus-folders; then
            success "papirus-folders installed."
        else
            warning "Could not install papirus-folders."
        fi
        rm -rf "$tmp"
    fi
    if command -v papirus-folders >/dev/null 2>&1; then
        if papirus-folders -C white; then
            success "Papirus folders set to white."
        else
            warning "papirus-folders couldn't set the color. Run manually: papirus-folders -C white"
        fi
    fi

    # gpu-screen-recorder: Flathub is the officially supported route off Arch.
    # System-wide so it can capture monitors on AMD/Intel (KMS needs root).
    if ! command -v gpu-screen-recorder >/dev/null 2>&1 \
        && ! flatpak info com.dec05eba.gpu_screen_recorder >/dev/null 2>&1; then
        info "Installing gpu-screen-recorder from Flathub..."
        sudo flatpak remote-add --if-not-exists --system flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
        if sudo flatpak install -y --noninteractive --system flathub com.dec05eba.gpu_screen_recorder; then
            success "gpu-screen-recorder installed (Flatpak)."
        else
            warning "gpu-screen-recorder failed to install. If Flathub is filtered, run:"
            warning "  sudo flatpak remote-modify --no-filter --enable flathub"
            BUILD_FAILED+=("gpu-screen-recorder")
        fi
    fi

    # HyprMod (optional GUI editor; AUR-only upstream)
    if [[ "$WITH_HYPRMOD" -eq 1 ]] && ! command -v hyprmod >/dev/null 2>&1; then
        info "Installing HyprMod with pipx..."
        install_packages pipx python3-gobject gtk4 libadwaita >/dev/null || true
        if pipx install "git+https://github.com/BlueManCZ/hyprmod.git" && "$HOME/.local/bin/hyprmod" --install; then
            success "HyprMod installed."
        else
            warning "HyprMod install failed; it's optional."
        fi
    fi

    # Brave (Super + B prefers it; falls back to Firefox). Official repo, opt-in.
    if [[ "$WITH_BRAVE" -eq 1 ]] && ! command -v brave-browser >/dev/null 2>&1; then
        info "Adding Brave's RPM repo and installing brave-browser..."
        if sudo dnf config-manager addrepo --overwrite \
                --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
            && install_packages brave-browser; then
            success "Brave installed."
        else
            warning "Brave install failed; Super + B will open Firefox."
        fi
    fi

    # ----------------------------------------------
    # Power profiles
    # ----------------------------------------------
    # Fedora 41+ ships tuned-ppd, which speaks the power-profiles-daemon D-Bus
    # API but conflicts with the power-profiles-daemon package. The settings
    # page shells out to `powerprofilesctl`, so we only add PPD when nothing
    # else is managing power profiles.

    if command -v powerprofilesctl >/dev/null 2>&1; then
        info "powerprofilesctl available."
    elif rpm -q tuned-ppd >/dev/null 2>&1; then
        warning "tuned-ppd manages power profiles here, but the Settings > Power page needs powerprofilesctl."
        warning "To use it, swap the daemons (your choice; it changes system power management):"
        warning "  sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon"
    else
        install_packages power-profiles-daemon \
            && sudo systemctl enable --now power-profiles-daemon.service >/dev/null 2>&1 \
            && success "power-profiles-daemon enabled."
    fi
fi

# --------------------------------------------------
# Login shell
# --------------------------------------------------

ZSH_PATH="$(command -v zsh || true)"
if [[ -n "$ZSH_PATH" ]]; then
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$(basename "$current_shell")" != "zsh" ]]; then
        info "Setting zsh as your login shell..."
        # Fedora doesn't install chsh by default (util-linux-user); usermod is always there
        if sudo usermod --shell "$ZSH_PATH" "$USER"; then
            success "Login shell changed to zsh (takes effect next login)."
        else
            warning "Failed to change the login shell."
        fi
    fi
else
    warning "zsh is not installed; skipping login shell change."
fi

# --------------------------------------------------
# Link dotfiles
# --------------------------------------------------

info "Linking dotfiles..."
find "$SRC" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} \;
link_dotfiles install

if [[ "$LINK_FAILED" -eq 1 ]]; then
    error "One or more files failed to link. See errors above."
else
    success "Dotfiles linked ($LINKED_COUNT file(s))."
fi
if [[ "$BACKED_UP_COUNT" -gt 0 ]]; then
    info "Replaced $BACKED_UP_COUNT existing file(s); originals saved to: $BACKUP_DIR"
fi

# --------------------------------------------------
# Directories, services
# --------------------------------------------------

xdg-user-dirs-update >/dev/null 2>&1 || true
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALLPAPER_DIR" "$HOME/Pictures/Screenshots"

for wp in "$REPO_DIR"/wallhaven-*.jpg; do
    [[ -f "$wp" && ! -e "$WALLPAPER_DIR/$(basename "$wp")" ]] && cp "$wp" "$WALLPAPER_DIR/"
done

install_session_units
fix_gtk_cursor_size
set_default_apps

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1 || true
    if rpm -q bluez >/dev/null 2>&1; then
        sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
    fi
fi

# --------------------------------------------------
# Theme
# --------------------------------------------------

THEME_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/43pr/state.json"
first_wp="$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print -quit 2>/dev/null)"
if [[ -n "$first_wp" ]] && ! { [[ -f "$THEME_STATE" ]] && grep -q '"wallpaper":' "$THEME_STATE"; }; then
    info "Setting initial wallpaper and colors from $(basename "$first_wp")..."
    run_theme wallpaper "$first_wp" || warning "Could not apply the wallpaper (is matugen installed?)."
fi

info "Generating initial theme..."
run_theme apply || warning "Initial theme generation failed."

# --------------------------------------------------
# Summary
# --------------------------------------------------

printf '\n\033[1;32m========================================\033[0m\n'
printf '\033[1;32m   43PR Hyprland Setup Ready (Fedora)   \033[0m\n'
printf '\033[1;32m========================================\033[0m\n\n'
printf 'Distribution:  %s\n' "${PRETTY_NAME:-Fedora}"
printf 'Hyprland:      %s\n' "$(rpm -q hyprland 2>/dev/null || echo 'not installed')"
printf 'Configuration: %s -> %s\n' "$CONFIG_DIR" "$SRC"

# Drop entries that were built/fetched above instead of coming from dnf
still_missing=()
for entry in "${UNKNOWN_PACKAGES[@]}"; do
    command -v "${entry%%|*}" >/dev/null 2>&1 || still_missing+=("$entry")
done
if [[ "${#still_missing[@]}" -gt 0 ]]; then
    warning "Not found in any enabled repo (install manually or ignore): ${still_missing[*]}"
fi
if [[ "${#BUILD_FAILED[@]}" -gt 0 ]]; then
    warning "Needs attention: ${BUILD_FAILED[*]}"
fi

cat <<'EOF'

Next:
  1. Log out. On the GDM login screen, click your name, then the gear icon,
     and pick "Hyprland".
  2. Put wallpapers in ~/Pictures/Wallpapers, then Super + W to pick one.
  3. Don't move or delete this repo: ~/.config points into it.

See fedora/README.md for what changed vs. the Arch version.
EOF

success "Installation complete!"
