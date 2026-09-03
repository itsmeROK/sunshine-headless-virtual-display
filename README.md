# Sunshine Headless Virtual Display (Hyprland & Omarchy)

Stream your Linux desktop to Moonlight **at the client's native resolution**
with a **1:1 (pixel-perfect)** image, instead of a scaled/downscaled 4K frame
that looks soft.

It works by creating a **persistent headless virtual monitor** (`HEADLESS-1`)
and pointing Sunshine at it. When a Moonlight client connects, the headless is
resized to match the client's resolution, your workspaces migrate onto it, and
the physical monitor turns off; on disconnect everything is restored.

```
┌──────────────────┬──────────────────────────┐
│  HEADLESS-1      │   DP-1 (physical 4K)     │
│  (stream display)│                          │
│  ws 11 (reserved)│   workspaces 1-10        │
│  720p default @ 0x0│   (auto-placed right)    │
│                  │   turns OFF during stream│
└──────────────────┴──────────────────────────┘
  receiver cursor maps to headless origin (0,0)
```

## Features

- **Pixel-perfect 1:1 streaming** — no more downscaled/soft 4K frames.
- **Per-client resolution** — the headless is resized automatically to each
  client's native resolution on connect (via Sunshine's client variables).
- **Cheap idle default (720p)** — saves VRAM when nobody is streaming.
- **Workspaces follow the stream** — your workspaces migrate to the headless
  and back automatically; the physical monitor turns off/on.
- **Broad Hyprland support** — works on modern Lua configs and falls back to
  legacy dispatchers on pre-Lua Hyprland.
- **Self-contained installer** — `install.sh` auto-detects your physical output
  and config provider; no per-machine edits.

## Requirements

- Hyprland (Wayland, wlroots), incl. Omarchy
- Sunshine installed and working
- GPU with hardware encoding (VAAPI on AMD/Intel, NVENC on NVIDIA)
- `python3` (used by the hooks to parse `hyprctl` JSON)

## Install on a fresh machine

```bash
git clone https://github.com/itsmeROK/sunshine-headless-virtual-display.git sunshine-headless-virtual-display
cd sunshine-headless-virtual-display

# interactive - asks for the headless idle default, then installs
./scripts/install.sh

# non-interactive (fix the resolution up front)
CLIENT_MODE=2560x1440@60 ./scripts/install.sh

# or other options:
PHYSICAL_DP=HDMI-A-1   REMOTE_WS=12   ./scripts/install.sh

# dry-run: check the machine and report what would change, change nothing
./scripts/install.sh --check
```

`install.sh` asks for the **headless idle default resolution** on first run
(menu: 720p default, 1080p, QHD, or a custom `WxH@rate`). The actual stream
resolution is applied dynamically per client by the connect hook, so this
default only sets the cheap resolution the headless starts and rests at. The
choice is saved to `~/.config/sunshine-headless/mode` and reused next time;
passing `CLIENT_MODE=...` overrides it.

`install.sh` is idempotent and backs up every file it touches. It detects your
physical output name + Hyprland config provider, installs the hooks, merges
`monitors.lua` and `sunshine.conf`, and installs an Omarchy `post-boot` hook so
Sunshine is running after login.

> **Note:** `install.sh` does **not** touch your firewall. Make sure Sunshine's
> ports (47984–48010 TCP/UDP) are reachable if you use one.

Then connect from Moonlight. First connection asks for a PIN on the Sunshine
web panel as usual.

## Uninstall

```bash
./scripts/uninstall.sh        # interactive confirm
./scripts/uninstall.sh --yes  # no prompt
```

Removes the helper scripts, the `monitors.lua` block we added, resets
`sunshine.conf`, and deletes the Omarchy post-boot hook. Backups
(`*.bak.<ts>`) are left in place for manual recovery.

## Documentation

- **Technical reference** (architecture, hooks, resolution logic, legacy
  support, file layout): [`docs/Tech.md`](docs/Tech.md)
