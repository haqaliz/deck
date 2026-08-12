# LiveBox per-core CPU — PRD

## Ask

Add thin **per-core CPU lines** to the LiveBox chart so a glance shows core
saturation (E-core vs P-core, multi-core contention) under the prominent total
CPU line. Slug: `livebox-per-core-cpu`.

Source: `deck-next` handoff → `docs/planning/_card/issue.md` (ROADMAP.md:59
backlog item "Per-core CPU lines or per-core selection").

## User-visible spec

### Front face (widget, self-sampled)

No new widget size, no new section — the medium/large chart gains per-core
lines when the toggle is on and `showChart` is on:

1. **Chart** — the existing CPU/MEM/DISK lines stay exactly as-is; the total
   CPU line remains the prominent one (1.5pt, full opacity, `cpuColor`). Below
   it, up to 8 thin per-core lines (1.0pt, `cpuColor` at ~0.4 opacity,
   `catmullRom`). `showCPU` off → per-core lines also hidden.
2. **Core cap** — render `min(coreCount, 8)` cores, fixed first-N by index.
   No re-selection per tick, so the set of drawn lines never churns.
3. **Small widget** — unchanged (no chart).
4. **Backward compatibility** — history written before this build (no per-core
   data) renders exactly as today; per-core lines appear from the next sample
   onward.

### Back face (settings — Deck app tab, not in widget)

- **Chart section**: `Toggle("Per-core CPU lines", isOn: $settings.showPerCoreCores)`
  default **on**, disabled when `showChart` is off. No new control types.
- No color picker for per-core (reuses `cpuColor`), no count stepper (fixed
  cap of 8).

## Data source

Pure extension of the existing sandbox-safe path — **no agent, no snapshot, no
container changes**:

1. **Sampling**: `CpuTicks.sample()` (SystemMetrics.swift:14-42) already calls
   `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` which returns per-processor
   ticks; the loop at lines 33-39 sums them. Change the function to also return
   the per-processor array (`[CpuTicks]`, one per CPU), keeping the aggregated
   total for the existing API.
2. **Pure delta function**: `perCoreUsagePercents(previous: [CpuTicks],
   current: [CpuTicks]) -> [Double]` — per-core equivalent of
   `cpuUsagePercent` (SystemMetrics.swift:46-53): `(deltaTotal - deltaIdle) /
   deltaTotal * 100` per core, 0 when `deltaTotal == 0`. Counts mismatch
   (core count changed between ticks — VM migration) → zip-safe: compute on
   the shared prefix, drop the rest.
3. **Draw order**: per-core `LineMark`s render **before** the total
   CPU/MEM/DISK marks so the 1.5pt prominent lines stay visually on top.
   Applies only when `showCPU` and `showPerCoreCores` are both on.
4. **History**: `Sample` (LiveBoxWidget.swift:11-15) gains
   `perCore: [Double]?` (Codable, optional → old `history.json` decodes,
   `nil` renders no per-core lines). Appended per tick, capped with the same
   `HistoryStore.capacity` (60).
5. **Failure behavior**: any sampling failure already degrades to a zeroed
   `CpuTicks`; per-core line list empty → chart falls back to today's look.
   No new empty state needed (mach never partially fails in practice).

## Shell fit

- Touches only: `native/DeckWidgets/Loaders/SystemMetrics.swift` (per-core
  exposure), `native/DeckWidgets/LiveBoxWidget.swift` (Sample, sampler,
  chart), `native/Shared/DeckSettings.swift` (one toggle),
  `native/DeckApp/DeckApp.swift` (one toggle row in the LiveBox tab).
- The chart already renders multi-series `LineMark`s (LiveBoxWidget.swift:
  340-379) — per-core lines add N more series; the Charts view shape is
  unchanged.
- **Settings decode hardening (required)**: `DeckSettings.load()` falls back
  to all-defaults when decoding throws (DeckSettings.swift:61-64), and Swift's
  synthesized `Decodable` throws when a new non-optional key is missing — so a
  plain `var showPerCoreCores = true` would wipe **every** setting (colors,
  token, repo paths) on first launch after update. Fix: custom
  `init(from:)` on `LiveBoxSettings` using `decodeIfPresent` with defaults
  (~12 lines, local to the struct). Same latent risk exists for the `devbox`
  key added in 48e386a — out of scope, flagged at review gate.
- **No other shell invariant is touched**: same widget file, same sandbox-safe
  self-sampled path, same 60s cadence.
- **TDD**: the per-core percent function is pure → developed in a scratch
  SwiftPM package (`Sources/LiveBoxCore` + `Tests/LiveBoxCoreTests`,
  `swift test`) — the BatBox/GitBox/DevBox precedent (devbox/prd.md:88-92) —
  then ported into `SystemMetrics.swift` (or a small adjacent file) and the
  scratch package removed before merge.

## Non-goals

- No per-core selection/highlighting, no E/P-core grouping or core labels, no
  top-N-by-usage re-selection (churn).
- No per-core history chart or drill-down; no per-core MEM/DISK.
- No GPU/ANE usage (no public Apple Silicon API — ROADMAP.md:60 stays open).
- No changes to small widget, process list, or threshold coloring.

## Decisions (resolved in interview)

- Toggle **default on** — the feature is the point; low opacity prevents a
  visual regression when re-adding from the gallery.
- Cap **fixed first 8** cores (`min(coreCount, 8)`) — stable set, no churn.
- Styling: per-core lines in `cpuColor` at ~0.4 opacity, 1.0pt — reads as
  "cores inside CPU", total CPU line stays prominent.
- Per-core history stored in `Sample.perCore` (optional) — old history.json
  decodes unchanged.
