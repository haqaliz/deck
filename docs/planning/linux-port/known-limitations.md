# Deck for Linux — known limitations (v0.1.0)

Deck on Linux is a **Pi-first v1**. This page is the honest boundary of what was
verified on the hardware available.

## Tested

- Raspberry Pi 4B (4 GB), Raspberry Pi OS Trixie, labwc 0.9.2, GTK 4.18.6.
- Layer-shell desktop widgets, tray, labwc W-Space search, settings, all 13
  widget faces, search providers, the `.deb`, `deckd`, and the X11 branch via
  Xwayland.
- Release build: 3.6 MB `.deb`, ~120 ms socket-ready, 0.53% CPU / 119 MB RSS
  over a 60-second idle sample.

## Not tested

- **Pi 5**: no hardware. The arm64 package should run, but this is not claimed.
- **KDE Plasma, GNOME Wayland, Hyprland/Sway, XFCE/i3**: no machines. The code
  uses the shared layer-shell backend for KDE/wlroots and a normal dashboard
  window for GNOME, but the matrix is untested.
- **GNOME Wayland desktop widgets**: Mutter has no `wlr-layer-shell`, so GNOME
  gets normal windows (dashboard fallback), an optional gsettings shortcut and
  no guaranteed tray. A Shell extension is post-v1.
- **X11 on a native WM**: the app sets `_NET_WM_WINDOW_TYPE_DESKTOP`,
  below/skip-taskbar/skip-pager and non-focusable hints. labwc's Xwayland
  integration still tiles the windows and lists them in its panel; a native
  X11 WM may honour the hints, but that was not verified. X11 placement is the
  window manager's job.
- **Multi-monitor**: the flow moves a full column to the next monitor, but no
  second display was available to verify it.
- **Secret Service**: the Pi has no `secret-tool`/keyring, so the 0600 fallback
  was the only exercised path. Desktop keyrings remain to be checked.
- **Live GitHub, Azure DevOps, Elastic and Grafana**: no tokens/clusters were
  available. Their parsers and faces are fixture/seeded-snapshot tested; the
  live fetch and Verify buttons are not.
- **AppImage on a clean desktop**: the CI artifact bundles GTK4,
  gtk4-layer-shell, X11/font and Wayland libraries and was inspected with
  `unsquashfs`, but it was not launched on a clean Ubuntu/Fedora machine. It
  needs FUSE 2 at runtime (`--appimage-extract-and-run` works without it, at
  the cost of extracting first).

## Deliberate v1 gaps

- Search is snapshot/local. It makes no network request at search time, so
  remote full-text search, the per-source floor and 429 isolation at search
  time are not implemented. Fetch-time 429 is reported as `rateLimited` and
  keeps the last good snapshot.
- Kibana/Grafana links open the configured base page, not a query-specific
  deep link.
- One account per provider in the Linux Credentials tab; multi-account and
  Elastic/Grafana project/environment pickers beyond the typed fields are
  deferred.
- OpenBox remote-server mode, ShipBox automatic discovery, PR review-state
  glyphs and the Market live picker are deferred.
- No KDE KGlobalAccel/portal shortcut write; the CLI prints the binding
  snippet. labwc and GNOME have installers.
- No auto-update, Flatpak, ARM32 or Pi Zero.
- CalBox, ClipBox and BatBox are deferred; PiBox is explicitly out of v1.
- Per-monitor user arrangement and drag-to-place widgets are not in v1;
  placement is automatic.

## Reporting a problem

Include the Deck version (`deck --version`), Pi OS version, desktop/compositor
and the contents of `~/.cache/deck/last-error.log` if the GUI crashed. Tokens
never appear in snapshots, settings, fetch status or crash logs.
