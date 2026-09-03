#!/usr/bin/env bash
# sunshine-headless-legacy.sh - legacy (pre-Lua) Hyprland fallbacks.
#
# Older Hyprland releases (< 0.55) do not expose the `hl.*` Lua API, so the
# dispatcher keywords (`moveworkspacetomonitor`, `dpms`, `focusmonitor`) and
# `hyprctl output <name> mode` must be used instead of their Lua equivalents.
#
# Modern Hyprland (0.55+) reads a Lua config and never sources this file.
#
# This is a function library: the sunshine-headless-{connect,disconnect}.sh
# hooks `source` it only when the config provider is *not* Lua, then call the
# functions defined here. It is safe to run directly for manual testing.

# Move every user workspace currently on $from onto $to, skipping the reserved
# remote workspace ($REMOTE_WS).
legacy_move_workspaces() {
    local from="$1" to="$2" ex="$3"
    local ids
    ids=$(hyprctl workspaces -j 2>/dev/null | python3 -c \
        "import sys,json; [print(w['id']) for w in json.load(sys.stdin) if w['monitor']=='$from' and w['id']>0 and w['id']!=$ex]")
    for id in $ids; do
        hyprctl dispatch moveworkspacetomonitor "$id" "$to" >/dev/null 2>&1
    done
}

# Focus the given monitor with the legacy dispatcher.
legacy_focus() {
    hyprctl dispatch focusmonitor "$1" >/dev/null 2>&1
}

# Set power state (on|off) of a monitor with the legacy dispatcher.
legacy_dpms() {
    hyprctl dispatch dpms "$1" "$2" >/dev/null 2>&1
}

# Change a monitor's resolution with the legacy `hyprctl output` command.
legacy_set_mode() {
    hyprctl output "$1" mode "$2" >/dev/null 2>&1
}
