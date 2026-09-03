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

# On pre-Lua Hyprland, load the legacy fallback functions.
if [ "$LUA" != 1 ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/sunshine-headless-legacy.sh"
fi

# Restore the headless display to its pre-stream resolution, if the connect
# hook resized it to match the client.
STATE="$HOME/.local/share/sunshine-headless-mode"
if [ -f "$STATE" ]; then
    ORIG="$(cat "$STATE" 2>/dev/null || true)"
    rm -f "$STATE"
    if [ -n "$ORIG" ]; then
        if [ "$LUA" = 1 ]; then
            hyprctl eval "hl.monitor({ output = \"$REMOTE\", mode = \"$ORIG\", position = \"0x0\", scale = 1 })" >/dev/null 2>&1
        else
            legacy_set_mode "$REMOTE" "$ORIG"
        fi
        echo "$(date -Iseconds) Restored $REMOTE to $ORIG" >> "$LOG"
    fi
fi

# Turn the physical monitor back on first so workspaces are never invisible.
if [ "$LUA" = 1 ]; then
    hyprctl dispatch "hl.dsp.dpms({ action=\"on\", monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
else
    legacy_dpms on "$PHYSICAL"
fi

# Move every workspace back to the physical monitor, except the reserved
# remote workspace which always stays on the headless.
if [ "$LUA" = 1 ]; then
    WS_IDS=$(hyprctl workspaces -j | python3 -c \
        "import sys,json; ex=$REMOTE_WS; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$REMOTE' and w['id']>0 and w['id']!=ex]")
    for id in $WS_IDS; do
        hyprctl dispatch "hl.dsp.workspace.move({ workspace=\"$id\", monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
    done
    hyprctl dispatch "hl.dsp.focus({ monitor=\"$PHYSICAL\" })" >/dev/null 2>&1
else
    legacy_move_workspaces "$REMOTE" "$PHYSICAL" "$REMOTE_WS"
    legacy_focus "$PHYSICAL"
fi

pkill -CONT -x hypridle 2>/dev/null

echo "$(date -Iseconds) Client disconnected, workspaces restored to $PHYSICAL" >> "$LOG"
exit 0
