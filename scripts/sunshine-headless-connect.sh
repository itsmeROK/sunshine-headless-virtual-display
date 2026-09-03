#!/usr/bin/env bash
# Runs when a Moonlight client connects (Sunshine global_prep_cmd "do").
# Moves the user's workspaces from the physical monitor onto the persistent
# HEADLESS stream display, then turns the physical monitor off.

LOG="$HOME/.local/share/sunshine-headless.log"
PHYSICAL="DP-1"
REMOTE="HEADLESS-1"
REMOTE_WS=11

loginctl unlock-session 2>/dev/null
pkill -STOP -x hypridle 2>/dev/null

# Detect Hyprland config provider (Lua 0.55+, or legacy dispatchers).
LUA=0
[ "$(hyprctl dispatch 'hl.dsp.no_op()' 2>&1)" = "ok" ] && LUA=1

# On pre-Lua Hyprland, load the legacy fallback functions.
if [ "$LUA" != 1 ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/sunshine-headless-legacy.sh"
fi

# Abort if the headless display is missing.
if ! hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin)]; raise SystemExit(0 if '$REMOTE' in ms else 1)" 2>/dev/null; then
    echo "$(date -Iseconds) ERROR: $REMOTE missing, cannot start stream" >> "$LOG"
    exit 0
fi

# Match the stream display to the client's native resolution.
# Sunshine exports SUNSHINE_CLIENT_WIDTH/HEIGHT while running this "do"
# command. Resize the headless to match; if the client's mode isn't
# supported, Hyprland keeps the monitors.lua default.
STATE="$HOME/.local/share/sunshine-headless-mode"
if [ -n "${SUNSHINE_CLIENT_WIDTH:-}" ] && [ -n "${SUNSHINE_CLIENT_HEIGHT:-}" ]; then
    RATE="${SUNSHINE_CLIENT_FPS:-60}"
    MODE="${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${RATE}"
    get_res() {
        hyprctl monitors -j 2>/dev/null | python3 -c \
            "import sys,json; ms=[m for m in json.load(sys.stdin) if m['name']=='$REMOTE']; print(f\"{ms[0]['width']}x{ms[0]['height']}\" if ms else '')"
    }
    ORIG="$(get_res)"
    # Apply the mode. Newer Hyprland (0.5x+) dropped 'hyprctl output <name>
    # mode' and use the Lua config; legacy platforms fall back to it.
    if [ "$LUA" = 1 ]; then
        hyprctl eval "hl.monitor({ output = \"$REMOTE\", mode = \"$MODE\", position = \"0x0\", scale = 1 })" >/dev/null 2>&1
    else
        legacy_set_mode "$REMOTE" "$MODE"
    fi
    sleep 1
    # Verify the resolution actually changed before trusting the resize.
    NEW="$(get_res)"
    if [ "$NEW" = "${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}" ]; then
        printf '%s\n' "$ORIG" > "$STATE"
        echo "$(date -Iseconds) Resized $REMOTE to $MODE (was $ORIG)" >> "$LOG"
    else
        echo "$(date -Iseconds) Client mode $MODE not applied (still $NEW), keeping default" >> "$LOG"
    fi
fi

# Move every user workspace currently on the physical monitor onto the headless.
# The reserved remote workspace already lives on HEADLESS.
if [ "$LUA" = 1 ]; then
    WS_IDS=$(hyprctl workspaces -j | python3 -c \
        "import sys,json; ex=$REMOTE_WS; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$PHYSICAL' and w['id']>0 and w['id']!=ex]")
    for id in $WS_IDS; do
        hyprctl dispatch "hl.dsp.workspace.move({ workspace=\"$id\", monitor=\"$REMOTE\" })" >/dev/null 2>&1
    done
    hyprctl dispatch "hl.dsp.focus({ monitor=\"$REMOTE\" })" >/dev/null 2>&1
    hyprctl dispatch "hl.dsp.dpms({ action=\"off\", monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
else
    legacy_move_workspaces "$PHYSICAL" "$REMOTE" "$REMOTE_WS"
    legacy_focus "$REMOTE"
    legacy_dpms off "$PHYSICAL"
fi

echo "$(date -Iseconds) Client connected, workspaces migrated to $REMOTE" >> "$LOG"
exit 0
