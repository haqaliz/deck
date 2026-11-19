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

## L0 — Feasibility spike (done 2026-11-19)

**Goal:** prove the three Linux unknowns before committing to a stack:
widget placement, global shortcut, and tray on the chosen sessions.

**Result:** the Pi OS target is **Trixie / labwc**, and all three pass there.
KDE, GNOME and X11 had no machine in this environment, so their probes move to
L7. See [`spike.md`](spike.md).

### Tasks

- [x] Pi OS Trixie 64-bit on a Pi 4B (4GB); desktop session labwc. Pi 5 was not
      available.
- [x] GTK4 dev packages from the Pi OS apt sources (`libgtk-4-dev`).
- [x] `gtk4-layer-shell` 1.0.4 is packaged for Trixie; no vendoring needed
      there. Bookworm would need a vendored build if supported later.
- [x] Place a background/bottom and top layer-shell window on Pi OS labwc.
- [ ] KDE Plasma Wayland, Hyprland/Sway: no machine; deferred to L7.
- [ ] X11 desktop/below window on XFCE or i3: no machine; deferred to L7.
- [ ] GNOME Wayland dashboard window: no machine; deferred to L7, and the
      no-layer-shell limitation is already documented.
- [x] Tray: `ksni` StatusNotifierItem appears in `wf-panel-pi`, which owns the
      StatusNotifier watcher/host. KDE/X11/GNOME tray checks move to L7.
- [x] Shortcut: labwc `rc.xml` keybind (A-F12) fired via `wtype`; `LABWC_PID`
      is required for `labwc --reconfigure`. KDE/GNOME/X11 probes move to L7.
- [x] Measure GTK4 idle: the bare layer window used ~95MB RSS and 0.0% CPU on
      the Pi 4; this is a floor, not the final app.
- [ ] Probe AMD/Intel/NVIDIA GPU backends: deferred to L3, when LiveBox is
      ported. The Pi's VideoCore GPU is allowed to be absent.
- [x] Decide: system `libgtk4-layer-shell0` on Trixie; vendoring only if a
      Bookworm package is added.

### Deliverable

[`spike.md`](spike.md) with the matrix, measurements, dependency decision and
go/no-go.

### Acceptance

- Pi OS labwc: layer-shell, tray and shortcut are all verified.
- KDE/GNOME/X11: explicitly deferred to L7; the abstractions are designed but
  not claimed as tested.
- L1 may proceed.


---

## L1 — Core, protocol, credentials, CI (done 2026-11-19)

**Goal:** a headless Linux app that can fetch, store and expose data safely,
before any UI exists.

### Tasks

- [x] Create the `linux/` Cargo workspace and the five crates from
      `architecture.md`.
- [x] `deck-core`: settings model, XDG paths, atomic writes, tolerant decode.
- [x] `contracts/snapshot-v1.json` and `fetch-status-v1.json`; payload fixtures
      land with the parsers in L3+.
- [x] `deck-core::credentials`: Secret Service through `secret-tool`, 0600 JSON
      fallback, stable item ids. The Pi has no `secret-tool`, so the fallback is
      the active path; a keyring round-trip remains a desktop check.
- [x] `deckd`: `--once` and 60s loop, hello snapshot, fetch-status file. Plain
      stdout for now; structured tracing moves to L2.
- [x] `deck` CLI: `--version`, `--daemon`, `--settings`, `--toggle-search`
      (stub until the GUI exists).
- [x] `deck-platform` detection skeleton (`auto`, layer-shell, x11, dashboard).
- [x] systemd user unit and XDG autostart entry, not enabled by default.
- [x] CI `linux.yml`: fmt, clippy, tests, x86_64 build; aarch64 cross build.
- [x] Tests: settings round-trip, snapshot schema, credentials fallback,
      atomic permissions. 18 tests green on the Pi; `cargo fmt` and
      `cargo clippy -D warnings` green; release build green.

### Acceptance

- `cargo test` and `cargo clippy -D warnings` green on the Pi.
- `deckd` writes a snapshot in `$XDG_DATA_HOME/deck` and exits cleanly.
- The 0600 fallback round-trips; Secret Service is implemented but not exercised
  on this Pi because `secret-tool`/a keyring is absent.
- No token appears in any snapshot or settings file.

**Known limitation:** the Secret Service path is code-complete but unverified
against a real keyring. Verify it on a desktop with GNOME Keyring/KWallet in L2
before calling credentials fully done.


---

## L2 — Shell: widget host, settings, tray, search (done 2026-11-19, Pi vertical slice)

**Goal:** the app a user can see: one placeholder widget, a settings window, a
tray, and a search panel that opens from a shortcut.

### Tasks

- [x] GTK4 application, single instance over a Unix socket, `deck` CLI wired.
- [x] `deck-platform` layer-shell surfaces on Pi OS labwc (KDE/wlroots share
      the backend; untested). X11 desktop/below and the GNOME dashboard fallback
      are coded as normal windows and move to L7.
- [x] Widget placement: a fixed anchor/margin model for the Pi vertical slice;
      per-monitor placement and settings persistence are L7.
- [x] Settings shell: General, Search, Credentials and Widgets tabs; autostart
      toggle; shortcut installer.
- [x] Deck theme: dark Deck CSS, rounded surfaces, readable tabs and header.
- [x] Tray: Search, Settings, Quit via `ksni`; icon verified in `wf-panel-pi`.
- [x] Autostart: XDG desktop entry written by the General toggle; the systemd
      unit exists from L1 but is not enabled by the dev run.
- [x] Search panel: layer-shell overlay with focused entry, Escape, and a
      placeholder result row. CLI `--toggle-search` and the labwc shortcut both
      open it.
- [x] Shortcut installer: labwc `W-Space`, marked block, `labwc --reconfigure`.
      KDE/GNOME/X11 paths move to L7.
- [x] GNOME dashboard limitation documented; no GNOME machine was available.
- [x] Manual smoke on Pi OS labwc; the other DE matrix moves to L7.

### Acceptance

- Pi OS labwc: a placeholder widget is created through the layer-shell
  backend; search and settings open through the socket and the installed
  Shortcut. The tray icon registers with `wf-panel-pi`.
- KDE, GNOME, wlroots and X11 are explicitly L7; the normal-window fallback is
  not claimed as tested.
- The GUI survived the smoke run; a long 30-minute idle run is part of L8.

---

## L3 — System widgets (done 2026-11-19, Pi vertical slice)

**Goal:** LiveBox, NetBox and DevBox with real Linux/Pi data.

### Tasks

- [x] CPU: `/proc/stat`, per-core, thresholds, history.
- [x] Memory: `/proc/meminfo`.
- [x] Disk: `statvfs`, per-volume list, thresholds.
- [x] Processes: `/proc` top CPU/MEM, refresh interval, process count.
- [x] Network: `/proc/net/dev` or netlink, per-interface rates, picker,
      packet/error counters, thresholds.
- [x] Docker: `docker ps`/`stats` or the Engine API; hide when absent.
      (`docker ps` status only; no stats.)
- [ ] GPU row: AMD sysfs, NVIDIA `nvidia-smi`, Intel fdinfo; hide when no
      backend; never fabricate 0%. AMD/NVIDIA are coded but unverified; Intel
      fdinfo is not implemented. The row hides correctly on the Pi.
- [x] Chart component: Cairo/DrawingArea, same visual language as the macOS
      chart; no Swift Charts.
- [x] Widget faces: LiveBox small/medium/large, NetBox, DevBox; placement and
      size presets.
- [x] Tests for every parser and threshold table.
- [x] Pi 4/5 measurements: idle CPU, widget refresh cost, memory. (Pi 4 only;
      Pi 5 not available.)

### Acceptance

- All three widgets render real data at all sizes on Pi OS; a desktop is the
  L7 matrix because no desktop machine is available.
- CPU/mem/disk values match `top`/`free`/`df` within a sensible tolerance.
- Thresholds turn amber/red at the configured values.
- No sustained CPU load from the widgets on a Pi 4 at the default cadence:
  0.82% of one core and 111 MB RSS over 60s in the debug build.

See [`l3.md`](l3.md) for evidence, measurements and the deferred GPU/desktop
checks.

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
- [ ] labwc shortcut installer (Trixie) and panel/tray path; Wayfire installer only if Bookworm is supported later.
- [ ] Secret Service fallback warning on first run if no keyring is present.
- [ ] Pi 4 and Pi 5 smoke: install, first run, widgets, settings, search,
      credentials, updates, uninstall.
- [ ] Measure idle CPU, memory, startup time and widget refresh cost.
- [ ] Install docs: Pi OS version, apt command, keybinding, known limits.
- [ ] Release artifact + SHA256; no macOS release changes.

### Acceptance

- Fresh Pi OS Trixie labwc, `apt install ./deck.deb`, launch, add widgets,
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

1. Pi OS Trixie labwc on Pi 4B (Pi 5 not available): `.deb` install, 13 widgets, settings,
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
