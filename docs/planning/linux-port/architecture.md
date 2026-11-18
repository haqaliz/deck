# Deck Linux & Raspberry Pi — architecture

**Status:** planned 2026-11-19. L0 must confirm the platform unknowns before
code is committed beyond the spike.

## Stack

- **Rust** stable, one Cargo workspace under `linux/`.
- **GTK4** via `gtk-rs` for every window: widgets, settings, search, tray menu.
- **gtk4-layer-shell** for background/bottom widget surfaces on Wayland;
  X11 uses desktop/below window types.
- **ksni** for the StatusNotifierItem tray.
- **tokio + reqwest (rustls)** for scheduled fetches and search.
- **serde/serde_json** for settings and snapshots.
- **rusqlite** for OpenBox (opencode DB).
- **zbus** for single-instance, search toggling, and desktop integration.
- **oo7 or secret-service** for the Secret Service; 0600 JSON fallback.
- **Cairo/DrawingArea** for the small charts. No webview, no Electron, no
  SwiftUI.

GTK4 is the choice because it is native on GNOME and available on Pi OS
Bookworm, while still running on KDE and wlroots. `gtk4-layer-shell` packaging
on Pi OS is an L0 question; if the library is not in Bookworm, the `.deb`
vendors it or the affected surface falls back to a normal window.

## Processes

```
deckd        background sampler (systemd user service)
  ├─ system samples: LiveBox, NetBox, DevBox
  ├─ network snapshots: Open/Ship/Task/PR/Market/Log/Metric/Weather
  └─ writes ~/.local/share/deck/*.json + fetch-*.json

deck-gui     GTK4 app (autostart, tray)
  ├─ widget windows
  ├─ settings window
  ├─ search panel (read snapshots + remote search on user input)
  └─ tray: Search, Settings, Quit

deck         CLI
  ├─ --toggle-search   → D-Bus to deck-gui; launches it if absent
  ├─ --settings        → opens the settings window
  ├─ --daemon          → runs deckd in the foreground (for debugging)
  └─ --version
```

Why a daemon: network snapshots must stay fresh with the settings window
closed, and the Pi should not pay for a full GUI to keep data current. Why the
GUI does search: mirror macOS's rule that user-initiated searches never starve
the background fetch budget.

Single instance: `io.github.haqaliz.deck` on the session bus. The CLI and
autostart both talk to the same GUI process.

## Workspace layout

```
linux/
├── Cargo.toml
├── crates/
│   ├── deck-core/          # config, credentials, snapshots, providers, search
│   ├── deck-platform/      # layer-shell/X11/dashboard, shortcut, DE detection
│   ├── deckd/              # background service
│   ├── deck-gui/           # GTK4 shell, widgets, settings, search, tray
│   └── deck-cli/           # `deck` binary
├── contracts/              # snapshot JSON schema + fixtures
├── assets/                 # Deck CSS, icons, widget faces
├── packaging/
│   ├── deb/                # arm64 .deb, systemd unit, desktop files
│   └── appimage/           # x86_64 AppImage
└── README.md
```

`deck-core` is the only crate the daemon and GUI both depend on. It must not
import GTK. The GUI crate owns every pixel; the daemon owns every scheduled
fetch.

## Shared contract with macOS

The macOS app is the source of truth for the v1 snapshot shape, but the Linux
app does not need byte-for-byte compatibility with every macOS field. The
contract is:

- `schema_version: 1`
- `written_at` (ISO-8601)
- one payload per widget
- a separate `fetch-<source>.json` with `outcome` and `attempted_at`
- credentials never appear in either file

`linux/contracts/snapshot-v1.json` defines the wire shape, and
`linux/contracts/fixtures/` copies the real macOS fixtures that already exist
under `native/SharedTests/Fixtures/`. Parser tests on Linux use the same bytes,
so a change in one app is visible in the other.

Config and data use XDG paths:

- settings: `$XDG_CONFIG_HOME/deck/settings.json` (0600; no tokens)
- credentials fallback: `$XDG_CONFIG_HOME/deck/credentials.json` (0600)
- snapshots: `$XDG_DATA_HOME/deck/`
- cache/history: `$XDG_CACHE_HOME/deck/`

## Platform abstraction

`deck-platform` exposes:

```rust
trait WidgetSurface {
    fn show(&self, config: SurfaceConfig) -> Result<SurfaceHandle>;
    fn update(&self, handle: &SurfaceHandle, content: WidgetContent);
    fn hide(&self, handle: &SurfaceHandle);
}
```

Backends:

1. **LayerShell** (`gtk4-layer-shell`) for Wayfire, KDE Wayland and wlroots.
   Layer `background` or `bottom`, no keyboard focus, per-monitor anchors and
   margins.
2. **X11** for generic X11 desktops and GNOME-on-X11. Set
   `_NET_WM_WINDOW_TYPE_DESKTOP` or `_NET_WM_STATE_BELOW`, skip taskbar/pager,
   and place per monitor with x11rb.
3. **Dashboard** for GNOME Wayland. Mutter has no `wlr-layer-shell`; the app
   opens normal borderless windows or one dashboard window. This is the
   documented GNOME fallback, not a bug.

Detection order: `WAYLAND_DISPLAY` + `XDG_CURRENT_DESKTOP` → LayerShell on
KDE/wlroots/Wayfire; → Dashboard on GNOME; `DISPLAY` without Wayland → X11.
Settings expose an override (`auto`, `layer-shell`, `x11`, `dashboard`) for
testing and unusual compositors.

### Shortcuts

| Session | Mechanism |
|---|---|
| KDE | KGlobalAccel D-Bus, or `org.freedesktop.portal.GlobalShortcuts` |
| GNOME | `gsettings` custom keybinding to `deck --toggle-search` |
| Wayfire | append a `[command]` binding to `~/.config/wayfire.ini` from `deck shortcut install` |
| wlroots | print the compositor config snippet; no universal file |
| X11 | `XGrabKey` in the GUI, with the CLI command as fallback |

The CLI command is the lowest common denominator everywhere. A failed shortcut
install must never block the app; the tray/CLI path still works.

### Tray

`ksni` publishes a StatusNotifierItem. KDE and most bars show it; GNOME needs
the AppIndicator extension. Pi OS's panel support is an L0 probe. If no tray is
available, Settings and Search remain reachable through the shortcut and
`deck --settings`.

## Search

- Panel: layer-shell overlay on Wayland; override-redirect/desktop overlay on
  X11; a normal window on GNOME Wayland.
- Providers: one per ported widget, same prefixes and ordering as macOS.
- Remote providers run in the GUI on user interaction only, with the same
  debounce/floor/cache/429 policy as macOS.
- Local providers read snapshots; no network.
- Opening a result uses `xdg-open` on http(s) URLs. No custom URL scheme.

## Credentials

- Prefer Secret Service (`org.freedesktop.secrets`) with a stable item name
  `deck.<account-id>.token`.
- If no Secret Service is available (common on a minimal Pi OS), write
  `credentials.json` with `0600` and a warning in Settings.
- Verified identity and cached non-secret fields stay in `settings.json`.
- Tokens are hydrated into memory only when a fetch/search needs them.
- The `deckd` and GUI both read the same store; a locked keyring is reported as
  `credentialsUnavailable`, never as "paste a token again".

## Packaging and CI

- **Pi `.deb`**: arm64, GTK4 runtime, systemd user unit, desktop entries,
  autostart, icons, shortcut installer. The postinst does not enable a user
  service silently; the app offers `deck --install-autostart` or the settings
  toggle.
- **AppImage**: x86_64, bundles GTK4, gtk4-layer-shell and icons; Secret Service
  is still the host D-Bus service, with the 0600 fallback.
- **CI** `linux.yml`: fmt, clippy, tests, x86_64 release build; aarch64 build
  via cross/QEMU or a self-hosted Pi runner; package artifacts on tags.
- No live API tests in CI; fixtures only.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| GNOME Wayland has no layer-shell | No true desktop widgets | Dashboard fallback in v1; Shell extension explicitly out of scope |
| Wayfire lacks layer-shell or tray support | Pi OS widget/tray design breaks | L0 probe; Wayfire window-rule fallback; keybinding instead of tray |
| `gtk4-layer-shell` not packaged on Pi OS | `.deb` dependency problem | Vendor/build the C library, or use the Wayfire fallback |
| GTK4 not installed/too heavy on Pi OS | Install/performance risk | L0 measures; `.deb` declares deps; Pi 4/5 only |
| Global shortcuts on Wayland | Search shortcut not automatic | CLI `--toggle-search` everywhere; per-DE installers; manual fallback |
| ARM64 packaging/CI | Slow or broken release | Cross-build + Pi smoke; no live tests |
| 13 widgets is a lot | Long path to v1 | Milestones L3-L5 split system, network, logs/metrics |
| Secret Service absent on Pi | Token storage fallback | 0600 file with explicit warning; never in snapshots |
| AppImage GTK4 bundling | Large/fragile artifact | linuxdeploy + AppRun; test on clean Ubuntu/Fedora |
