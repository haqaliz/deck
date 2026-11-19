# L0 — feasibility spike (Pi OS Trixie / labwc)

**Date:** 2026-11-19.
**Hardware:** Raspberry Pi 4B, 4GB RAM.
**OS:** Debian GNU/Linux 13 (trixie), kernel 6.12.47+rpt-rpi-v8.
**Session:** labwc 0.9.2 (`rpd-labwc`), Wayland; panel `wf-panel-pi`.
**Toolchain:** GTK 4.18.6, gtk4-layer-shell 1.0.4, Rust 1.85.1, cargo 1.85.1.

## Results

| Probe | Result |
|---|---|
| GTK4 runtime/dev | `libgtk-4-1` installed; `libgtk-4-dev` installs from Trixie |
| gtk4-layer-shell | `libgtk4-layer-shell0` / `-dev` 1.0.4 in Trixie apt |
| Layer-shell widget | A GTK4 C window with `GTK_LAYER_SHELL_LAYER_TOP` rendered above the terminal; `BOTTOM` presented behind it. Evidence: `evidence/layer-widget.png` |
| Tray | `ksni` 0.3.7 registered `org.kde.StatusNotifierItem-…`; `wf-panel-pi` is both `StatusNotifierWatcher` and host, and showed the icon. Evidence: `evidence/tray-strip.png` |
| Global shortcut | labwc `rc.xml` keybind `A-F12` ran a command; `wtype -M alt -k F12` fired it. `labwc --reconfigure` needs `LABWC_PID`. Config restored after the test. |
| Idle cost | The bare GTK4 layer window used ~95MB RSS and 0.0% CPU over 5s. This is a floor, not the final app. |
| Pi 4/5 | Only a Pi 4B was available; Pi 5 not measured. 4GB is comfortable. |

## What changed from the plan

- The Pi is **Pi OS Trixie / labwc**, not Bookworm / Wayfire. Both are wlroots and
  both support layer-shell, but the shortcut and panel integrations differ.
- `gtk4-layer-shell` does not need vendoring on Trixie; the `.deb` can depend on
  `libgtk4-layer-shell0`.
- Rust 1.85.1 is available from Trixie apt; use it as the v1 toolchain.
- Tray is real on the Pi panel; no fallback is needed for the default session.

## Not tested in L0

- KDE Plasma, GNOME Wayland, Hyprland/Sway, generic X11: no machines were
  available. The abstractions are planned; the matrix moves to L7.
- The search panel's keyboard focus on Wayland, multi-monitor placement, and
  the full GTK4 app's memory/cadence: later milestones.
- Pi 5: only Pi 4B was reachable.

## Decision

**Go for L1.** The Pi OS target has layer-shell, tray and shortcut paths that
all work. The cross-desktop matrix remains a risk handled by `deck-platform`
and L7, with GNOME's dashboard fallback already documented.

## Evidence

- `evidence/layer-widget.png` — a top-layer GTK4 window over the terminal.
- `evidence/tray-strip.png` — the `ksni` monitor icon in the Pi panel.
