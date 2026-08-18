# livebox-process-cadence — understanding note

## What the work is really asking

LiveBox's top-process rows can be up to ~90s stale while the widget presents
itself as a live monitor. The deck-next brief: sample the process snapshot at a
tighter interval (agent change, negligible CPU) and have LiveBox re-read it on
its live tick, with an optional interval setting (tolerant decode) + tests.

## Facts from the dig

1. **Widget side** (`DeckWidgets/LiveBoxWidget.swift`):
   - `TimelineView(.periodic(from: .now, by: 60))` (L194) — the chart tick is
     60s, not the "5s ticks" the L50 comment claims (comment is stale; `by: 60`
     came in f724424 "native-only Deck"). TimelineView ticks are NOT throttled
     by WidgetKit (L50-51 comment) — this is LiveBox's live trick.
   - Each tick re-samples mach and re-reads `processes.json` via
     `LiveBoxSampler.processes(mode:)` (L80-88) with a **90s freshness guard**
     on `writtenAt`.
   - `HistoryStore.capacity = 60` samples → 60 min window at 60s ticks; a
     faster tick shrinks the window unless capacity scales (240 @ 15s = 60 min).
   - `Sample.perCore` feeds the chart from `perCoreUsagePercents`.

2. **Agent side** (`DeckAgent/main.swift`, `DeckApp/DeckApp.swift`):
   - LaunchAgent `com.deck.agent` plist `StartInterval` is hardcoded 60
     (`agentInterval`, DeckApp.swift:185-187; plist L195-216).
   - The app also pumps all snapshots on a hardcoded 60s timer while open
     (DeckApp.swift:60). Both write `processes.json` via
     `HostProcessSampler.top(limit: 10)` (`/bin/ps`, ~ms — cheap).
   - `ProcessSnapshotStore` (`Shared/ProcessSnapshot.swift`) writes into the
     widget container; only saved when changed (writtenAt is fresh each tick so
     effectively every tick).

3. **Dead code found (flag, out of scope):** `OpenBoxSettings.refreshInterval`
   (DeckSettings.swift:124, 147) has a 5...60 stepper (DeckApp.swift:361) but
   **nothing consumes it** — neither the app timer nor the agent plist. A user
   setting it expects a cadence change and gets none. Per CLAUDE.md's
   cross-page consistency rule, this is a follow-up bug (or part of this
   feature if the interval setting is generalized).

4. **Deferred test slice (rides along):** `SystemMetrics.swift`
   (`DeckWidgets/Loaders/`, not compiled into DeckSharedTests) holds the pure
   per-core math `perCoreUsagePercents` / `cpuUsagePercent(previous:current:)`
   / `CpuTicks` (L77-101) that ROADMAP.md:58 lists as the last deferred test
   item ("needs the per-core math moved to Shared first"). Precedent:
   `Shared/LiveBoxDiskCore.swift`, `Shared/NetBoxCore.swift`. The mach
   `sampleAll()`/`sample()` (Darwin calls) stays in the widget target.

5. **Test command** (CI, `.github/workflows/deck.yml:59`):
   `xcodebuild test -project native/Deck.xcodeproj -scheme DeckSharedTests
   -derivedDataPath native/build CODE_SIGNING_ALLOWED=NO`.

## Design space (open questions for the interview)

- **Widget tick**: drop to the process interval (e.g. 15s) so rows + chart both
  feel live, and scale `HistoryStore.capacity` to keep a 60-min window
  (capacity = 3600 / interval). Floor at 5s (CPU/draw burn).
- **Agent**: a second LaunchAgent `com.deck.agent.processes` running
  `DeckAgent --processes` (new mode: only the ps snapshot, then exit) at the
  interval — heavy snapshots (git, weather, shipbox, opencode DB) stay at 60s.
  App rewrites both plists on interval change (bootout+bootstrap to apply a new
  StartInterval).
- **Freshness guard**: currently 90s; should scale with the interval
  (e.g. max(3×interval, 60)) so a dead fast-agent is still detected.
- **Setting**: `LiveBoxSettings.processRefreshInterval` (Int, tolerant decode),
  stepper in the LiveBox tab next to "Show top processes".

## Affected files

- `Shared/SystemMetricsCore.swift` (new, pure math moved) + `DeckWidgets/Loaders/SystemMetrics.swift` (reuse)
- `Shared/ProcessSnapshot.swift` (guard logic if generalized)
- `Shared/DeckSettings.swift` (LiveBoxSettings.processRefreshInterval + decode)
- `DeckApp/DeckApp.swift` (LiveBox stepper, second LaunchAgent install/rewrite)
- `DeckAgent/main.swift` (`--processes` mode)
- `DeckWidgets/LiveBoxWidget.swift` (tick interval, guard, history capacity)
- `SharedTests/SystemMetricsCoreTests.swift` (new) + DecodeTests additions
- `README.md`, `ROADMAP.md` (register; close M4 deferred line)

## Ambiguities / risks

- The stale "5s ticks" comment: the code already ticks at 60s — the feature
  must decide the target tick explicitly (recommend the interval setting, not
  hardcoded 5s).
- WidgetKit may floor aggressive TimelineView rates on macOS; the gain is
  fresher data per render, not fighting the floor (CLAUDE.md).
- Second LaunchAgent duplicates install/uninstall + bootstrapping; keep it
  driven by the same `agentAtLogin` toggle and remove it when the primary is
  removed (uninstall path in README).
