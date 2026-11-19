# Deck for Linux & Raspberry Pi

Rust + GTK4 implementation, planned in
[`docs/planning/linux-port/`](../../docs/planning/linux-port/). This tree is at
**L1**: core, snapshot contract, credentials, daemon and CLI. The GTK4 shell
and widgets arrive in L2+.

## Build and test

```bash
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p deck-cli -- --version
cargo run -p deckd -- --once
```

On Raspberry Pi OS Trixie, the build dependencies are:

```bash
sudo apt install cargo rustc build-essential pkg-config
```

GTK4 and `gtk4-layer-shell` are not needed until L2.

## Layout

```
crates/deck-core      settings, XDG paths, snapshots, credentials, session
crates/deck-platform  platform backends (L2) and session decision
crates/deckd          background sampler / systemd user service
crates/deck-gui       GTK4 shell (placeholder in L1)
crates/deck-cli       `deck` command
contracts             snapshot v1 schema and shared payload fixtures
packaging             systemd unit and autostart entry
```

## Runtime paths

- settings: `$XDG_CONFIG_HOME/deck/settings.json`
- 0600 credentials fallback: `$XDG_CONFIG_HOME/deck/credentials.json`
- snapshots and fetch status: `$XDG_DATA_HOME/deck/`
- cache: `$XDG_CACHE_HOME/deck/`

Secret Service is used through `secret-tool` when it exists; otherwise the
0600 file is used. A token never appears in a snapshot or the settings file.

## L0 evidence

The Pi 4B / Pi OS Trixie / labwc spike is recorded in
[`docs/planning/linux-port/spike.md`](../../docs/planning/linux-port/spike.md).
