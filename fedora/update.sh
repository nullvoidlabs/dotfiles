#!/usr/bin/env bash
# 43PR/dotfiles updater — Fedora port
#
# Usage (from the repo root, after pulling):
#   ./fedora/update.sh
#   ./fedora/update.sh --dry-run
#   ./fedora/update.sh --skip-packages
#   ./fedora/update.sh --skip-theme
#   ./fedora/update.sh --restart-shell
#
# Configs are symlinks into this repo, so `git pull` already updated them.
# This only installs new packages, links new files, and regenerates the theme.

set -uo pipefail

# shellcheck source=fedora/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DRY_RUN=0
SKIP_PACKAGES=0
SKIP_THEME=0
RESTART_SHELL=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)       DRY_RUN=1 ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-theme)    SKIP_THEME=1 ;;
        --restart-shell) RESTART_SHELL=1 ;;
        -h|--help)       sed -n '2,13p' "$0"; exit 0 ;;
        *) error "Unknown option: $arg"; exit 1 ;;
    esac
done

require_fedora
load_generated_files

UNKNOWN_PACKAGES=()
RESOLVED_PACKAGES=()

# --------------------------------------------------
# Packages
# --------------------------------------------------

if [[ "$SKIP_PACKAGES" -eq 1 ]]; then
    info "Skipping packages (--skip-packages)."
else
    resolve_packages missing-only
    if [[ "${#RESOLVED_PACKAGES[@]}" -eq 0 ]]; then
        info "Packages: everything in fedora/packages.txt is installed."
    elif [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would install (${#RESOLVED_PACKAGES[@]}): ${RESOLVED_PACKAGES[*]}"
    else
        info "Installing new packages: ${RESOLVED_PACKAGES[*]}"
        install_packages "${RESOLVED_PACKAGES[@]}" || warning "Some packages failed; continuing."
    fi

    # Upstream only maintains the Arch list. Flag names it added that this
    # port hasn't mapped yet so they don't silently go missing.
    if [[ -f "$REPO_DIR/packages.txt" ]]; then
        mapfile -t arch_pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]\+//g' "$REPO_DIR/packages.txt" | sed '/^$/d')
        fedora_map="$(cat "$PACKAGE_FILE")"
        unmapped=()
        for p in "${arch_pkgs[@]}"; do
            grep -qiF -- "$p" <<< "$fedora_map" || unmapped+=("$p")
        done
        if [[ "${#unmapped[@]}" -gt 0 ]]; then
            warning "Upstream packages.txt has entries not in fedora/packages.txt: ${unmapped[*]}"
            warning "Find the Fedora name with 'dnf search <name>' and add it to fedora/packages.txt."
        fi
    fi
fi

# --------------------------------------------------
# Link new files
# --------------------------------------------------

link_dotfiles update "$DRY_RUN"

if [[ "$LINKED_COUNT" -eq 0 ]]; then
    success "No new files to link."
elif [[ "$DRY_RUN" -eq 0 ]]; then
    success "Linked $LINKED_COUNT new file(s)."
fi
[[ "$SKIPPED_REAL_FILES" -gt 0 ]] && warning "$SKIPPED_REAL_FILES file(s) skipped; see warnings above."

if [[ "$DRY_RUN" -eq 1 ]]; then
    info "Dry run: nothing was written."
    exit 0
fi

# --------------------------------------------------
# Theme
# --------------------------------------------------

if [[ "$SKIP_THEME" -eq 1 ]]; then
    info "Skipping theme regeneration (--skip-theme)."
else
    info "Regenerating theme..."
    run_theme apply && success "Theme regenerated." || { error "Theme regeneration failed."; exit 1; }
fi

# --------------------------------------------------
# Quickshell
# --------------------------------------------------

if [[ "$RESTART_SHELL" -eq 1 ]]; then
    info "Restarting Quickshell..."
    pkill -x qs 2>/dev/null || true
    sleep 1
    setsid qs >/dev/null 2>&1 &
    disown
    success "Quickshell restarted."
else
    warning "Quickshell not restarted. If .qml files changed, re-run with --restart-shell."
fi

if [[ "${#UNKNOWN_PACKAGES[@]}" -gt 0 ]]; then
    warning "Not found in any enabled repo: ${UNKNOWN_PACKAGES[*]}"
fi

success "Update complete."
