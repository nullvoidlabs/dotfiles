# 43PR Desktop — Fedora port

Fedora version of [43PR/dotfiles](https://github.com/43PR/dotfiles). Same configs, same symlink model; only the install path and a few distro-specific lines differ. Built against upstream commit `3aeafef` (2026-10-18).

**Requires Fedora 43, 44 or 45 (x86_64).** The config uses Hyprland's Lua format, which needs Hyprland 0.55+. Fedora retired its own hyprland package, so this comes from the `nikromen/hyprland` COPR (0.56.x; the maintainer patches it to build against Fedora's Lua 5.4 on F43/44).

## Install

```bash
git clone https://github.com/43PR/dotfiles.git ~/dotfiles
cd ~/dotfiles
git checkout -b fedora
git am /path/to/0001-Add-Fedora-port.patch
./fedora/install.sh
```

Then log out, pick **Hyprland** from the gear icon on the GDM login screen, and log in.

Flags: `--yes` (no prompts), `--with-hyprmod` (also install HyprMod via pipx), `--skip-packages` (relink + theme only).

## Updating

```bash
cd ~/dotfiles
git fetch origin
git rebase origin/main        # replays the Fedora commit on top of upstream
./fedora/update.sh            # --dry-run, --skip-packages, --skip-theme, --restart-shell
```

`update.sh` warns when upstream's `packages.txt` gains a package that `fedora/packages.txt` doesn't map yet.

## What's different from the Arch version

| Area | Arch (upstream) | Fedora port |
|---|---|---|
| Hyprland, hyprlock, hyprpolkitagent, awww, portal | official repos | COPR `nikromen/hyprland` |
| Quickshell | official repos | Fedora repos, else COPR `errornointernet/quickshell` |
| matugen, starship, eza, cliphist | official repos | dnf if packaged, else built with cargo/go into `/usr/local/bin` |
| Nerd Fonts | `ttf-*-nerd` | Release tarballs into `~/.local/share/fonts/NerdFonts` |
| papirus-folders, hyprmod | AUR | GitHub script / pipx (hyprmod is opt-in) |
| gpu-screen-recorder | official repos | Flathub (official route off Arch) via `hypr/scripts/gsr-toggle.sh` |
| Power profiles | power-profiles-daemon | Fedora's tuned-ppd is left alone; see below |
| Login shell | `chsh` | `usermod` (Fedora doesn't ship `chsh` by default) |

Config edits (all still work on Arch, so the patch stays rebase-friendly):

- `hypr/hyprland.lua`: polkit agent was `/usr/lib/polkit-kde-authentication-agent-1` (not even in upstream's package list); now `hyprpolkitagent` with Fedora and Arch paths. Browser `brave` → `firefox`.
- `hypr/keybinds.lua`: Super+R calls `scripts/gsr-toggle.sh` (native or Flatpak recorder, same pidfile for the OSD).
- `.zshrc`: plugin paths checked for both `/usr/share/zsh/plugins/<name>` (Arch) and `/usr/share/<name>` (Fedora).
- `quickshell/SettingsPages/StoragePage.qml`: YAY/PACMAN cache rows → one DNF CACHE row (`pkexec dnf clean all`).
- `quickshell/hyprquickpaper/cache.sh`: prefers `magick` over the deprecated `convert`.

## Known gaps

- **Settings > Power**: needs `powerprofilesctl`. Fedora Workstation uses tuned-ppd, which conflicts with power-profiles-daemon. The installer won't swap them for you. If you want the page: `sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon`.
- **Settings > System RAM details**: runs `sudo -n /usr/bin/dmidecode`, which needs a NOPASSWD sudoers rule (same as upstream). Only add it if you're fine with that trade-off.
- **Super + L** is bound twice upstream (light/dark toggle and focus-right). Both fire. Rebind one in `hypr/keybinds.lua` if it bothers you.
- **First recording** with the Flatpak recorder asks for your password once (its KMS capture helper needs root).
- After `papirus-icon-theme` updates, re-run `papirus-folders -C white`.
