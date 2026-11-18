# Deck Linux & Raspberry Pi — PRD

**Status:** planned 2026-11-19. Implementation has not started.
**Source:** product interview, 2026-11-19.
**Related:** `ROADMAP.md` M12, `architecture.md`, `milestones.md`.

## Product

Deck for Linux and Raspberry Pi OS is a **second native app**, not a port of the
macOS codebase. It keeps the same product shape:

- small desktop widgets for the data Deck already knows how to fetch
- one settings app with the same tabs, faces and thresholds
- a Spotlight-style search panel with the same providers and prefixes
- a background service that keeps network snapshots fresh
- the same Deck look, not a native GTK/Qt imitation

The macOS app stays Swift/SwiftUI/WidgetKit. The two apps share a **data
contract** (snapshot schemas, API queries, parser fixtures, credential slots,
thresholds, UX copy), not source code.

## Decisions (owner, 2026-11-19)

| Decision | Choice |
|---|---|
| Widget model | Cross-DE always-on-desktop windows drawn by one app |
| v1 desktops | Pi OS, KDE Plasma, GNOME, wlroots, generic X11 |
| Pi hardware | Pi 5 / Pi 4, 64-bit |
| Pi OS session | Bookworm Wayfire |
| UI stack | Rust + GTK4 |
| macOS | Keep Swift; share the JSON/API contract |
| v1 widgets | 13: LiveBox, NetBox, DevBox, Weather, Clock, Git, Open, Ship, Task, PR, Market, Log, Metric |
| Pi hardware widget | No (PiBox not in v1) |
| CalBox | Deferred |
| ClipBox | Deferred |
| Search | Deck panel + shortcut, all ported providers |
| Credentials | Secret Service, 0600 file fallback |
| Packaging | Pi `.deb`, desktop AppImage |
| Release order | Pi OS first, desktop next |
| Look | Deck's own look |
| Startup | Autostart + tray |

## v1 scope

### Widgets

| Widget | v1 | Notes |
|---|---|---|
| LiveBox | yes | CPU/mem/disk on Linux and Pi; GPU row only where a vendor backend exists |
| NetBox | yes | `/proc/net/dev` or netlink |
| DevBox | yes | processes and Docker containers |
| WeatherBox | yes | wttr.in |
| ClockBox | yes | local time zones |
| GitBox | yes | `git log` |
| OpenBox | yes | local opencode SQLite and remote mode |
| ShipBox | yes | GitHub Actions |
| TaskBox | yes | Azure DevOps |
| PRBox | yes | GitHub + Azure DevOps |
| MarketBox | yes | keyless price sources |
| LogBox | yes | Elastic |
| MetricBox | yes | Grafana |
| CalBox | no | no EventKit; backend choice deferred |
| ClipBox | no | Wayland blocks background clipboard |
| BatBox | no | no battery requirement on Pi; deferred |

### Shell

- Cross-DE widget windows with remembered per-monitor placement.
- Settings window with the same sections as macOS: General, Search,
  Credentials, and one tab per v1 widget.
- Search panel with the same prefixes and rate policies.
- Tray icon (StatusNotifierItem) with Search, Settings, Quit.
- Autostart at login.
- systemd user service for the background sampler.

### Packages

- Raspberry Pi OS Bookworm arm64 `.deb`.
- x86_64 AppImage for desktop distributions.
- No Flatpak in v1: a system monitor needs host `/proc`, `/sys`, GPU and Docker
  access that a default Flatpak sandbox blocks.
- No ARM32, Pi Zero, or Pi 1 in v1.

## Platform matrix and known limits

| Platform | Widget placement | Shortcut | Tray |
|---|---|---|---|
| Pi OS Bookworm Wayfire | layer-shell if supported; Wayfire window rule fallback (L0) | Wayfire keybinding installer | panel support to verify in L0 |
| KDE Plasma Wayland | layer-shell | KGlobalAccel / GlobalShortcuts portal | StatusNotifierItem |
| GNOME Wayland | **no layer-shell**: dashboard window fallback | `gsettings` custom keybinding to `deck --toggle-search` | AppIndicator extension, otherwise none |
| wlroots (Hyprland/Sway) | layer-shell | compositor keybinding to `deck --toggle-search` | bar/StatusNotifier where present |
| Generic X11 | `_NET_WM_WINDOW_TYPE_DESKTOP` / below | `XGrabKey` | StatusNotifierItem |

**The GNOME limit is real:** Mutter does not implement `wlr-layer-shell`. With
the chosen cross-DE window model, v1 on GNOME Wayland cannot put widgets behind
normal windows. It ships a dashboard/floating-window mode, a `gsettings`
shortcut, and no guaranteed tray. Always-on-desktop widgets on GNOME would need
a Shell extension, which is explicitly out of v1.

## Non-goals

- Native KDE plasmoids or a GNOME Shell extension.
- CalBox, ClipBox, BatBox, PiBox.
- Flatpak, Snap, ARM32, Pi Zero.
- macOS changes or a shared Rust core with Swift.
- Notarization or macOS release changes.
- Auto-update; package managers and AppImage updates are the update path.

## Success criteria

1. A clean Pi OS Bookworm install from the `.deb` shows the v1 widgets on the
   desktop, opens Search with the installed shortcut, and exposes Settings and
   the tray.
2. The AppImage runs on KDE Wayland, wlroots, and X11 with the same widgets and
   search; GNOME Wayland runs the documented dashboard fallback.
3. All 13 v1 widgets render real data at small/medium/large sizes, with the same
   faces, text modes and thresholds as macOS where the data model matches.
4. Search covers every ported provider with the same prefixes and degradation
   rules.
5. No token appears in a snapshot, log, or settings file; the 0600 fallback is
   used only when Secret Service is unavailable.
6. A Pi 4 and a Pi 5 both run the full v1 widget set without sustained CPU or
   memory pressure; measured numbers are recorded.
7. `cargo test`, `cargo clippy`, and the aarch64/x86_64 CI builds are green.
