#!/usr/bin/env bash
# Sunshine headless virtual display - ensure-stream-serve hook.
#
# Runs at every boot (post-boot event) to guarantee the persistent HEADLESS-1
# virtual monitor exists and Sunshine is serving it, even if Sunshine was not
# started or died. The headless is normally created by monitors.lua during
# Hyprland init; this is a belt-and-braces check.
#
# Install:  omarchy hook install post-boot <this-file>
#   (already installed in ~/.config/omarchy/hooks/post-boot.d/)

set -e

LOG="$HOME/.local/share/sunshine-headless.log"
REMOTE="HEADLESS-1"

# Give Hyprland a moment to finish bringing up monitors at login.
sleep 3

# Ensure the headless virtual monitor exists.
if ! hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin)]; raise SystemExit(0 if '$REMOTE' in ms else 1)"; then
  hyprctl output create headless >/dev/null 2>&1 || true
  sleep 1
fi

# Ensure Sunshine is running.
if ! pgrep -x sunshine >/dev/null 2>&1; then
  nohup sunshine >/dev/null 2>&1 &
  echo "$(date -Iseconds) post-boot: started Sunshine for $REMOTE" >> "$LOG"
fi

exit 0
