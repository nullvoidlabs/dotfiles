#!/usr/bin/env bash
# Toggle gpu-screen-recorder (Super + R).
# Uses the native binary if present (Arch), else the Flathub build (Fedora).
# Keeps upstream's pidfile so RecorderOSD.qml still shows recording state.

PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/gsr.pid"
FLATPAK_ID="com.dec05eba.gpu_screen_recorder"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    pid="$(cat "$PIDFILE")"
    # Native: the pidfile PID *is* the recorder. Flatpak: it's the sandbox
    # wrapper, which may not forward SIGINT, so signal the recorder inside.
    # SIGINT (not TERM) is what makes it finalize the .mp4.
    if [[ "$(ps -o comm= -p "$pid" 2>/dev/null)" == gpu-screen-reco* ]]; then
        kill -INT "$pid"
    else
        # anchored to argv[0], so editors/shells merely mentioning the name are never hit
        pkill -INT -f '^([^ ]*/)?gpu-screen-recorder( |$)' || kill -INT "$pid"
    fi
    rm -f "$PIDFILE"
    exit 0
fi

if command -v gpu-screen-recorder >/dev/null 2>&1; then
    gsr=(gpu-screen-recorder)
elif flatpak info "$FLATPAK_ID" >/dev/null 2>&1; then
    gsr=(flatpak run --command=gpu-screen-recorder "$FLATPAK_ID")
else
    notify-send "Screen recorder" "gpu-screen-recorder is not installed" 2>/dev/null
    exit 1
fi

dir="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"
mkdir -p "$dir"
mon="$(hyprctl monitors | awk '/^Monitor/{n=$2} /focused: yes/{print n}')"

"${gsr[@]}" -w "${mon:-screen}" -f 60 -a default_output \
    -o "$dir/$(date +%Y-%m-%d_%H-%M-%S).mp4" &
echo $! > "$PIDFILE"
