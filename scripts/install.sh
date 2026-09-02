#!/usr/bin/env bash
# install.sh - Sunshine Headless Virtual Display for Hyprland/Omarchy
#
# Sets up a persistent headless virtual monitor so Sunshine streams the remote
# client's desktop at its native resolution (1:1, no scaling softness). Includes
# connect/disconnect hooks that migrate workspaces to the headless and back, and
# turns the physical monitor off during the stream.
#
# Idempotent: safe to re-run. Always backs up the files it modifies.
#
# Usage:
#   ./scripts/install.sh                     # asks for client res, then installs
#   CLIENT_MODE=2560x1440@60 ./install.sh    # fix the client resolution up front
#   PHYSICAL_DP=HDMI-A-1 ./install.sh        # different physical output name
#   REMOTE_WS=12 ./install.sh                # different reserved workspace
#   ./install.sh --check                     # dry-run: inspect, change nothing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

CLIENT_MODE="${CLIENT_MODE:-}"
PHYSICAL="${PHYSICAL_DP:-}"
REMOTE_WS="${REMOTE_WS:-11}"
REMOTE="HEADLESS-1"

log() { printf '\033[1;32m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*"; }

# Resolve the client's native resolution. Precedence:
#   1. CLIENT_MODE env/arg (e.g. CLIENT_MODE=2560x1440@60 ./install.sh)
#   2. saved choice from a previous run (~/.config/sunshine-headless/mode)
#   3. interactive menu (only when stdin is a terminal)
default_mode=${CLIENT_MODE:-}
if [ -z "$default_mode" ] && [ -f "$HOME/.config/sunshine-headless/mode" ]; then
  default_mode="$(cat "$HOME/.config/sunshine-headless/mode" 2>/dev/null || true)"
fi
if [ -z "$CLIENT_MODE" ] && { [ ! -t 0 ] || [ -n "$default_mode" ]; }; then
  # Non-interactive (e.g. hook/CI) or saved choice present: don't prompt.
  CLIENT_MODE="${default_mode:-2560x1664@60.00}"
fi
if [ -z "$CLIENT_MODE" ]; then
  echo "Remote client's native resolution? (streamed 1:1)"
  echo " MacBook Air / Pro (retina, HiDPI):"
  echo "  1) 2560x1664 @ 60  13\" MacBook Air M4          [default]"
  echo "  2) 2880x1864 @ 60  15\" MacBook Air M4"
  echo "  3) 3024x1964 @ 60  14\" MacBook Pro M4/Pro/Max"
  echo "  4) 3456x2234 @ 60  16\" MacBook Pro M4 Pro/Max"
  echo " Standard 16:9:"
  echo "  5) 2560x1440 @ 60  QHD"
  echo "  6) 1920x1080 @ 60  FHD"
  echo "  7) 3840x2160 @ 60  4K"
  echo "  8) 5120x2880 @ 60  5K"
  read -r -p "Choose [1-8] or type res like 3440x1440@60.00: " choice
  case "$choice" in
    1|"")   CLIENT_MODE="2560x1664@60.00" ;;
    2)      CLIENT_MODE="2880x1864@60.00" ;;
    3)      CLIENT_MODE="3024x1964@60.00" ;;
    4)      CLIENT_MODE="3456x2234@60.00" ;;
    5)      CLIENT_MODE="2560x1440@60.00" ;;
    6)      CLIENT_MODE="1920x1080@60.00" ;;
    7)      CLIENT_MODE="3840x2160@60.00" ;;
    8)      CLIENT_MODE="5120x2880@60.00" ;;
    *)      CLIENT_MODE="$choice" ;;
  esac
fi
mkdir -p "$HOME/.config/sunshine-headless"
printf '%s\n' "$CLIENT_MODE" > "$HOME/.config/sunshine-headless/mode"

# --check: inspect the machine and print what would change, make no changes.
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

### Preflight: required tools --------------------------------------------------
missing=()
for tool in hyprctl python3; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if ! command -v sunshine >/dev/null 2>&1; then
  missing+=("sunshine")
fi
if [ ${#missing[@]} -gt 0 ]; then
  warn "Missing: ${missing[*]}"
  warn "Install them first, e.g.:  pacman -S sunshine python"
  if [ "$CHECK" = 0 ]; then
    exit 1
  fi
fi
if [ ! -d "$HOME/.config/hypr" ]; then
  warn "No ~/.config/hypr — is this a Hyprland/Omarchy machine?"
  if [ "$CHECK" = 0 ]; then
    exit 1
  fi
fi

if [ "$CHECK" = 1 ]; then
  log "Preflight OK. Would: install scripts to ~/.local/bin, edit monitors.lua/sunshine.conf, install post-boot hook, open UFW ports, restart Sunshine."
  exit 0
fi

### 0. Locate the physical output name ----------------------------------------
if [ -z "$PHYSICAL" ]; then
  PHYSICAL=$(hyprctl monitors -j 2>/dev/null | python3 -c \
    "import sys,json; ms=[m['name'] for m in json.load(sys.stdin) if 'HEADLESS' not in m['name']]; print(ms[0] if ms else '')" || true) || true
  PHYSICAL="${PHYSICAL:-DP-1}"
fi

### 1. Detect Hyprland config provider ----------------------------------------
LUA=0
[ "$(hyprctl dispatch 'hl.dsp.no_op()' 2>&1)" = "ok" ] && LUA=1
log "Hyprland provider: $([ $LUA = 1 ] && echo Lua || echo legacy)"
log "Physical output: $PHYSICAL | Client mode: $CLIENT_MODE | Remote WS: $REMOTE_WS"

### 2. Install helper scripts -------------------------------------------------
mkdir -p "$HOME/.local/bin"
# Substitute placeholders for physical monitor + remote workspace.
for f in sunshine-headless-connect.sh sunshine-headless-disconnect.sh; do
  sed -e "s/^PHYSICAL=\"[^\"]*\"/PHYSICAL=\"$PHYSICAL\"/" \
      -e "s/^REMOTE=\"[^\"]*\"/REMOTE=\"$REMOTE\"/" \
      -e "s/^REMOTE_WS=.*/REMOTE_WS=$REMOTE_WS/" \
      "$SCRIPT_DIR/$f" > "$HOME/.local/bin/$f"
done
chmod +x "$HOME/.local/bin/sunshine-headless-connect.sh" "$HOME/.local/bin/sunshine-headless-disconnect.sh"
log "Installed helper scripts to ~/.local/bin/"

### 3. Merge monitors.lua -----------------------------------------------------
MON="$HOME/.config/hypr/monitors.lua"
mkdir -p "$(dirname "$MON")"
if [ -f "$MON" ] && grep -q "$REMOTE" "$MON"; then
  log "monitors.lua already references $REMOTE; skipping (edit manually if resolution changed)"
else
  cp "$MON" "$MON.bak.$(date +%s)" 2>/dev/null || true
  cat >> "$MON" <<EOF

-- [[ Sunshine headless virtual display (added by install.sh) ]]
local physical = "$PHYSICAL"
local remote_ws = $REMOTE_WS
hl.monitor({ output = "$REMOTE", mode = "$CLIENT_MODE", position = "0x0", scale = 1 })
hl.workspace_rule({ workspace = remote_ws, monitor = "$REMOTE", default = true, persistent = true })
EOF
  log "monitors.lua updated"
fi

### 4. Merge sunshine.conf ----------------------------------------------------
SUN="$HOME/.config/sunshine/sunshine.conf"
mkdir -p "$(dirname "$SUN")"
cp "$SUN" "$SUN.bak.$(date +%s)" 2>/dev/null || true
if grep -q "output_name" "$SUN" 2>/dev/null; then
  sed -i "s/^output_name *=.*/output_name = $REMOTE/" "$SUN"
else
  printf '\noutput_name = %s\n' "$REMOTE" >> "$SUN"
fi
if ! grep -q "global_prep_cmd" "$SUN" 2>/dev/null; then
  printf 'global_prep_cmd = [{"do":"%s/sunshine-headless-connect.sh","undo":"%s/sunshine-headless-disconnect.sh","elevated":"false"}]\n' \
    "$HOME/.local/bin" "$HOME/.local/bin" >> "$SUN"
fi
log "sunshine.conf updated (output_name=$REMOTE, hooks wired)"

### 5. Install the post-boot hook --------------------------------------------
HOOKS_DIR="$HOME/.config/omarchy/hooks/post-boot.d"
if [ -d "$HOME/.config/omarchy" ] || [ -d "$HOME/.config/omarchy/hooks" ]; then
  mkdir -p "$HOOKS_DIR"
  install -m 0755 "$ROOT/hooks/post-boot-ensure-sunshine.sh" "$HOOKS_DIR/sunshine-headless.hook"
  log "Installed Omarchy post-boot hook (ensures headless + Sunshine at login)"
fi

### 6. Open firewall ports ----------------------------------------------------
if command -v ufw >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo ufw allow 47984:48010/tcp >/dev/null 2>&1 || true
  sudo ufw allow 47984:48010/udp >/dev/null 2>&1 || true
  log "UFW: opened Sunshine ports 47984-48010"
else
  warn "UFW ports not auto-opened (needs sudo). Run manually if firewall is active."
fi

### 7. Reload Hyprland + restart Sunshine -------------------------------------
hyprctl reload >/dev/null 2>&1 || true
if command -v sunshine >/dev/null 2>&1; then
  pkill -x sunshine 2>/dev/null || true
  sleep 2
  nohup sunshine >/dev/null 2>&1 &
  log "Sunshine restarted"
fi

log "Done. Reconnect from Moonlight to verify (stream is $CLIENT_MODE)."
