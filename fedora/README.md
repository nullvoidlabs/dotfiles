# 43PR Desktop — Fedora port

Fedora port of [43PR/dotfiles](https://github.com/43PR/dotfiles) by **43PR**. All design, configs and the Quickshell desktop are his work; this branch only adapts installation and a few distro-specific lines for Fedora. Maintained by [NullVoidLabs](https://nullvoidlabs.io). If you like the setup, support the original author ([YouTube](https://www.youtube.com/@43PR2), [Ko-fi](https://ko-fi.com/43pr)).

Same configs, same symlink model. Last rebased onto upstream commit `7274604` (2026-10-19).

**Requires Fedora 43, 44 or 45 (x86_64).** The config uses Hyprland's Lua format, which needs Hyprland 0.55+. Fedora retired its own hyprland package, so this comes from the `nikromen/hyprland` COPR (0.56.x; the maintainer patches it to build against Fedora's Lua 5.4 on F43/44).

## Install

```bash
git clone -b fedora https://github.com/nullvoidlabs/dotfiles.git ~/dotfiles
cd ~/dotfiles
./fedora/install.sh
```

Then log out, pick **Hyprland** from the gear icon on the GDM login screen, and log in.

Flags: `--yes` (no prompts), `--with-hyprmod` (also install HyprMod via pipx), `--skip-packages` (relink + theme only).

## Updating

```bash
cd ~/dotfiles
git pull                      # this fork's fedora branch
./fedora/update.sh            # --dry-run, --skip-packages, --skip-theme, --restart-shell
```

The Settings → Updates page runs the same thing ("Update desktop") and uses dnf for system packages.

Maintainer flow for pulling in new upstream work:

```bash
git remote add upstream https://github.com/43PR/dotfiles.git   # once
git fetch upstream
git rebase upstream/main      # replays the Fedora commits on top
git push --force-with-lease origin fedora
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
- `quickshell/SettingsPages/UpdatesPage.qml`: counts and installs system updates with dnf (`repoquery --upgrades`, `dnf upgrade --refresh`); "Update desktop" runs `fedora/update.sh`. AUR row shows N/A.
- `quickshell/hyprquickpaper/cache.sh`: prefers `magick` over the deprecated `convert`.
- `hypr/hyprland.lua` autostart: imports the session environment into systemd/D-Bus and starts `hyprland-session.target` (installed from `fedora/systemd/` into `~/.config/systemd/user/`). Without it, `xdg-desktop-portal` fails with result `dependency` because `graphical-session.target` is never active under a bare Hyprland session. Apps then fall back to built-in file pickers (Enter doesn't save in Brave's) and screen sharing breaks.

## Known gaps

- **Settings > Power**: needs `powerprofilesctl`. Fedora Workstation uses tuned-ppd, which conflicts with power-profiles-daemon. The installer won't swap them for you. If you want the page: `sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon`.
- **Settings > System RAM details**: runs `sudo -n /usr/bin/dmidecode`, which needs a NOPASSWD sudoers rule (same as upstream). Only add it if you're fine with that trade-off.
- **Super + L** is bound twice upstream (light/dark toggle and focus-right). Both fire. Rebind one in `hypr/keybinds.lua` if it bothers you.
- **First recording** with the Flatpak recorder asks for your password once (its KMS capture helper needs root).
- After `papirus-icon-theme` updates, re-run `papirus-folders -C white`.
