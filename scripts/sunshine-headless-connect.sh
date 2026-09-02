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

# Abort if the headless display is missing.
if ! hyprctl monitors -j | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin)]; raise SystemExit(0 if '$REMOTE' in ms else 1)" 2>/dev/null; then
    echo "$(date -Iseconds) ERROR: $REMOTE missing, cannot start stream" >> "$LOG"
    exit 0
fi

# Move every user workspace currently on the physical monitor onto the headless.
# The reserved remote workspace already lives on HEADLESS.
WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; ex=$REMOTE_WS; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$PHYSICAL' and w['id']>0 and w['id']!=ex]")

for id in $WS_IDS; do
    if [ "$LUA" = 1 ]; then
        hyprctl dispatch "hl.dsp.workspace.move({ workspace=\"$id\", monitor=\"$REMOTE\" })" >/dev/null 2>&1
    else
        hyprctl dispatch moveworkspacetomonitor "$id" "$REMOTE" >/dev/null 2>&1
    fi
done

if [ "$LUA" = 1 ]; then
    hyprctl dispatch "hl.dsp.focus({ monitor=\"$REMOTE\" })" >/dev/null 2>&1
else
    hyprctl dispatch focusmonitor "$REMOTE" >/dev/null 2>&1
fi

# Turn off the physical monitor.
if [ "$LUA" = 1 ]; then
    hyprctl dispatch "hl.dsp.dpms({ action=\"off\", monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
else
    hyprctl dispatch dpms off "$PHYSICAL" >/dev/null 2>&1
fi

echo "$(date -Iseconds) Client connected, workspaces migrated to $REMOTE" >> "$LOG"
exit 0
