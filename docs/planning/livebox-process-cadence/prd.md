# PRD: livebox-process-cadence

**Slug:** `livebox-process-cadence` (branch `feat/livebox-process-cadence/aliz`)
**Source:** inline brief (deck-next handoff) — `docs/planning/_card/issue.md`
**Date:** 2026-08-18

## 1. Restate the ask

Make LiveBox's top-process rows track reality at a user-chosen tighter cadence
(default 15s, down from up to ~90s of staleness today) by sampling the
`processes.json` snapshot faster (dedicated agent path) and re-reading it on a
faster widget tick — without touching the other widgets' 60s cadence and
without fighting the WidgetKit timeline floor. The deferred per-core CPU math
tests (ROADMAP.md:58) ride along since they touch the same files.

## 2. User-visible spec

Front face (LiveBox widget, all sizes — **no visual change** to layout):
- Chart + CPU/MEM/DISK rows + top-process rows refresh at the configured
  interval instead of 60s. The chart keeps a ~60-minute rolling window.
- Nothing else changes: per-core lines, per-volume disk, thresholds, process
  tabs, colors, counts all behave as today.

Back face (LiveBox tab in the Deck app):
- New stepper **"Process refresh: 15 s"** — range 5...60, step 5, default 15,
  placed under "Show top processes" (DeckApp.swift:342-344).
- Tolerant decode: `LiveBoxSettings.processRefreshInterval` (`Int`, default 15,
  `decodeIfPresent ?? 15`) — missing key never wipes other settings.

## 3. Data source & cadence

- **Fast path (new):** LaunchAgent `com.deck.agent.processes` runs
  `DeckAgent --processes` every `processRefreshInterval` seconds — samples
  `/bin/ps` (`HostProcessSampler.top(limit: 10)`, ~ms) and rewrites
  `processes.json` in the widget container, then exits.
- **Slow path (unchanged):** the existing 60s agent + app timer keep sampling
  everything else (opencode DB, git log, weather, ShipBox, DevBox, clipboard)
  and still write `processes.json` — the two writers are idempotent (last-wins,
  same shape, both cheap).
- **Widget:** `TimelineView(.periodic(from: .now, by: interval))` — tick drives
  the mach sampling, history append, and a fresh `processes.json` read per
  render. TimelineView ticks are not throttled by WidgetKit (LiveBoxWidget.swift:50-51).
- **Unavailable source:** freshness guard on `writtenAt` becomes
  `max(2 × interval, 30)` — a dead fast agent hides the rows within ~30s at the
  default. Implemented as a pure helper in `Shared/ProcessSnapshot.swift`
  (`ProcessSnapshot.maxAgeSeconds(for:)`) so DeckSharedTests can cover it.
  WidgetKit may still floor aggressive ticks on macOS; the gain is fresher data
  per render, not more renders (CLAUDE.md — do not fight it).
- **Dual writers are deliberate:** the 60s agent/app timer keep writing
  `processes.json` too. If only the slow writer is alive, rows update once a
  minute and stay under the guard — the guard is evaluated per-read, so this is
  honest staleness, not a flicker bug.
- **History:** `HistoryStore.capacity = min(3600 / interval, 240)` keeps the
  ~60-min chart window at 15s (240 samples) and caps draw cost at fast
  intervals (at 5s the window shrinks to 20 min — accepted).

## 4. Shell fit

Reuses the whole proven LiveBox shell; no new widget, no panel invariant
touched (card, flip, settings window, container, signing all unchanged).

- `Shared/SystemMetricsCore.swift` (new): pure per-core math moved from
  `DeckWidgets/Loaders/SystemMetrics.swift` — `CpuTicks` struct, `total`,
  `perCoreUsagePercents`, `cpuUsagePercent(previous:current:)`. The mach
  samplers (`sample()`, `sampleAll()`, `memoryUsagePercent`, `diskUsagePercent`,
  `diskVolumeSamples`) stay in the widget target (Darwin calls). Precedent:
  `Shared/LiveBoxDiskCore.swift`, `Shared/NetBoxCore.swift`.
- `DeckWidgets/Loaders/SystemMetrics.swift` reuses the moved core.
- Agent: `DeckAgent/main.swift` gains a `--processes` mode (only the ps
  snapshot, then exit); `DeckApp` installs the second plist
  (`com.deck.agent.processes.plist`) with `StartInterval = processRefreshInterval`,
  bootout+bootstrap on interval change, removed alongside the primary agent via
  the existing `agentAtLogin` toggle. README uninstall section updated.
- Widget entry already carries `LiveBoxSettings` — the tick interval and guard
  come from it; the app's `onChange` reload path (settings → save → applyAgent →
  reloadAllTimelines) already propagates changes.

## 5. Non-goals

- No change to other widgets' cadence (weather/ShipBox HTTP stays at 60s).
- No separate process-only timer inside the widget (one tick drives chart +
  rows; decoupling is a non-goal).
- No process-history or per-process details beyond the existing rows.
- No changes to the process tabs, counts, or list layout.
- No fix for the dead `OpenBoxSettings.refreshInterval` stepper
  (DeckApp.swift:361 — nothing consumes it): flagged as a follow-up bug, out
  of scope (it drives no code path today).
- No GPU/ANE/thermal (documented blocker: no public Apple Silicon API —
  docs/planning/livebox-per-core-cpu/prd.md:94).

## 6. In-scope ride-along

Deferred per-core math tests (ROADMAP.md:58): the move in §4 makes
`perCoreUsagePercents` / `cpuUsagePercent` / `CpuTicks.total` testable in
`DeckSharedTests` — new `SharedTests/SystemMetricsCoreTests.swift` (zero-delta,
no-delta, mixed-core zips, regression on known tick pairs). This closes the
last deferred M4 test line.

## 7. Verification

- `xcodebuild test -project native/Deck.xcodeproj -scheme DeckSharedTests
  -derivedDataPath native/build CODE_SIGNING_ALLOWED=NO` — new core tests +
  `maxAgeSeconds` guard tests + DecodeTests for `processRefreshInterval`
  (missing key → 15; explicit → value; other keys untouched).
- `xcodebuild ... build` clean; install; re-add LiveBox from the gallery;
  verify small/medium/large unchanged.
- Live: set interval 5s, watch process rows track `top`-equivalent churn;
  `launchctl bootout gui/$(getuid)/com.deck.agent.processes` → rows disappear
  within ~30s (guard); re-open app → agent reinstalled.
- Register in README.md and ROADMAP.md (M4 item `[x]`; deferred line closed).
