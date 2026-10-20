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

Flags: `--yes` (no prompts), `--with-brave` (add Brave's official repo and install it), `--with-hyprmod` (also install HyprMod via pipx), `--skip-packages` (relink + theme only).

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

- `hypr/hyprland.lua`:
  - Polkit agent was `/usr/lib/polkit-kde-authentication-agent-1` (not in upstream's package list); now `hyprpolkitagent` with Fedora and Arch paths.
  - Browser: `brave-browser`, falling back to the Brave Flatpak, then Firefox (upstream's `brave` command doesn't exist on Fedora).
  - Touchpad `natural_scroll = true`: content follows your fingers.
- `hypr/keybinds.lua`: screenshots on **Print** (full) and **Shift + Print** (area) instead of Delete / Shift + Delete, so Delete works as Delete again. Fn brightness keys step 2% instead of 5%.
- `quickshell/Wheel.qml` (Super + S): dims the screen behind it, adds a backdrop disc, fills the segments and strengthens the lines so it reads on busy windows. Brightness item: click/Enter brightens, right-click dims, scroll works both ways, 2% steps.
- `hypr/rules.lua` + `scripts/opacity.sh`: Super + O saves to `~/.local/state/43pr/opacity` instead of editing `rules.lua`, so the repo stays clean (default 70%).
- `hypr/.luarc.json`: tells Lua language servers that `hl` and the shared config globals exist, so editors stop flagging every line.
- `gtk-3.0/gtk-4.0 settings.ini`: cursor size 14 → 24. See "Cursor size" below.
- `hypr/keybinds.lua`: Super+R calls `scripts/gsr-toggle.sh` (native or Flatpak recorder, same pidfile for the OSD).
- `.zshrc`: plugin paths checked for both `/usr/share/zsh/plugins/<name>` (Arch) and `/usr/share/<name>` (Fedora).
- `quickshell/SettingsPages/StoragePage.qml`: YAY/PACMAN cache rows → one DNF CACHE row (`pkexec dnf clean all`).
- `quickshell/SettingsPages/UpdatesPage.qml`: counts and installs system updates with dnf (`repoquery --upgrades`, `dnf upgrade --refresh`); "Update desktop" runs `fedora/update.sh`. AUR row shows N/A.
- Wallpaper picker (Super + W):
  - `cache.sh`: one run at a time (reopening the picker started a second run that wrote half-finished thumbnails), atomic writes, parallel jobs capped at CPU count with one thread each, `.webp` thumbnails, stale thumbnails removed, prefers `magick` over `convert`.
  - `shell.qml`: tile shadows rendered at quarter resolution (full-size blur on every tile, every frame, was the main scroll lag); thumbnail retries back off and stop after ~1 min; keyboard works: ←/→ (or H/L, A/D, Shift for 3), Home/End, Enter/Space to apply. Before, arrows moved a different internal index than the highlight, so Space could apply the wrong wallpaper.
- `hypr/hyprland.lua` autostart: imports the session environment into systemd/D-Bus and starts `hyprland-session.target` (installed from `fedora/systemd/` into `~/.config/systemd/user/`). Without it, `xdg-desktop-portal` fails with result `dependency` because `graphical-session.target` is never active under a bare Hyprland session. Apps then fall back to built-in file pickers (Enter doesn't save in Brave's) and screen sharing breaks.

## Desktop integration a bare Hyprland session doesn't do for you

The installer and `update.sh` handle these; each only acts when you haven't already chosen something.

- **File type detection.** Outside GNOME/KDE, `xdg-open` falls back to `file --mime-type`, which sniffs contents. Text-based formats like Proxmox SPICE `.vv` files then look like `text/plain` and open in whatever claims plain text (calibre). `perl-File-MimeInfo` provides `mimetype`, which matches by extension, and `xdg-open` prefers it.
- **Default apps** (`~/.config/mimeapps.list`, shared with GNOME): `.vv` → remote-viewer, `text/plain` → xed (only if unset or calibre), default browser → Brave (only if unset or Firefox).
- **Portals.** `hyprland-session.target` (see above) so file pickers and screen sharing work.

## Cursor size

Hyprland keeps `XCURSOR_SIZE=14` (upstream's value). Cursor themes ship fixed sizes (Adwaita: 24, 32, 48…), and Hyprland snaps 14 to the nearest real one, so it looks like 24. GNOME draws vector cursors at the exact requested size, so the same 14 in the shared GTK settings made the cursor tiny when switching back to GNOME. The GTK files now say 24, which looks identical in Hyprland and normal in GNOME. Existing installs with exactly 14 are migrated; any other value is left alone.

If GNOME's cursor is still small, nwg-look or a GNOME setting changed it globally: `gsettings reset org.gnome.desktop.interface cursor-size`.

## Known gaps

- **Settings > Power**: needs `powerprofilesctl`. Fedora Workstation uses tuned-ppd, which conflicts with power-profiles-daemon. The installer won't swap them for you. If you want the page: `sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon`.
- **Settings > System RAM details**: runs `sudo -n /usr/bin/dmidecode`, which needs a NOPASSWD sudoers rule (same as upstream). Only add it if you're fine with that trade-off.
- **Super + L** is bound twice upstream (light/dark toggle and focus-right). Both fire. Rebind one in `hypr/keybinds.lua` if it bothers you.
- **First recording** with the Flatpak recorder asks for your password once (its KMS capture helper needs root).
- After `papirus-icon-theme` updates, re-run `papirus-folders -C white`.
- **COPR in-between states**: `dnf upgrade` may print "Skipping packages with conflicts: hyprtoolkit" / "broken dependencies: hyprland-guiutils" right after the maintainer bumps a library but before rebuilding everything that uses it. dnf keeps your installed pair consistent; just upgrade again in a few days. Don't use `--allowerasing`: `hyprland` requires `hyprland-guiutils`.
- **Shared with GNOME**: GTK settings, `mimeapps.list` and `org.gnome.desktop.interface` are the same files/keys in both sessions. The light/dark toggle (Super + L) also flips GNOME's color scheme.
- **zsh-autocomplete**: upstream's `.zshrc` sources it but it isn't in upstream's package list, and Fedora doesn't package it. The installer clones it to `~/.local/share/zsh/zsh-autocomplete` at the newest release tag; `.zshrc` checks the Arch path, a distro path, then that clone. On first shell start it may clone a helper (`zasync`) into `~/.cache/zsh`.
- **Opacity**: Super + O sets every window's opacity (upstream default is now 70%).
