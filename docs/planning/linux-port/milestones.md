# Deck Linux & Raspberry Pi — milestones

**Plan date:** 2026-11-19. **Order:** Pi OS first, then desktop packaging.
**Estimate:** 22-29 weeks for one engineer; about 4-5 months with two people
working in parallel after L1. Treat every date as an estimate, not a promise.

## Milestone map

| ID | Milestone | Estimate | Depends on |
|---|---|---|---|
| L0 | Feasibility spike | 1 week | none |
| L1 | Core, protocol, credentials, CI | 1-2 weeks | L0 |
| L2 | Shell: widget host, settings, tray, search | 3-4 weeks | L1 |
| L3 | System widgets (LiveBox, NetBox, DevBox) | 3-4 weeks | L2 |
| L4 | Network widgets (8) | 4-5 weeks | L1, L2 |
| L5 | LogBox, MetricBox, search providers | 3-4 weeks | L3, L4 |
| L6 | Pi OS packaging + Pi v1 release | 2-3 weeks | L5 |
| L7 | Desktop AppImage + cross-DE matrix | 3-4 weeks | L6 |
| L8 | Hardening + v1 | 2 weeks | L7 |

L0 must pass before L1 is committed beyond a throwaway spike. L4 can start in
parallel with L3 once L1/L2 are stable, but the recommended sequence is linear
so each widget reuses a proven shell.

---

## L0 — Feasibility spike (1 week)

**Goal:** prove the three Linux unknowns before committing to a stack:
widget placement, global shortcut, and tray on the chosen sessions.

### Tasks

- [ ] Pi OS Bookworm 64-bit on a Pi 4 and a Pi 5; desktop session Wayfire.
- [ ] Build a throwaway Rust + GTK4 window. Confirm `libgtk-4-1` and
      `libgtk-4-dev` are available from the Pi OS apt sources.
- [ ] Try `gtk4-layer-shell`: system package first; if absent, build the C
      library from source and link it. Record the exact dependency plan for the
      `.deb`.
- [ ] Place a background/bottom layer-shell window on:
      - Pi OS Wayfire
      - KDE Plasma Wayland
      - Hyprland or Sway
- [ ] Place an X11 desktop/below window on XFCE or i3.
- [ ] Open a normal dashboard window on GNOME Wayland; record that layer-shell
      is unavailable there.
- [ ] Tray: `ksni` StatusNotifierItem on Pi OS panel, KDE, X11, and GNOME with
      the AppIndicator extension. Record what appears without the extension.
- [ ] Shortcut probes:
      - Wayfire: add a `[command]` keybinding to `~/.config/wayfire.ini`
      - KDE: KGlobalAccel D-Bus or the GlobalShortcuts portal
      - GNOME: `gsettings` custom keybinding to a test command
      - X11: `XGrabKey` from a test process
- [ ] Measure GTK4 app RAM/CPU on Pi 4/5 idle, and with one widget surface.
- [ ] Probe Linux GPU backends for LiveBox: AMD `gpu_busy_percent`, Intel
      fdinfo/engine busy, NVIDIA `nvidia-smi`; record which are usable without
      root. Pi GPU is allowed to be absent.
- [ ] Decide: use `gtk4-layer-shell` as a system dependency, vendor it, or use
      a Wayfire/X11 fallback.

### Deliverable

`docs/planning/linux-port/spike.md` with a matrix of results, measurements,
the dependency decision, and a go/no-go for the cross-DE window model.

### Acceptance

- A placeholder widget can be placed behind normal windows on Pi OS Wayfire and
  KDE Wayland.
- Search can be toggled by a shortcut on Pi OS Wayfire, KDE and X11, with a
  documented GNOME `gsettings` equivalent.
- Tray behaviour is known on every v1 session.
- If any item fails, the plan records the fallback before L1 starts.

---

## L1 — Core, protocol, credentials, CI (1-2 weeks)

**Goal:** a headless Linux app that can fetch, store and expose data safely,
before any UI exists.

### Tasks

- [ ] Create the `linux/` Cargo workspace and the five crates from
      `architecture.md`.
- [ ] `deck-core`: settings model, XDG paths, atomic writes, tolerant decode.
- [ ] `contracts/snapshot-v1.json` and fixtures copied from the macOS
      `native/SharedTests/Fixtures/`.
- [ ] `deck-core::credentials`: Secret Service first, 0600 JSON fallback,
      stable item ids, absent/failed distinction.
- [ ] `deckd`: one 60s tick, a hello snapshot, fetch-status files, structured
      logs, clean shutdown.
- [ ] `deck` CLI: `--version`, `--daemon`, `--settings`, `--toggle-search`
      (stub until the GUI exists).
- [ ] `deck-platform` detection skeleton (`auto`, layer-shell, x11, dashboard).
- [ ] systemd user unit file and XDG autostart entry, not enabled by default.
- [ ] CI `linux.yml`: fmt, clippy, tests, x86_64 build; aarch64 build job.
- [ ] Tests: settings round-trip, snapshot schema, credentials fallback,
      no-token-in-snapshot assertion.

### Acceptance

- `cargo test` and `cargo clippy -D warnings` green.
- `deckd` writes a snapshot in `$XDG_DATA_HOME/deck` and exits cleanly.
- A token round-trips through Secret Service and through the 0600 fallback.
- No token appears in any snapshot or settings file.

---

## L2 — Shell: widget host, settings, tray, search (3-4 weeks)

**Goal:** the app a user can see: one placeholder widget, a settings window, a
tray, and a search panel that opens from a shortcut.

### Tasks

- [ ] GTK4 application, single instance over D-Bus, `deck` CLI wired.
- [ ] `deck-platform` backends:
      - layer-shell (Pi OS Wayfire, KDE Wayland, wlroots)
      - X11 desktop/below
      - dashboard (GNOME Wayland)
- [ ] Widget placement model: per-monitor, anchor, margin, size, show/hide,
      remembered in settings; a placement mode in Settings.
- [ ] Settings shell: General, Search, Credentials, one placeholder widget tab.
- [ ] Deck theme: CSS tokens, rounded surfaces, typography, light/dark/system.
- [ ] Tray: Search, Settings, Quit; hide the icon when no tray is available.
- [ ] Autostart: XDG autostart entry, systemd user service, first-run helper.
- [ ] Search panel: layer-shell overlay / X11 overlay / GNOME normal window;
      text field, results area, Esc/Enter, no focus loss on Wayland where
      supported.
- [ ] Shortcut installers:
      - `deck shortcut install --wayfire`
      - KDE KGlobalAccel/portal path
      - GNOME `gsettings` keybinding
      - X11 grab with CLI fallback
- [ ] GNOME dashboard mode documented and selectable.
- [ ] Manual smoke matrix on Pi OS Wayfire, KDE, GNOME, wlroots, X11.

### Acceptance

- A placeholder widget sits behind windows on Pi OS Wayfire, KDE and wlroots;
  an X11 desktop window on X11; a dashboard on GNOME Wayland.
- A shortcut opens the search panel on Pi OS, KDE and X11; GNOME uses the
  documented gsettings binding.
- Settings persist across restart; the tray offers Search/Settings/Quit where
  the session supports it.
- No crashes on a 30-minute idle/refresh run.

---

## L3 — System widgets (3-4 weeks)

**Goal:** LiveBox, NetBox and DevBox with real Linux/Pi data.

### Tasks

- [ ] CPU: `/proc/stat`, per-core, thresholds, history.
- [ ] Memory: `/proc/meminfo`.
- [ ] Disk: `statvfs`, per-volume list, thresholds.
- [ ] Processes: `/proc` top CPU/MEM, refresh interval, process count.
- [ ] Network: `/proc/net/dev` or netlink, per-interface rates, picker,
      packet/error counters, thresholds.
- [ ] Docker: `docker ps`/`stats` or the Engine API; hide when absent.
- [ ] GPU row: AMD sysfs, NVIDIA `nvidia-smi`, Intel fdinfo; hide when no
      backend; never fabricate 0%.
- [ ] Chart component: Cairo/DrawingArea, same visual language as the macOS
      chart; no Swift Charts.
- [ ] Widget faces: LiveBox small/medium/large, NetBox, DevBox; placement and
      size presets.
- [ ] Tests for every parser and threshold table.
- [ ] Pi 4/5 measurements: idle CPU, widget refresh cost, memory.

### Acceptance

- All three widgets render real data at all sizes on Pi OS and a desktop.
- CPU/mem/disk values match `top`/`free`/`df` within a sensible tolerance.
- Thresholds turn amber/red at the configured values.
- No sustained CPU load from the widgets on a Pi 4 at the default cadence.

---

## L4 — Network widgets (4-5 weeks)

**Goal:** the eight API widgets, with account management and fixture-tested
parsers.

### Tasks

- [ ] Credentials UI: add/edit/delete accounts for GitHub, Azure DevOps,
      opencode, Elastic and Grafana; Verify button; keychain/file fallback.
- [ ] WeatherBox: wttr.in, units, forecast.
- [ ] ClockBox: world clocks, main city, offsets.
- [ ] GitBox: repo scan, commits/day, streak, top repos.
- [ ] OpenBox: local SQLite + remote server mode, models/tools/sessions.
- [ ] ShipBox: GitHub Actions, automatic/static repos, multi-repo merge.
- [ ] TaskBox: Azure DevOps work items, WIQL, accounts/projects.
- [ ] PRBox: GitHub + Azure DevOps, review queue, per-provider settings.
- [ ] MarketBox: crypto/fiat/gold/stocks, display currency, live picker policy.
- [ ] Fetch statuses, retry/stale behavior, offline/empty/error copy.
- [ ] Deep links via `xdg-open`.
- [ ] Copy/port the macOS fixtures and add golden tests for each parser.
- [ ] Widget faces and settings tabs for all eight.

### Acceptance

- Each widget renders real data with the user's accounts; no token in a
  snapshot or log.
- A failed provider shows its own reason and never blanks the others.
- All three sizes and the settings tabs work.
- Goldens cover the success, empty, auth failure and malformed-payload cases.

---

## L5 — LogBox, MetricBox, search providers (3-4 weeks)

**Goal:** the two infra widgets plus the full v1 search experience.

### Tasks

- [ ] LogBox: Elastic counts/trend/templates/recent lines, environment/service
      catalogs, raw-text modes, Kibana deep links.
- [ ] MetricBox: Grafana datasource discovery, fleet/host/power/agents/alerts,
      configurable columns, host/service catalogs, Grafana deep links.
- [ ] Charts for counts/trend/sparkline in Cairo.
- [ ] Search providers for all 13 v1 widgets:
      - local snapshots: system, network, dev, clock, git, open sessions
      - remote: work items, PRs, markets, logs, metrics, weather, ship runs
- [ ] Prefixes and ordering matching macOS; debounce, per-source floor, cache,
      429 degrades one section only.
- [ ] Search panel results: grouped sections, keyboard navigation, Enter opens
      the URL or result.
- [ ] Rate-budget rule: searches run in the GUI on user input, never in `deckd`.
- [ ] Tests for prefix parsing, grouping, cache, and degraded sections.

### Acceptance

- Real LogBox/MetricBox data with the user's read-only credentials.
- Deep links open Kibana/Grafana in the browser.
- Search finds at least one result per ported provider and degrades cleanly
  when one source is down.
- No search request runs on the background tick.

---

## L6 — Pi OS packaging + Pi v1 release (2-3 weeks)

**Goal:** a clean Pi OS install from the `.deb` that feels finished.

### Tasks

- [ ] arm64 `.deb`: dependencies, icons, desktop entries, systemd user unit,
      autostart, uninstall rules.
- [ ] Wayfire shortcut installer and panel/tray fallback (from L0 results).
- [ ] Secret Service fallback warning on first run if no keyring is present.
- [ ] Pi 4 and Pi 5 smoke: install, first run, widgets, settings, search,
      credentials, updates, uninstall.
- [ ] Measure idle CPU, memory, startup time and widget refresh cost.
- [ ] Install docs: Pi OS version, apt command, keybinding, known limits.
- [ ] Release artifact + SHA256; no macOS release changes.

### Acceptance

- Fresh Pi OS Bookworm Wayfire, `apt install ./deck.deb`, launch, add widgets,
  pair one network account, search, quit, uninstall.
- No secret in a snapshot or log; `.deb` dependencies resolve from Pi OS.
- Pi 4 idle overhead is acceptable and recorded in the docs.

---

## L7 — Desktop AppImage + cross-DE matrix (3-4 weeks)

**Goal:** one portable x86_64 artifact that runs on the four desktop targets.

### Tasks

- [ ] AppImage: bundle GTK4, gtk4-layer-shell, icons, desktop file, AppRun.
- [ ] Test on clean Ubuntu and Fedora VMs: KDE Wayland, GNOME Wayland,
      Hyprland/Sway, XFCE/i3.
- [ ] GNOME Wayland: dashboard mode, gsettings shortcut, AppIndicator/tray
      caveat; no layer-shell promise.
- [ ] Multi-monitor placement and per-monitor persistence.
- [ ] X11 desktop window type and focus behavior.
- [ ] KDE KGlobalAccel/portal shortcut path; wlroots compositor snippets.
- [ ] Desktop install docs and known-limitations page.
- [ ] AppImage release + SHA256.

### Acceptance

- The AppImage starts on a clean system without installing GTK4 manually.
- Same widgets and search on KDE, wlroots and X11; GNOME runs the documented
  dashboard fallback.
- Placement survives monitor changes and restarts.

---

## L8 — Hardening + v1 (2 weeks)

**Goal:** a release that can be used daily and trusted.

### Tasks

- [ ] Crash handling: structured logs, last-error screen, no silent blank
      widgets.
- [ ] Offline/timeout/429 behavior on every network widget.
- [ ] Config migration and corrupt-file tolerance.
- [ ] Security pass: 0600 fallback, no token in snapshots/logs, deep-link
      filtering, no writes to remote services.
- [ ] Performance pass on Pi 4/5: idle CPU, memory, startup, widget cadence.
- [ ] Docs: install, first run, search, credentials, platform limits, FAQ.
- [ ] Release checklist: CI green, artifacts, checksums, tag, release notes.
- [ ] Definition of done below.

### Acceptance

The v1 definition of done is met and the known-limitations page is honest about
GNOME Wayland, CalBox, ClipBox, BatBox and Flatpak.

---

## v1 definition of done

1. Pi OS Bookworm Wayfire on Pi 4/5: `.deb` install, 13 widgets, settings,
   search, tray/keybinding, credentials, uninstall.
2. Desktop AppImage on KDE Wayland, wlroots, X11; GNOME Wayland dashboard
   fallback.
3. 13 widgets at small/medium/large with the same faces/thresholds as macOS
   where the data model matches.
4. Search covers every ported provider with the same prefixes and degradation.
5. No token in any snapshot, log or settings file.
6. `cargo test`, `cargo clippy`, x86_64 and aarch64 builds green.
7. Install docs and platform limitations published.

## Post-v1 backlog

- CalBox (CalDAV first, then Google or EDS).
- ClipBox (X11/Pi first; Wayland needs compositor-specific work).
- BatBox (UPower/BlueZ).
- GNOME Shell extension for true desktop widgets.
- Native KDE Plasma widgets, if the cross-DE windows prove insufficient.
- Flatpak, ARM32, Pi Zero.
- PiBox (temperature/throttling/voltage) is explicitly not part of v1; revisit
  only if the owner asks.
- Theme variants and auto-update.

## Start here

Do **L0** first. It is one week of throwaway code and measurements; it decides
whether `gtk4-layer-shell` and the Pi OS panel/tray story are viable. Do not
create the Cargo workspace or port a widget until the L0 matrix is written.
