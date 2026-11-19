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

## L4 — Network widgets (Pi vertical slice done 2026-11-19)

**Goal:** the eight API widgets, with account management and fixture-tested
parsers.

### Tasks

- [x] Credentials UI: single-account rows for GitHub, Azure DevOps and
      opencode with save/delete/verify and the keychain/file fallback.
- [ ] Elastic and Grafana accounts: deferred to L5 with their widgets.
- [x] WeatherBox: wttr.in, units, forecast.
- [x] ClockBox: world clocks, main city, offsets.
- [x] GitBox: repo scan, commits/day, streak, top repos.
- [x] OpenBox: local SQLite, models/tools/sessions.
- [ ] OpenBox remote server mode: deferred.
- [x] ShipBox: GitHub Actions, static list, multi-repo merge.
- [ ] ShipBox automatic repo discovery: deferred.
- [x] TaskBox: Azure DevOps work items, WIQL, organization/project.
- [x] PRBox: GitHub + Azure DevOps review queue.
- [ ] PRBox per-provider toggles and review-state glyphs: deferred.
- [x] MarketBox: crypto/fiat/gold/stocks, display currency.
- [ ] MarketBox live picker policy: deferred; symbols are a settings list.
- [x] Fetch statuses, retry/stale behavior, offline/empty/error copy.
- [x] Deep links through GTK's URI handler (`xdg-open` on Linux).
- [x] Copy/port the macOS fixtures and add parser tests; Weather, Open, Ship,
      Task and PR use new fixtures where macOS had none.
- [x] Widget faces and settings tabs for all eight.

### Acceptance

- Weather, Market, Git and Open render live/local data on the Pi. Ship, Task
  and PR are fixture-verified; no GitHub token or Azure PAT was available.
- A failed provider shows its own reason and never blanks the others.
- All three sizes and the settings hub work; small/medium/large screenshots
  are in [`l4.md`](l4.md).
- Parser tests cover success and malformed payloads; the auth-failure branch is
  exercised by the status mapping, not by a live token.

See [`l4.md`](l4.md) for the evidence and the deferred account/discovery work.

---

## L5 — LogBox, MetricBox, search providers (done 2026-11-19, Pi vertical slice)

**Goal:** the two infra widgets plus the full v1 search experience.

### Tasks

- [x] LogBox: Elastic counts/trend/templates/recent lines, environment/service
      catalog loader, templates/latest/full modes and a Kibana link.
- [x] MetricBox: Grafana datasource discovery, fleet/host/power/agents/alerts,
      configurable columns, host list from the snapshot and a Grafana link.
- [x] Charts for counts/trend in Cairo; MarketBox sparklines.
- [x] Search providers for all 13 v1 widgets:
      - local: system, network, dev, clock, git, open sessions
      - snapshot-backed: work items, PRs, markets, logs, metrics, weather,
        ship runs
- [x] Prefixes and macOS-style ordering; 180ms debounce.
- [ ] Per-source floor, remote search cache and 429 isolation: deferred because
      search is local-only and makes no network calls.
- [x] Search panel results: grouped sections, Up/Down, Enter/click opens the
      URL or copies the result.
- [x] Rate-budget rule: searches run in the GUI on user input, never in `deckd`.
- [x] Tests for prefix parsing, work-item kinds, ordering/limits and degraded
      sections; cache is not applicable to the local-only slice.

### Acceptance

- LogBox/MetricBox faces and parsers are verified with seeded snapshots and
  fixtures; a real cluster was not available, so live credentials and the
  Verify buttons remain untested.
- Kibana/Grafana links point at the configured base URL; query-specific deep
  links are deferred.
- Search returns at least one result for every ported provider in tests and
  screenshots, and a missing snapshot simply removes its section.
- No search request runs on the background tick; there are no search-time
  network requests at all.

See [`l5.md`](l5.md) for evidence and the deferred live-infra checks.

---

## L6 — Pi OS packaging + Pi v1 release (done 2026-11-20, Pi 4)

**Goal:** a clean Pi OS install from the `.deb` that feels finished.

### Tasks

- [x] arm64 `.deb`: dependencies, icons, desktop entries, systemd user unit,
      autostart, uninstall rules.
- [x] labwc shortcut installer/removal (Trixie) and panel/tray path.
- [x] Secret Service fallback warning in the General tab when no keyring is
      present.
- [x] Pi 4 smoke: install, first run, widgets, settings, search, deckd,
      shortcut removal and uninstall/reinstall.
- [ ] Pi 5 smoke: no hardware.
- [x] Measure idle CPU, memory, startup time and widget refresh cost.
- [x] Install docs: Pi OS version, apt command, keybinding, known limits.
- [x] Release artifact + SHA256 in `dist/`; publication waits for L8.

### Acceptance

- Fresh Pi OS Trixie labwc: `dpkg -i`, launch, widgets, search, settings,
  `deckd --once`, uninstall and reinstall verified. The Secret Service path
  remains unexercised because the Pi has no keyring.
- No secret in a snapshot or log; `.deb` dependencies resolve from Pi OS.
- Pi 4 idle overhead: 0.53% CPU and 119 MB RSS over 60s in the release build.
- Pi 5 is documented as untested.

See [`l6.md`](l6.md) for the package details and measurements.

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
