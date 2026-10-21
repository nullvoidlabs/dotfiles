# 43PR Desktop — Fedora port

A Fedora port of [43PR/dotfiles](https://github.com/43PR/dotfiles), a Hyprland + Quickshell desktop by **43PR**. The design, configs and Quickshell desktop are his. This fork:

- makes it install and run on Fedora (dnf, COPRs, Flathub instead of pacman and the AUR);
- fixes what a bare Hyprland session on Fedora doesn't do on its own (file pickers, file associations, cursor size shared with GNOME);
- adds a handful of usability fixes found while daily-driving it (wallpaper picker, Super + S menu, keybinds, touchpad);
- ships [backup and restore scripts](#backup-and-restore), so trying it out is reversible: your old configs, GNOME settings, login shell and packages can all be put back.

Everything stays compatible with Arch, so the Fedora commits rebase cleanly onto new upstream work. Maintained by [NullVoidLabs](https://nullvoidlabs.io).

If you like the setup, support the original author: [YouTube](https://www.youtube.com/@43PR2) · [Ko-fi](https://ko-fi.com/43pr) · [Discord](https://discord.gg/HQwU9SzHj)

> Last rebased onto upstream commit `7274604` (2026-10-19).

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Backup and restore](#backup-and-restore)
- [Updating](#updating)
- [Keybinds that differ from upstream](#keybinds-that-differ-from-upstream)
- [Finding your way around the config](#finding-your-way-around-the-config)
- [What's different from upstream](#whats-different-from-upstream)
- [Living alongside GNOME](#living-alongside-gnome)
- [Known issues](#known-issues)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Credits and license](#credits-and-license)

## Requirements

- **Fedora 43, 44 or 45, x86_64.** Tested on Fedora 44 Workstation, logging in from GDM.
- The config uses Hyprland's **Lua** format, which needs **Hyprland 0.55+**. Fedora retired its own `hyprland` package, so it comes from the [`nikromen/hyprland`](https://github.com/nikromen/hyprland-rpm) COPR (0.56.x, patched to build against Fedora's Lua 5.4 on F43/44).
- A clean-ish setup is easiest. Anything the installer replaces in `~/.config` is backed up first.

## Install

```bash
git clone -b fedora https://github.com/nullvoidlabs/dotfiles.git ~/dotfiles
cd ~/dotfiles
./fedora/backup.sh --snapshot     # recommended: lets restore.sh undo everything later
./fedora/install.sh
```

If you skip `backup.sh`, the installer offers to run it for you on a first install (without the btrfs snapshot). Either way, copy the backup's `.tar.gz` off the machine; see [Backup and restore](#backup-and-restore).

Then log out. On the GDM login screen, click your name, then the gear icon, pick **Hyprland**, and log in. Put wallpapers in `~/Pictures/Wallpapers` and press **Super + W**.

**Don't move or delete `~/dotfiles` afterwards.** `~/.config` is symlinked into it. If you do move it, run `./fedora/install.sh --skip-packages` from the new location to repoint the links.

| Flag | Effect |
|---|---|
| `--yes` | No prompts |
| `--with-brave` | Add Brave's official RPM repo and install `brave-browser` (Super + B prefers Brave, falls back to Firefox) |
| `--with-hyprmod` | Also install [HyprMod](https://github.com/BlueManCZ/hyprmod), a GUI keybind/settings editor, via pipx |
| `--skip-packages` | Only relink configs, install the systemd unit, regenerate the theme |
| `--no-backup` | Don't offer to run `fedora/backup.sh` first |

What the installer does:

0. On a first install, offers to run [`fedora/backup.sh`](#backup-and-restore) so you can undo everything later.
1. Asks before enabling third-party sources: COPR `nikromen/hyprland`, COPR `errornointernet/quickshell` (only if Fedora's repos lack Quickshell), Flathub for gpu-screen-recorder.
2. Installs [`fedora/packages.txt`](packages.txt) with dnf. Each line may list alternatives; the first one available wins, and anything missing is reported at the end instead of aborting.
3. Builds what Fedora doesn't package (matugen, starship, eza, cliphist) into `/usr/local/bin`, and fetches Nerd Fonts, papirus-folders and zsh-autocomplete.
4. Symlinks `.config/` into `~/.config`, with backups to `~/.config-backups/<timestamp>/`.
5. Installs `hyprland-session.target`, sets zsh as your login shell, sets default apps only where none are set, and generates the initial theme.

## Backup and restore

Take a backup **before** the first install (the installer offers to). It's what lets you go back to your old desktop cleanly.

```bash
./fedora/backup.sh               # --out DIR, --snapshot (btrfs snapshot of /home too)
```

It saves, to `~/43pr-backups/pre-43pr-<timestamp>/` plus a single `.tar.gz`:

- every `~/.config` entry this repo manages, `~/.zshrc`, `~/.config/mimeapps.list`;
- the fonts, zsh plugin and state folders the installer adds;
- GNOME settings (`dconf dump /`) and your login shell;
- installed packages, repo files, Flatpaks, `/usr/local/bin`, and the last dnf transaction ID.

**Copy the `.tar.gz` off the machine** (NAS, another host, USB drive). Don't keep it inside `~/dotfiles`, and don't publish it: `dconf.ini` holds your GNOME settings.

To go back:

```bash
./fedora/restore.sh                       # newest pre-install backup in ~/43pr-backups
./fedora/restore.sh path/to/backup.tar.gz # or a specific one
./fedora/restore.sh --configs-only        # files, settings, shell; leave packages alone
```

Each step asks first (`--yes` skips the prompts):

1. **Configs**: current versions are moved to `~/43pr-backups/replaced-<timestamp>/`, never deleted, and the backed-up ones are unpacked. Anything that didn't exist before stays gone.
2. **GNOME settings and login shell.**
3. **Packages**: `sudo dnf history rollback <id>` to the recorded transaction. dnf lists every change and asks before applying, and the list includes anything else you installed since the backup. Then it removes COPRs and repo files added since, the Flatpak recorder, the tools built into `/usr/local/bin`, and resets papirus-folders.

Then log out and pick GNOME. `~/dotfiles` itself is left alone; delete it when you're done.

## Updating

```bash
cd ~/dotfiles
git pull
./fedora/update.sh            # --dry-run, --skip-packages, --skip-theme, --restart-shell
```

**Settings → Updates** does the same from the desktop. It counts and installs dnf and Flatpak updates, and "Update desktop" runs `fedora/update.sh`.

`update.sh` installs newly listed packages, links new files, never overwrites real files you created, and warns when upstream's `packages.txt` gains something `fedora/packages.txt` doesn't cover yet.

<details>
<summary>Maintainer: pulling in new upstream work</summary>

```bash
git remote add upstream https://github.com/43PR/dotfiles.git   # once
git fetch upstream
git rebase upstream/main          # replays the Fedora commits on top
git push --force-with-lease origin fedora
```

After a rebase, grep new upstream code for Arch-only commands (`pacman`, `checkupdates`, `paru`, `yay`, `/usr/share/zsh/plugins`, `/usr/lib/`) and update the "Last rebased" commit above.
</details>

## Keybinds that differ from upstream

Everything else matches [upstream's keybind table](../README.md#keybinds).

| Keybind | Upstream | This fork |
|---|---|---|
| `Print` | — | Screenshot, full screen |
| `Shift + Print` | — | Screenshot, area select |
| `Delete` / `Shift + Delete` | Screenshots | Normal Delete |
| `Fn + Brightness` | 5% steps | 2% steps |
| `Super + Shift + T` | — | Light/dark theme toggle |
| `Super + L` | Focus right **and** light/dark toggle (both fired) | Focus right only |
| `Super + B` | `brave` (doesn't exist on Fedora) | Brave → Brave Flatpak → Firefox |
| Touchpad, 2-finger **press** | Left click | Right click (3 fingers = middle) |
| Touchpad scrolling | Traditional | Natural (content follows your fingers) |

**Super + S** (quick actions): the brightness item now responds to click/Enter (brighter) and right-click (dimmer) as well as scrolling.

**Super + W** (wallpaper picker): ← / → (also H/L, A/D; hold Shift to move 3), Home / End, Enter or Space to apply, Esc or W to close. Click a tile to select it, click it again to apply.

## Finding your way around the config

Hyprland 0.55+ is configured in **Lua**, split across several files instead of one `hyprland.conf`. Everything below is in `~/dotfiles/.config/hypr/`. Edit it there (`~/.config/hypr/` points at the same files).

| File | What's in it |
|---|---|
| `hyprland.lua` | Main file: programs (`terminal`, `browser`, ...), autostart, environment variables, input/touchpad; loads the others |
| `keybinds.lua` | All keybinds |
| `rules.lua` | Window rules: floating, opacity, sizes |
| `look.lua` | Gaps, borders, blur, animations |
| `monitors.lua` | Monitor layout, workspace-to-monitor rules |
| `hyprlock.conf` | Lock screen (Super + Tab); hyprlock still uses the classic format |
| `hyprland-gui.lua` | Written by HyprMod, if you use it; loaded last |
| `scripts/` | Helpers the binds call: screenshots, opacity picker, recorder, wallpaper restore |
| `.luarc.json` | Tells Lua editors that `hl` and the shared globals exist |

Load order: `hyprland.lua` → Settings → Input state → `monitors` → `keybinds` → `look` → Settings → Appearance state → `rules` → `hyprland-gui`. Later files win when they set the same thing.

**Settings saved from the desktop override these files.** They live outside the repo and are loaded on top:

| Saved by | File | Overrides |
|---|---|---|
| Settings → Input | `~/.config/quickshell/state/devices.lua` | Touchpad and mouse options |
| Settings → Appearance | `~/.config/quickshell/state/look.lua` | `look.lua` values |
| Settings → Display | `~/.config/quickshell/state/display.lua` | Monitor layout |
| Super + O | `~/.local/state/43pr/opacity` | Window opacity in `rules.lua` |

If a config change seems to do nothing, check whether one of these sets the same option.

Quick tips:

- Apply changes with `hyprctl reload`. If the config has an error, Hyprland shows it on screen.
- Find a bind: `grep -n '" + L"' ~/dotfiles/.config/hypr/keybinds.lua`.
- Find a window's class for a rule: `hyprctl clients | grep class`, or `hyprctl activewindow`.
- A bind looks like `hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("command"))`. `..` joins strings in Lua; `--` starts a comment.

## What's different from upstream

### Packaging

| Area | Arch (upstream) | Fedora port |
|---|---|---|
| Hyprland, hyprlock, hyprpolkitagent, awww, portal | Official repos | COPR `nikromen/hyprland` |
| Quickshell | Official repos | Fedora repos, else COPR `errornointernet/quickshell` |
| matugen, starship, eza, cliphist | Official repos | dnf if packaged, else built with cargo/go into `/usr/local/bin` |
| zsh-autocomplete | Expected at the Arch path (not in upstream's package list) | Cloned at its newest release tag into `~/.local/share/zsh/zsh-autocomplete` |
| Nerd Fonts | `ttf-*-nerd` | Release tarballs into `~/.local/share/fonts/NerdFonts` |
| papirus-folders, HyprMod | AUR | GitHub script / pipx (HyprMod is opt-in) |
| gpu-screen-recorder | Official repos | Flathub, wrapped by `hypr/scripts/gsr-toggle.sh` |
| Power profiles | power-profiles-daemon | Fedora's tuned-ppd is left alone (see [Known issues](#known-issues)) |
| Login shell | `chsh` | `usermod` (`chsh` isn't installed by default on Fedora) |
| Package cleanup (Settings → Storage) | yay + pacman caches | dnf cache (`pkexec dnf clean all`) |
| System updates (Settings → Updates) | pacman + AUR | dnf (`repoquery --upgrades`, `dnf upgrade --refresh`) |

### Session fixes for Fedora

- **Portals (file pickers, screen sharing).** Under a Hyprland session started straight from GDM, `graphical-session.target` is never active, so `xdg-desktop-portal` fails with result `dependency`. Apps then fall back to their built-in file pickers (in Brave, Enter didn't save) and screen sharing breaks. `fedora/systemd/hyprland-session.target` binds that target, and `hyprland.lua` imports the session environment and starts it at login.
- **SSH agent.** GNOME sets `SSH_AUTH_SOCK` to its agent; a Hyprland session from GDM got none, so `ssh` and `git push` asked for the key passphrase every time. `hyprland.lua` now points at the same agent GNOME uses (`gcr-ssh-agent`), or plain `ssh-agent` if gcr isn't installed, and `scripts/ssh-agent.sh` starts it.
- **Polkit agent.** Upstream launched `/usr/lib/polkit-kde-authentication-agent-1`, which isn't in its own package list. The fork uses `hyprpolkitagent` at the Fedora path, with the Arch path as fallback.
- **File types.** Outside GNOME/KDE, `xdg-open` falls back to content sniffing, so text-based files like Proxmox SPICE `.vv` looked like `text/plain` and opened in calibre. `perl-File-MimeInfo` lets it match by extension.
- **zsh plugins** are looked up at both the Arch (`/usr/share/zsh/plugins/<name>`) and Fedora (`/usr/share/<name>`) paths.

### Usability fixes and tweaks

- **Wallpaper picker (Super + W)**
  - Opens centered on the current wallpaper. Upstream's position math put the selected tile at the left edge, so it opened off-center and the first tiles could never be centered.
  - Steady movement: a fixed 220 ms per step, one tile per wheel notch, and no hover-to-select (tiles sliding under the cursor kept changing the selection mid-move).
  - Keyboard navigation works. The arrow keys used to move a different internal index than the highlight, so Space could apply the wrong wallpaper.
  - Clear selection: full brightness, a white frame and the file name; the rest are dimmed. The frame color was `transparent`.
  - Less lag: tile shadows render at quarter resolution, thumbnail generation runs one copy at a time, capped at CPU count with one thread per job, with atomic writes, `.webp` support and stale-thumbnail cleanup.
- **Quick actions (Super + S)**: a soft dim behind it, a backdrop disc, filled segments and stronger lines, so it reads over busy windows. Same thin-line look, theme colors only.
- **Opacity (Super + O)** saves to `~/.local/state/43pr/opacity` instead of rewriting `hypr/rules.lua`, so changing it doesn't leave the repo modified. The default stays 70%.
- **Thunar drag-select box** is a faint tint with an outline. Upstream's GTK CSS gave every `.view` an opaque background, and the selection box inherited it, hiding the files underneath.
- **Image previews** (Loupe, Eye of GNOME, Ristretto, gThumb, imv, feh, qimgv) open as a centered, opaque pop-up instead of a tile.
- **SSH from kitty**: `ssh` sends `TERM=xterm-256color`, because most remote hosts lack kitty's terminfo (`clear` failed with "unknown terminal type", Ctrl+L didn't clear). `kssh` runs `kitten ssh` for full kitty features, but it copies files onto the remote host, so use it only on your own machines.
- **Prompt**: git status shown in `[ ]` again. Fixed starship's `stashed = "$"`, which warned on every prompt.
- **Editors**: `hypr/.luarc.json` declares `hl` and the shared config globals, so Lua language servers stop flagging every line.

## Living alongside GNOME

GNOME and Hyprland share the same user settings: the GTK `settings.ini` files, `~/.config/mimeapps.list` and the `org.gnome.desktop.interface` keys. So:

- **Cursor size.** Hyprland keeps `XCURSOR_SIZE=14`, which it snaps to the theme's nearest real size (24). GNOME draws vector cursors at the exact size, so the shared GTK value of 14 made GNOME's cursor tiny. The GTK files now say 24, which looks the same in Hyprland. Existing installs set to exactly 14 are migrated; other values are left alone.
- **Default apps.** Set only where nothing is chosen yet: `.vv` → remote-viewer, `text/plain` → xed (if unset or calibre), browser → Brave (if unset or Firefox). They apply in GNOME too.
- **Light/dark toggle (Super + Shift + T)** also switches GNOME's color scheme.
- **nwg-look** writes to GNOME's settings. Changing the cursor size there changes GNOME too.

## Known issues

- **Settings → Power** needs `powerprofilesctl`. Fedora Workstation uses tuned-ppd, which conflicts with power-profiles-daemon, and the installer won't swap them for you. To use the page: `sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon`.
- **Settings → System RAM details** runs `sudo -n /usr/bin/dmidecode`, which needs a NOPASSWD sudoers rule (same as upstream). Only add one if you accept that trade-off.
- **COPR in-between states.** `dnf upgrade` may skip `hyprtoolkit` / `hyprland-guiutils` ("conflicts" / "broken dependencies") right after the COPR maintainer bumps a library and before everything is rebuilt. dnf keeps the installed pair consistent; upgrade again in a few days. Don't use `--allowerasing`: `hyprland` requires `hyprland-guiutils`.
- **First screen recording** with the Flatpak recorder asks for your password once (its capture helper needs root).
- After `papirus-icon-theme` updates, re-run `papirus-folders -C white`.
- **HyprMod** writes to `hypr/hyprland-gui.lua`, a tracked file, so its changes show up in `git status`.

## Troubleshooting

| Symptom | Check |
|---|---|
| File picker / screen share broken | `systemctl --user is-active graphical-session.target xdg-desktop-portal` (both should be `active`) |
| A file opens in the wrong app | `xdg-mime query filetype <file>` vs `gio info -a standard::content-type <file>`, then `xdg-mime default <app>.desktop <mime/type>` |
| Tiny cursor in GNOME | `gsettings reset org.gnome.desktop.interface cursor-size` |
| Wallpaper picker tiles stuck on "Caching" | Settings → Storage → Wallpaper picker → Clear, then reopen with Super + W |
| Touchpad setting ignored | Settings → Input overrides `hyprland.lua` (it's saved in `~/.config/quickshell/state/devices.lua`) |
| `ssh`/`git` asks for the key passphrase every time | `echo $SSH_AUTH_SOCK; ssh-add -l` (empty, or "Could not open a connection" = no agent; log out and back in after updating) |
| `git push` asks for a username | The clone uses HTTPS: `git remote set-url origin git@github.com:<you>/dotfiles.git` |
| Which window has focus | `sleep 5; hyprctl activewindow \| grep -E 'class\|title'` |

## Security notes

- **Third-party sources run as root when installed.** The COPRs, Flathub and the GitHub downloads (fonts, papirus-folders, zsh-autocomplete) deserve the same trust you'd give the AUR, which is why the installer lists them and asks first.
- **Your config is live code.** `~/.config` points into this repo, and Hyprland runs `exec` lines and keybind scripts at login. A `git pull` is effectively a code deploy into your session, so skim the diff before you pull.
- **Shell plugins run in every terminal.** zsh-autocomplete is pinned to a release tag rather than its development branch, but it fetches a helper (`zasync`) on first start.
- **Proxmox `.vv` files** carry a short-lived SPICE ticket and your PVE host details. Don't let them pile up in Downloads.

## Credits and license

- Desktop, configs and Quickshell components: [43PR](https://github.com/43PR/dotfiles), MIT-licensed. The [LICENSE](../LICENSE) and his copyright notice are kept as-is.
- Wallpaper picker: based on [hyprquickpaper](https://github.com/iamsurjog/hyprquickpaper) by iamsurjog, as tweaked by 43PR.
- Fedora Hyprland packaging: [nikromen/hyprland-rpm](https://github.com/nikromen/hyprland-rpm). Quickshell COPR: errornointernet.
- Fedora port: [NullVoidLabs](https://nullvoidlabs.io).
