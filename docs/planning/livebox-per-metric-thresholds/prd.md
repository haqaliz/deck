# PRD: LiveBox per-metric threshold pairs

- Slug: `livebox-per-metric-thresholds`
- Type: `feat` (follow-on slice of LiveBox)
- Source: `docs/planning/_card/issue.md` (deck-next handoff, 2026-08-19)
- Status: drafted (deck-prd interview, 2026-08-19)

## 1. Restated ask

Split LiveBox's single shared warn/alarm threshold pair into **per-metric
pairs** — CPU, MEM, DISK each get their own warn/alarm thresholds — so a busy
CPU or a full disk can alarm independently. Recorded follow-on:
`docs/planning/livebox-threshold-coloring/prd.md:67` ("No per-metric threshold
pairs (follow-on if asked)"). Pure settings + view-color work: no agent, no
snapshot, no loader, no timeline change.

## 2. User-visible spec

### Front face (widget, all three sizes)

- **Metric rows** (CPU / MEM / DISK): the value text turns amber/red per that
  **metric's own** pair. The colored dot keeps the user's color. Normal →
  current behavior.
- **Chart lines** (medium/large): each line colored by the tier of that
  **metric's own** pair and its current value. Per-core CPU lines use the
  **CPU** pair (they are CPU values), each core still judged by its own value.
- **Per-volume disk rows** (large): **untinted** — thresholds are the aggregate
  DISK row's story (`docs/planning/livebox-disk-per-volume/prd.md:88`).
- A value counts as **alarm** whenever it is ≥ its alarm threshold, regardless
  of warn (tier precedence: alarm wins if warn > alarm — unchanged
  `ThresholdTier` rule).

### Back face (Deck app → LiveBox tab → "Thresholds" section)

| Control | Default | Behavior |
|---|---|---|
| Toggle "Show threshold colors" | On | Master switch for all threshold coloring (unchanged) |
| CPU row: Stepper "Warn at: 80%" / "Alarm at: 90%" | 80 / 90 | 0...100, CPU pair |
| MEM row: Stepper "Warn at: 80%" / "Alarm at: 90%" | 80 / 90 | 0...100, MEM pair |
| DISK row: Stepper "Warn at: 80%" / "Alarm at: 90%" | 80 / 90 | 0...100, DISK pair |

Three labeled rows (CPU / MEM / DISK), each with two steppers, following the
existing `Stepper("Warn at: …%")` pattern (DeckApp.swift:351-354). All steppers
disabled while the master toggle is off. Caption text unchanged.

## 3. Data source

- **Source**: values already sampled in-process by `LiveBoxSampler.sample()`
  (LiveBoxWidget.swift:61-99) — mach `CpuTicks`, `memoryUsagePercent()`,
  `diskUsagePercent()`. No new source.
- **Cadence**: 5s render ticks via `TimelineView` (unchanged).
- **Unavailable**: unchanged — history empty → no chart; thresholds only color
  what is already rendered. No new empty states.

## 4. Shell fit

- Reuses the LiveBox widget shell wholesale; only `LiveBoxFace` tier application,
  `LiveBoxSettings` + decode, and the settings view change.
- **Settings migration** (settled in interview): six new keys —
  `cpuWarnThreshold`, `cpuAlarmThreshold`, `memWarnThreshold`, `memAlarmThreshold`,
  `diskWarnThreshold`, `diskAlarmThreshold`. Tolerant decode per key with a
  **fallback chain: per-metric key → legacy `warnThreshold`/`alarmThreshold` →
  default 80/90**, so existing customizations survive one-time (settings-schema
  migration precedent, ROADMAP.md:56).
  **Legacy keys are decode-only**: they are read straight from the decode
  container, never stored as properties, so the synthesized encoder writes only
  the six per-metric keys (one-way migration; the app and widget extension always
  ship version-matched, so a downgrade to an older app is the only path back to
  80/90).
- New pure resolver in Shared (testable in DeckSharedTests): a `Metric` enum
  (cpu/mem/disk) + `tier(metric:value:settings:)` returning the tier for that
  metric's pair — mirrors the `NetBoxThresholdTier` wrapper shape
  (NetBoxCore.swift:85-92). Lives in `Shared/LiveBoxCore.swift`.
- No shell invariants touched: material card, dynamic height, corner mask,
  settings persistence, agent, refresh cadences all unchanged.

## 5. Non-goals

- No per-direction or per-unit pairs — NetBox keeps its single pair by design
  (`docs/planning/netbox-threshold-coloring/prd.md:74`); this feature is
  LiveBox-only.
- No threshold coloring for top-process rows or their percents (unchanged).
- No per-volume disk tinting (see §2).
- No GPU/ANE/thermal work (blocker-deferred: no public Apple Silicon API —
  `docs/planning/livebox-per-core-cpu/prd.md:94`).
- No changes to `ThresholdTier` itself or the no-reading/zero-floor guard NetBox
  added.
- No widget-side settings UI (settings live in the Deck app only).

## 6. Open questions

Resolved in interview (2026-08-19):
- Migration: inherit the legacy pair when per-metric keys are absent. — agreed
- Defaults: 80/90 for all three metrics. — agreed
- UI: per-metric stepper groups (CPU / MEM / DISK rows). — agreed

Remaining: none blocking; warn > alarm edge is defined (alarm wins) and covered
by an existing unit test (`ThresholdTierTests.swift:28`).

## Checklist

- Front face at a glance: each metric flips amber/red by its own pair. ✓
- Back face: master toggle + three per-metric stepper groups (80/90). ✓
- Data source exists and is local-first: in-process mach, already shipped. ✓
- Cadence: follows the 5s tick; no new refresh path. ✓
- Migration: old settings.json keeps loading; custom thresholds inherited. ✓
- Shell reuse, zero panel-invariant risk. ✓