#!/usr/bin/env bash
# Start the SSH agent hyprland.lua pointed SSH_AUTH_SOCK at.
#   .../gcr/ssh            -> gcr-ssh-agent (GNOME's agent on Fedora; socket-activated)
#   .../ssh-agent.socket   -> plain ssh-agent, reused if one is already listening
sock="${SSH_AUTH_SOCK:-}"
[[ -n "$sock" ]] || exit 0

if [[ "$sock" == */gcr/ssh ]]; then
    systemctl --user start gcr-ssh-agent.socket
else
    ssh-add -l >/dev/null 2>&1
    if [[ $? -eq 2 ]]; then                 # 2 = no agent listening
        rm -f -- "$sock"
        ssh-agent -a "$sock" >/dev/null 2>&1   # daemonizes; close its output so callers don't wait on it
    fi
fi

# So services started by systemd/D-Bus (e.g. editors, git GUIs) see it too
systemctl --user set-environment SSH_AUTH_SOCK="$sock"
dbus-update-activation-environment --systemd SSH_AUTH_SOCK 2>/dev/null
