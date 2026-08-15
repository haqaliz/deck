# PRD: LiveBox threshold coloring

- Slug: `livebox-threshold-coloring`
- Type: `feat` (follow-on slice of LiveBox)
- Source: `docs/planning/_card/issue.md` (deck-next handoff, 2026-08-15)
- Status: drafted (deck-prd interview, 2026-08-15)

## 1. Restated ask

LiveBox metric rows (CPU/MEM/DISK) and the per-core CPU chart lines turn
amber/red when a value crosses configurable thresholds (defaults warn 80% /
alarm 90%), so the widget stays readable at a glance from across the room.
Pure layout/color work: no agent, no loader, no snapshot changes.

## 2. User-visible spec

### Front face (widget)

- **Metric rows** (all three sizes): when a metric's current value ≥ warn,
  the row's **value text** turns amber; ≥ alarm, it turns red. The colored dot
  keeps the user's metric color. Normal → current behavior.
- **Chart** (medium/large, when `showChart`):
  - CPU/MEM/DISK lines: colored by the metric's **current** value tier
    (amber/red instead of the user color while alarmed; normal → user color).
  - Per-core CPU lines: each core line colored by **its own** current value
    tier (only when `showPerCoreCores` is on). Same warn/alarm colors.
- A value counts as **alarm** whenever it is ≥ alarm, regardless of warn
  (tier precedence: alarm wins if warn > alarm).

### Back face (Deck app, LiveBox tab)

New "Thresholds" section under Metrics:

| Control | Default | Behavior |
|---|---|---|
| Toggle "Show threshold colors" | On | Master switch for all threshold coloring |
| Stepper "Warn at: 80%" | 80 | 0...100, applied to CPU/MEM/DISK |
| Stepper "Alarm at: 90%" | 90 | 0...100, applied to CPU/MEM/DISK |

Toggles pinned right; steppers follow the existing `Stepper("Process count: …")`
pattern (DeckApp.swift:326). No other back-face changes.

## 3. Data source

- **Source**: values already sampled in-process by `LiveBoxSampler.sample()`
  (LiveBoxWidget.swift:61-99) — mach `CpuTicks`, `memoryUsagePercent()`,
  `diskUsagePercent()`. No new source.
- **Cadence**: 5s render ticks via `TimelineView` (unchanged).
- **Unavailable**: unchanged — history empty → no chart; thresholds only color
  what is already rendered. No new empty states.

## 4. Shell fit

- Reuses the LiveBox widget shell wholesale; only `LiveBoxFace` view colors and
  `LiveBoxSettings` + its decode change.
- New shared helper `native/Shared/LiveBoxCore.swift` (Foundation-only, same
  shape as `OpenBoxCore.swift`): `enum ThresholdTier { normal, warn, alarm }`,
  pure `tier(value:warn:alarm:)`, plus standard warn/alarm colors so NetBox
  threshold coloring (ROADMAP.md:81) reuses the same language.
- Settings follow the tolerant-decode pattern (DeckSettings.swift:97-109) —
  old `settings.json` files must keep loading.
- No shell invariants touched (material card, dynamic height, corner mask,
  settings persistence, agent).

## 5. Non-goals

- No per-metric threshold pairs (follow-on if asked).
- No threshold coloring for top-process rows or their percents.
- No GPU/ANE/thermal work (ROADMAP.md:67) — separate feasibility.
- No NetBox wiring in this slice (the helper ships now, NetBox later).
- No per-point chart coloring of history — series colored by current value
  (a 1.5px line can't carry per-point meaning).

## 6. Open questions

Resolved in interview (2026-08-15):
- Shared threshold pair (not per-metric). — agreed
- Value text + chart line recolor; dot keeps user color. — agreed
- Each per-core line by its own value. — agreed
- On by default + settings toggle. — agreed

Remaining: none blocking; warn > alarm edge is defined (alarm wins) and will be
covered by a unit test.

## Checklist

- Front face at a glance: values flip amber/red on load — no new elements. ✓
- Back face settings: toggle + 2 steppers with sane defaults (80/90). ✓
- Data source exists and is local-first: in-process mach, already shipped. ✓
- Cadence: follows the 5s tick; no new refresh path. ✓
- Shell reuse, zero panel-invariant risk. ✓
