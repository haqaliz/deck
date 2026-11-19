# Deck for Linux & Raspberry Pi

Rust + GTK4 implementation, planned in
[`docs/planning/linux-port/`](../../docs/planning/linux-port/). This tree is at
**L2**: core, snapshot contract, credentials, daemon, CLI and the GTK4 shell
(widget surface, settings, tray, search and the labwc shortcut) on Pi OS
labwc. The system/network widgets arrive in L3+.

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
  libgtk-4-dev libgtk4-layer-shell-dev libgtk4-layer-shell0
```

## Layout

```
crates/deck-core      settings, XDG paths, snapshots, credentials, session,
                      autostart and the labwc shortcut installer
crates/deck-platform  layer-shell/default surfaces and session decision
crates/deckd          background sampler / systemd user service
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

## L0 / L2 evidence

- [`docs/planning/linux-port/spike.md`](../../docs/planning/linux-port/spike.md)
  — Pi 4B / Trixie / labwc layer-shell, tray and shortcut spike.
- [`docs/planning/linux-port/l2.md`](../../docs/planning/linux-port/l2.md) —
  GTK4 shell, settings, search, tray, autostart and labwc shortcut.
