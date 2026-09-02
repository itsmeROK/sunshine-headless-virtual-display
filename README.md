# Sunshine Headless Virtual Display (Hyprland & Omarchy)

Stream your Linux desktop to Moonlight **at the client's native resolution**
with a **1:1 (pixel-perfect)** image, instead of a scaled/downscaled 4K frame
that looks soft.

It works by creating a **persistent headless virtual monitor** (`HEADLESS-1`)
at the remote client's resolution (e.g. 2560×1664 for a 13" MacBook Air M4) and
pointing Sunshine at it. When a Moonlight client connects, your workspaces
migrate onto the headless and the physical monitor turns off; on disconnect
everything is restored.

```
┌──────────────────┬──────────────────────────┐
│  HEADLESS-1      │   DP-1 (physical 4K)     │
│  (stream display)│                          │
│  ws 11 (reserved)│   workspaces 1-10        │
│  2560x1664 @ 0x0 │   (auto-placed right)    │
│                  │   turns OFF during stream│
└──────────────────┴──────────────────────────┘
  receiver cursor maps to headless origin (0,0)
```

---

## What it does

1. **Creates** `HEADLESS-1` — a persistent headless virtual display at the
   client's native resolution. Lives for the whole Hyprland session.
2. **Pins** a reserved workspace (default `11`) to the headless.
3. **Streams** it with Sunshine (`output_name = HEADLESS-1`).
4. **On client connect** (`global_prep_cmd "do"`):
   moves workspaces 1–10 to the headless, focuses it, turns the physical
   monitor off, pauses `hypridle`, unlocks the session.
5. **On client disconnect** (`global_prep_cmd "undo"`):
   moves the workspaces back, turns the physical monitor on, resumes `hypridle`.

---

## Requirements

- Hyprland (Wayland, wlroots), incl. Omarchy
- Sunshine installed and working
- GPU with hardware encoding (VAAPI on AMD/Intel, NVENC on NVIDIA)
- `python3` (used by the hooks to parse `hyprctl` JSON)

---

## Install on a fresh machine
```bash
git clone <repo-url> sunshine-headless-virtual-display
cd sunshine-headless-virtual-display

# interactive - asks for the client's native resolution, then installs
./scripts/install.sh

# non-interactive (fix the resolution up front)
CLIENT_MODE=2560x1440@60 ./scripts/install.sh

# or other options:
PHYSICAL_DP=HDMI-A-1   REMOTE_WS=12   ./scripts/install.sh

# dry-run: check the machine and report what would change, change nothing
./scripts/install.sh --check
```

`install.sh` asks for the **remote client's native resolution** on first run
(menu: 2560×1664 for 13" MacBook Air M4, 2880×1864 for 15" Air, 3024×1964 for
14" MacBook Pro, 3456×2234 for 16" MacBook Pro, plus 16:9 QHD/FHD/4K/5K, or type
a custom `WxH@rate`). The choice is saved to
`~/.config/sunshine-headless/mode` and reused next time; passing
`CLIENT_MODE=...` overrides it.

`install.sh` is idempotent and backs up every file it touches. It:

1. Detects your physical output name + Hyprland config provider (Lua/legacy)
2. Installs the connect/disconnect hooks to `~/.local/bin/`
3. Merges `monitors.lua` (headless monitor + reserved workspace)
4. Merges `sunshine.conf` (`output_name` + `global_prep_cmd` hooks)
5. Opens Sunshine firewall ports (if UFW and passwordless sudo)
6. Reloads Hyprland and restarts Sunshine
7. Installs an Omarchy `post-boot` hook that ensures the headless display
   exists and Sunshine is running after every login

Then connect from Moonlight. First connection asks for a PIN on the Sunshine
web panel as usual. `install.sh` auto-detects the target machine's physical
output name and Hyprland provider, so no edits are needed on another machine —
just clone the repo and run `./scripts/install.sh`.

---

## Uninstall

```bash
./scripts/uninstall.sh        # interactive confirm
./scripts/uninstall.sh --yes  # no prompt
```

Removes the helper scripts, the `monitors.lua` block we added,
resets `sunshine.conf` (`output_name` + hooks), and deletes the Omarchy
post-boot hook. Backups (`*.bak.<ts>`) are left in place for manual recovery.

---

## How it's wired

| Piece | File |
|-------|------|
| Headless monitor + workspace pin | `~/.config/hypr/monitors.lua` |
| Capture target + hooks | `~/.config/sunshine/sunshine.conf` |
| Connect hook | `~/.local/bin/sunshine-headless-connect.sh` |
| Disconnect hook | `~/.local/bin/sunshine-headless-disconnect.sh` |
| Ensure-at-boot hook (Omarchy) | `~/.config/omarchy/hooks/post-boot.d/sunshine-headless.hook` |

---

## Files & layout

```
sunshine-headless-virtual-display/
├── README.md                      # this file
├── scripts/                       # executable scripts
│   ├── install.sh                   #   idempotent installer (run on fresh machines)
│   ├── uninstall.sh                 #   removes everything install.sh created
│   ├── sunshine-headless-connect.sh     #   "do" hook (run by Sunshine on connect)
│   └── sunshine-headless-disconnect.sh  #   "undo" hook (run on disconnect)
├── hooks/
│   └── post-boot-ensure-sunshine.sh     # Omarchy post-boot hook
├── hypr/
│   └── monitors.lua.snippet             # headless monitor block
└── sunshine/
    └── sunshine.conf                    # output_name + hooks template
```

---

## Notes / limitations

- **Physical monitor turns off during the stream.** If you want it to stay on
  (e.g. stream a second device while someone uses the PC), drop the DPMS-off
  lines from the connect hook.
- Resolutions are streamed as configured in `monitors.lua`
  (`CLIENT_MODE`); change it and re-run `install.sh` or edit the file.
- X11 is not supported by the headless backend — Hyprland/Wayland only.
