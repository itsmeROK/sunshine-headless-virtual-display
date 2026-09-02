#!/usr/bin/env bash
# Runs when a Moonlight client disconnects (Sunshine global_prep_cmd "undo").
# Restores the user's workspaces back to the physical monitor and turns it on.

LOG="$HOME/.local/share/sunshine-headless.log"
PHYSICAL="DP-1"
REMOTE="HEADLESS-1"
REMOTE_WS=11

# Detect Hyprland config provider (Lua 0.55+, or legacy dispatchers).
LUA=0
[ "$(hyprctl dispatch 'hl.dsp.no_op()' 2>&1)" = "ok" ] && LUA=1

# Turn the physical monitor back on first so workspaces are never invisible.
if [ "$LUA" = 1 ]; then
    hyprctl dispatch "hl.dsp.dpms({ action=\"on\", monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
else
    hyprctl dispatch dpms on "$PHYSICAL" >/dev/null 2>&1
fi

# Move every workspace back to the physical monitor, except the reserved
# remote workspace which always stays on the headless.
WS_IDS=$(hyprctl workspaces -j | python3 -c \
    "import sys,json; ex=$REMOTE_WS; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$REMOTE' and w['id']>0 and w['id']!=ex]")

for id in $WS_IDS; do
    if [ "$LUA" = 1 ]; then
        hyprctl dispatch "hl.dsp.workspace.move({ workspace=\"$id\", monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
    else
        hyprctl dispatch moveworkspacetomonitor "$id" "$PHYSICAL" >/dev/null 2>&1
    fi
done

if [ "$LUA" = 1 ]; then
    hyprctl dispatch "hl.dsp.focus({ monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
else
    hyprctl dispatch focusmonitor "$PHYSICAL" >/dev/null 2>&1
fi

pkill -CONT -x hypridle 2>/dev/null

echo "$(date -Iseconds) Client disconnected, workspaces restored to $PHYSICAL" >> "$LOG"
exit 0
