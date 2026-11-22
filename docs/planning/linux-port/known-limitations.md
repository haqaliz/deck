# Deck for Linux — known limitations (v0.6.1)

Deck on Linux is a **Pi-first v1**. This page is the honest boundary of what was
verified on the hardware available.

## Tested

- Raspberry Pi 4B (4 GB), Raspberry Pi OS Trixie, labwc 0.9.2, GTK 4.18.6.
- Layer-shell desktop widgets, tray, labwc W-Space search, settings, all 13
  widget faces, search providers, the `.deb`, `deckd`, and the X11 branch via
  Xwayland.
- Sway headless (wlroots layer-shell) and X11 + Openbox in Debian Trixie arm64
  containers: widgets on the desktop layer, search on the overlay/above layer.
- Secret Service through `gnome-keyring` + `secret-tool` in a D-Bus session:
  store, read and `deck --check-credentials` green.
- Release build: 3.6 MB `.deb`, ~120 ms socket-ready, 0.53% CPU / 119 MB RSS
  over a 60-second idle sample.

## Not tested

- **Pi 5**: no hardware. The arm64 package should run, but this is not claimed.
- **KDE Plasma, GNOME Wayland, Hyprland, XFCE/i3**: no machines. Sway covers
  the shared wlroots layer-shell path and Openbox covers X11, but the other
  desktops remain untested.
- **GNOME Wayland desktop widgets**: Mutter has no `wlr-layer-shell`, so GNOME
  gets normal windows (dashboard fallback), an optional gsettings shortcut and
  no guaranteed tray. A Shell extension is post-v1.
- **X11 on a native WM**: Openbox honours the desktop/below/skip-taskbar
  hints; the search card is opaque on X11 because there is no compositor blur.
  Evidence is under `docs/planning/linux-port/evidence/l11-x11-*`. Other X11
  window managers are still untested, and placement remains the window
  manager's job.
- **Multi-monitor**: the flow moves a full column to the next monitor, but no
  second display was available to verify it.
- **KWallet**: GNOME Keyring/Secret Service is verified; KWallet is not.
- **CalDAV**: the parser and widget are fixture-tested; no live CalDAV server
  was available.
- **Live GitHub, Azure DevOps, Elastic and Grafana**: no tokens/clusters were
  available. Their parsers and faces are fixture/seeded-snapshot tested; the
  live fetch and Verify buttons are not.
- **AppImage on a clean desktop**: the CI artifact bundles GTK4,
  gtk4-layer-shell, X11/font and Wayland libraries. `ldd` is clean on bare
  Debian Trixie and it ran for 10 seconds under Xvfb with
  `GSK_RENDERER=cairo` (Xvfb has no GL). It was not launched on a clean
  physical Ubuntu/Fedora desktop. It needs FUSE 2 at runtime
  (`--appimage-extract-and-run` works without it, at the cost of extracting
  first).

## Deliberate v1 gaps

- Remote search covers Azure work items, pull requests and Elastic log lines.
  Metrics remains snapshot-only, and the remote sources require a typed
  prefix except work items.
- Kibana log results open a query-specific Discover link; Grafana links still
  open the configured base page.
- Azure supports multiple accounts. GitHub, Elastic, Grafana and opencode
  remain one token per provider.
- GitHub review state needs one per-PR API request and is only fetched when
  the setting is on; Azure reads reviewer votes from the PR list.
- OpenBox remote mode supports servers with session-level usage; older
  per-message servers keep the last/local snapshot.
- The Market picker searches CoinGecko and Yahoo Finance; there is no manual
  symbol browser.
- KDE shortcut install is best-effort via `kwriteconfig6/5` and needs a
  Plasma restart; labwc and GNOME installers are exercised.
- No auto-update, Flatpak, ARM32 or Pi Zero.
- BatBox accessories/BlueZ integration is not populated yet; PiBox is explicitly out of v1.
- Placement is automatic until dragged. Widget title bars and the search
  header can be dragged; positions persist in settings. Per-monitor
  arrangement across monitor changes is not verified (one display available).
- On labwc, Deck writes a marked `windowRule` that puts PCManFM's desktop
  window on the always-on-bottom layer. Without that rule the desktop window
  sits above Deck's bottom layer and swallows pointer input. It is installed
  automatically when `labwc` is running; other window rules are preserved.

## Reporting a problem

Include the Deck version (`deck --version`), Pi OS version, desktop/compositor
and the contents of `~/.cache/deck/last-error.log` if the GUI crashed. Tokens
never appear in snapshots, settings, fetch status or crash logs.
