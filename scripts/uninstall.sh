#!/usr/bin/env bash
# uninstall.sh - Remove everything install.sh configured.
#
# Restores the backed-up config files and removes the helper scripts, the
# Sunshine hooks, and the Omarchy post-boot hook. Safe to re-run.
#
# Usage:
#   ./uninstall.sh          # interactive confirm
#   ./uninstall.sh --yes    # skip confirmation

set -euo pipefail

YES=0
[ "${1:-}" = "--yes" ] && YES=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REMOTE="HEADLESS-1"
LOG="$HOME/.local/share/sunshine-headless.log"

if [ "$YES" = 0 ]; then
  read -r -p "Remove Sunshine headless virtual display setup? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

rm -f "$HOME/.local/bin/sunshine-headless-connect.sh" \
      "$HOME/.local/bin/sunshine-headless-disconnect.sh"
rm -f "$HOME/.local/share/sunshine-headless.log"

# Remove the monitors.lua block we added (guarded marker comment).
MON="$HOME/.config/hypr/monitors.lua"
if [ -f "$MON" ]; then
  python3 - "$MON" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
marker = "-- [[ Sunshine headless virtual display (added by install.sh) ]]"
i = s.find(marker)
if i != -1:
    s = s[:i].rstrip() + "\n"
    open(p, "w").write(s)
    print("monitors.lua: removed setup block")
else:
    print("monitors.lua: no setup block found, leaving as-is")
PY
fi

# Sunshine config: blank output_name / remove the hook line we added.
SUN="$HOME/.config/sunshine/sunshine.conf"
if [ -f "$SUN" ] && grep -q "$REMOTE" "$SUN" 2>/dev/null; then
  sed -i "s/^output_name *=[[:space:]]*$REMOTE.*/output_name =/" "$SUN"
  sed -i "/global_prep_cmd.*sunshine-headless/d" "$SUN"
  echo "sunshine.conf: reset output_name and removed hooks"
fi

# Remove the Omarchy post-boot hook.
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/sunshine-headless.hook" 2>/dev/null || true

# Remove the saved resolution choice.
rm -f "$HOME/.config/sunshine-headless/mode"
rmdir "$HOME/.config/sunshine-headless" 2>/dev/null || true

echo "Uninstalled. Backups (*.bak.<ts>) were not touched."
