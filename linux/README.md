# Deck for Linux & Raspberry Pi

Rust + GTK4 implementation, planned in
[`docs/planning/linux-port/`](../../docs/planning/linux-port/). This tree is at
**v0.1.1 (L8)**: core, snapshot contract, credentials, daemon, CLI, the GTK4
shell, all 13 widgets, the search panel, the Pi `.deb` and the desktop
AppImage. Pi OS labwc is the verified target; KDE/GNOME/wlroots/X11 are coded
but not claimed as tested. Network fetches use the system `curl`; OpenBox uses
bundled SQLite.

## Install on Raspberry Pi OS

```bash
sudo dpkg -i deck_0.1.1_arm64.deb
deck-gui                 # starts the widgets, tray and socket
deck --install-shortcut  # labwc W-Space, GNOME Super+Space, or printed snippet
```

Autostart is controlled by the General tab. The optional background sampler:

```bash
systemctl --user enable --now deckd
```

Uninstall with `sudo dpkg -r deck`. User settings in `~/.config/deck` and
snapshots in `~/.local/share/deck` are kept; remove the shortcut first with
`deck --remove-shortcut`. The package recommends `libsecret-tools`; without a
keyring, tokens live in the 0600 fallback file and Settings shows the warning.

## First run

1. Start `deck-gui` (or log out/in after enabling autostart). The tray menu has
   Search, Settings and Quit; `deck --toggle-search` and the installed
   shortcut open the panel.
2. Drag a widget's title (or the search panel's header) to move it; positions
   are saved and restored on the next start. Open Settings → Widgets for each
   face's page, size and enable switch. Changes to size/visibility apply on
   restart.
3. Open Settings → Credentials for GitHub, Azure DevOps, Elastic, Grafana and
   the local opencode check. Without a keyring the tokens go to a 0600 file;
   the General tab repeats that warning.
4. Start `deckd` (user service or `deckd --once`) for the network/snapshot
   widgets. The GUI still renders the last good snapshot when a source fails.

## Search

Type without a prefix to search all local providers. A prefix scopes after a
space (typing `port` alone is still normal text).

| Prefix | Finds |
|---|---|
| `port` | listening ports and Docker containers |
| `time` | curated/configured world clocks |
| `oc` | recent opencode sessions |
| `run` | GitHub Actions runs |
| `sys` | processes |
| `net` | network interfaces |
| `git` | configured repositories |
| `weather` | the current weather snapshot |
| `bug`, `pbi`/`backlog`/`story`, `epic`, `feature`, `task`, `wi` | Azure work items by type |
| `pr` | GitHub/Azure pull requests |
| `log` | LogBox services/templates/recent lines |
| `metric` | Grafana hosts, agents and alerts |
| `mkt` | MarketBox rows |

Up/Down selects, Enter or a click copies a local result or opens a URL, Escape
closes. Search never makes a network request; it reads the snapshots `deckd`
maintains.

## AppImage

The CI artifact `deck_0.1.1_x86_64.AppImage` bundles GTK4,
gtk4-layer-shell and the X11/font/Wayland libraries. Make it executable and
run it; if FUSE 2 is unavailable, use `--appimage-extract-and-run`. It was
smoke-tested under Xvfb with software rendering; a clean physical desktop
remains a known-limitations item.

## Packaging

```bash
VERSION=0.1.1 bash packaging/build-deb.sh       # arm64 .deb on the Pi
VERSION=0.1.1 bash packaging/build-appimage.sh  # x86_64 AppImage on a GTK4 desktop
```

## Build and test

```bash
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p deck-cli -- --version
cargo run -p deckd -- --once
cargo run -p deck-gui                 # GTK4 shell (needs a Wayland/X11 session)
cargo run -p deck-cli -- --toggle-search
cargo run -p deck-cli -- --install-shortcut
```

On Raspberry Pi OS Trixie, the build dependencies are:

```bash
sudo apt install cargo rustc build-essential pkg-config \
  libgtk-4-dev libgtk4-layer-shell-dev libgtk4-layer-shell0 curl
```

## Layout

```
crates/deck-core      settings, XDG paths, snapshots, credentials, session,
                      autostart, labwc shortcut, metric samplers and providers
crates/deck-platform  layer-shell/default surfaces and session decision
crates/deckd          background sampler / systemd user service; fetches every
                      enabled widget on a 60s tick
crates/deck-gui       GTK4 shell, widget surface, settings, tray and search
crates/deck-cli       `deck` command, socket control and shortcut install
assets                Deck CSS and icons
contracts             snapshot v1 schema and shared payload fixtures
packaging             systemd unit and autostart entry
```

## Runtime paths

- settings: `$XDG_CONFIG_HOME/deck/settings.json`
- 0600 credentials fallback: `$XDG_CONFIG_HOME/deck/credentials.json`
- snapshots and fetch status: `$XDG_DATA_HOME/deck/`
- control socket: `$XDG_RUNTIME_DIR/deck.sock` (cache fallback)
- cache: `$XDG_CACHE_HOME/deck/`

Secret Service is used through `secret-tool` when it exists; otherwise the
0600 file is used. A token never appears in a snapshot or the settings file.

## Known limitations

[`docs/planning/linux-port/known-limitations.md`](../../docs/planning/linux-port/known-limitations.md)
is the authoritative v1 boundary: Pi 5, KDE/GNOME/wlroots/X11, keyrings, live
API accounts, X11 WM hints and the AppImage runtime are explicitly described.

## L0 / L2-L8 evidence

- [`docs/planning/linux-port/spike.md`](../../docs/planning/linux-port/spike.md)
  — Pi 4B / Trixie / labwc layer-shell, tray and shortcut spike.
- [`docs/planning/linux-port/l2.md`](../../docs/planning/linux-port/l2.md) —
  GTK4 shell, settings, search, tray, autostart and labwc shortcut.
- [`docs/planning/linux-port/l3.md`](../../docs/planning/linux-port/l3.md) —
  LiveBox, NetBox, DevBox, sizes, thresholds and Pi measurements.
- [`docs/planning/linux-port/l4.md`](../../docs/planning/linux-port/l4.md) —
  network widgets, settings hub, credentials and fixture coverage.
- [`docs/planning/linux-port/l5.md`](../../docs/planning/linux-port/l5.md) —
  LogBox, MetricBox, charts and the search panel.
- [`docs/planning/linux-port/l6.md`](../../docs/planning/linux-port/l6.md) —
  Pi `.deb`, install/uninstall and release measurements.
- [`docs/planning/linux-port/l7.md`](../../docs/planning/linux-port/l7.md) —
  surface override, X11 smoke, shortcut paths, multi-monitor flow and AppImage.
- [`docs/planning/linux-port/l8.md`](../../docs/planning/linux-port/l8.md) —
  hardening, release checklist and the final artifacts.
