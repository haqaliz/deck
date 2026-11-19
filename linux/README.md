# Deck for Linux & Raspberry Pi

Rust + GTK4 implementation, planned in
[`docs/planning/linux-port/`](../../docs/planning/linux-port/). This tree is at
**L5**: core, snapshot contract, credentials, daemon, CLI, the GTK4 shell, the
system and network widgets, LogBox/MetricBox and the 13-provider search panel
on Pi OS labwc. KDE/GNOME/X11 are L7. Network fetches use the system `curl`;
OpenBox uses bundled SQLite.

## Install on Raspberry Pi OS

```bash
sudo dpkg -i deck_0.1.0_arm64.deb
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

## L0 / L2-L5 evidence

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
