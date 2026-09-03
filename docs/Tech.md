# Technical Reference

This document describes how Sunshine Headless Virtual Display works
internally. See `README.md` for installation instructions.

## Architecture

The setup runs a **persistent headless virtual monitor** (`HEADLESS-1`) for the
whole Hyprland session. Sunshine captures that monitor (`output_name`), and
when a Moonlight client connects, the hooks move the desktop onto it.

```
hyprland (Lua config)
  ├── monitors.lua       → HEADLESS-1 (720p default, 0x0) + reserved ws 11
  └── autostart          → (no automatic Sunshine launch; post-boot handles it)

sunshine.conf
  ├── output_name = HEADLESS-1
  └── global_prep_cmd = [{"do":"connect.sh","undo":"disconnect.sh"}]

connect.sh (global_prep_cmd "do")       →  resize + workspace migration + DPMS off
disconnect.sh (global_prep_cmd "undo")  →  restore + migration back + DPMS on
```

## Monitor placement (position 0x0)

`HEADLESS-1` **must be at position `0x0`**. If it is placed at a non-zero
offset, a dead zone forms on its left, and the receiver's cursor can never
enter the left half of the stream. Because the headless sits at the origin, the
stream's own (0,0) maps directly to the host's pointer origin; the physical
display auto-places to its right.

## Resolution logic

- The headless starts at a cheap **idle default** (`monitors.lua` →
  `CLIENT_MODE`, default `1280x720@60`). This saves VRAM while nothing is
  streaming.
- When a client connects, Sunshine sets `SUNSHINE_CLIENT_WIDTH`,
  `SUNSHINE_CLIENT_HEIGHT` and `SUNSHINE_CLIENT_FPS` environment variables
  before running the `global_prep_cmd` "do" command. These are only available
  inside the hook (not in e.g. `output_name` values or `monitors.lua`).
- `connect.sh` reads these and resizes the headless to match the client.
- `disconnect.sh` restores the resolution to the idle default (saved in the
  state file `~/.local/share/sunshine-headless-mode`).

### Changing resolution across Hyprland versions

**Important:** the `hyprctl output <name> mode <res>` command has been dropped
from newer Hyprland versions (it returns `ok` but does nothing).

- **Modern (Lua config, 0.55+):** uses
  `hyprctl eval "hl.monitor({ output = \"HEADLESS-1\", mode = \"WxH@rate\", position = \"0x0\", scale = 1 })"`.
- **Legacy (pre-Lua):** uses `hyprctl output <name> mode <res>` (worked on old
  versions).

The hooks **verify** afterwards (by re-reading `hyprctl monitors -j`) that the
resolution actually changed — they do not rely on the command's exit code alone.

## Legacy support (pre-Lua Hyprland)

All pre-Lua fallbacks live in their own file
`scripts/sunshine-headless-legacy.sh`, which is a **function library**
(containing `legacy_move_workspaces`, `legacy_focus`, `legacy_dpms`,
`legacy_set_mode`).

- The hooks **source** that file only when the config provider is *not* Lua
  (test: `hyprctl dispatch 'hl.dsp.no_op()'`).
- Lua systems never load the legacy file.
- `install.sh` installs the legacy file to `~/.local/bin/` and `uninstall.sh`
  removes it.

Dispatcher syntax used (Lua vs legacy):

| Action | Lua (0.55+) | Legacy |
|--------|-------------|--------|
| Move workspace | `hl.dsp.workspace.move({workspace=.., monitor=..})` | `moveworkspacetomonitor` |
| Focus monitor | `hl.dsp.focus({monitor=..})` | `focusmonitor` |
| DPMS | `hl.dsp.dpms({action=.., monitor=..})` | `dpms` |
| Set mode | `hyprctl eval "hl.monitor(..)"` | `hyprctl output .. mode ..` |

## Workspace management

- The reserved workspace `11` is marked `persistent = true` and always stays on
  `HEADLESS-1`.
- Workspaces 1–10 stay movable. The connect hook moves them from the physical
  display to the headless; the disconnect hook moves them back.
- The physical display is turned off (DPMS off) during the stream and back on
  on disconnect.

## Installed file map ("How it's wired")

| Piece | File |
|-------|------|
| Headless monitor + workspace pin | `~/.config/hypr/monitors.lua` |
| Capture target + hooks | `~/.config/sunshine/sunshine.conf` |
| Connect hook | `~/.local/bin/sunshine-headless-connect.sh` |
| Disconnect hook | `~/.local/bin/sunshine-headless-disconnect.sh` |
| Legacy fallbacks (pre-Lua) | `~/.local/bin/sunshine-headless-legacy.sh` |
| Ensure-at-boot hook (Omarchy) | `~/.config/omarchy/hooks/post-boot.d/sunshine-headless.hook` |

## Files & layout

```
sunshine-headless-virtual-display/
├── README.md                      # intro + installation
├── docs/
│   └── Tech.md                    # this file (technical reference)
├── scripts/                       # executable scripts
│   ├── install.sh                   #   idempotent installer (run on fresh machines)
│   ├── uninstall.sh                 #   removes everything install.sh created
│   ├── sunshine-headless-connect.sh     #   "do" hook (run by Sunshine on connect)
│   ├── sunshine-headless-disconnect.sh  #   "undo" hook (run on disconnect)
│   └── sunshine-headless-legacy.sh      #   fallbacks for pre-Lua Hyprland
├── hooks/
│   └── post-boot-ensure-sunshine.sh     # Omarchy post-boot hook
├── hypr/
│   └── monitors.lua.snippet             # headless monitor block
└── sunshine/
    └── sunshine.conf                    # output_name + hooks template
```

## Notes & limitations

- **The physical display turns off during the stream.** If you want it to stay
  on (e.g. streaming to a second device while someone uses the PC), drop the
  DPMS-off lines from the connect hook.
- The stream resolution is matched per client automatically by the connect hook
  (`SUNSHINE_CLIENT_WIDTH`/`HEIGHT`). The headless starts at the idle default
  (`CLIENT_MODE` in `monitors.lua`); change it and re-run `install.sh` or edit
  the file.
- `X11` is not supported by the headless backend — Hyprland/Wayland only.
