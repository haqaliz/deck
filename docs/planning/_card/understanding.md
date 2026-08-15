# Understanding: livebox-threshold-coloring

## What the work is really asking

LiveBox metric rows (CPU/MEM/DISK) and the per-core CPU chart lines should turn
amber/red when a value crosses configurable thresholds (defaults warn 80% /
alarm 90%). This is the deck-next pick for the roadmap item "Threshold coloring
(e.g. red when CPU > 90%)" (ROADMAP.md:69). It must be **pure layout/color**:
LiveBox already samples mach in-process (LiveBoxWidget.swift:61-99), so there is
no agent, no loader, and no snapshot change. The threshold rules must live in a
**shared, testable helper** (OpenBoxCore.swift precedent) so NetBox threshold
coloring (ROADMAP.md:81) can reuse them later.

## Code map

- `native/DeckWidgets/LiveBoxWidget.swift`:
  - `LiveBoxFace` (line 208) — renders 3 sizes; metric rows via `metricRow`
    (line 409: colored dot + secondary title + primary value text).
  - `chart` (line 352) — per-core lines (354-368, `cpuColor.opacity(0.4)`),
    CPU/MEM/DISK lines (370-401, user colors). Current value is live; the chart
    plots the 60-sample history.
  - Process rows (330-345) color percents with the metric colors — brief says
    nothing about processes; default out of scope.
- `native/Shared/DeckSettings.swift` — `LiveBoxSettings` (line 79) with the
  tolerant-decode `init(from:)` pattern (97-109). New keys must follow it.
- `native/DeckApp/DeckApp.swift` — `LiveBoxSettingsView` (line 303): Form with
  Chart/Metrics/Processes sections; Stepper pattern (line 326) to copy.
- `native/Shared/OpenBoxCore.swift` — the shared pure-logic precedent (Foundation
  only, extracted so DeckSharedTests can compile it).
- `native/SharedTests/` — XCTest suites; `DecodeTests.swift:143` covers
  `LiveBoxSettings` tolerant decode; new suite file for the tier logic.

## Design sketch

- New `Shared/LiveBoxCore.swift`: `enum ThresholdTier { normal, warn, alarm }`,
  pure `tier(value:warn:alarm:)` (alarm wins over warn), plus standard warn
  (amber) / alarm (red) colors so NetBox reuses the same language.
- `LiveBoxSettings`: `showThresholdColors = true`, `warnThreshold = 80`,
  `alarmThreshold = 90`, tolerant decode.
- `LiveBoxFace`: row dot + value text + the metric's chart line switch to the
  tier color when the **current** value crosses; per-core lines too (series
  colored by latest value's tier — per-point coloring in Swift Charts is not
  worth it for a 1.5px line).

## Ambiguities for the interview

1. One shared threshold pair for all three metrics, or per-metric? (Brief reads
   shared; per-metric = 6 settings, follow-on slice.)
2. Recolor the row **dot** too, or only the value text? (Dot is the user's
   metric color identity — keep it, recolor value text + chart line.)
3. Per-core lines: all recolor when the aggregate CPU alarms, or each core by
   its own value? (Own value is the honest reading of "per-core CPU lines".)
4. Default ON or a toggle defaulting OFF? (Feature-by-default matches the
   brief; a toggle still gives an escape hatch.)
5. What if user sets warn > alarm? (Tier precedence: alarm wins. No clamping
   gymnastics.)
6. Processes stay out of scope for this slice.

## No shell invariants broken

No card/flip/settings-window/agent behavior changes; the only production edits
are one Shared helper + three setting keys + view colors. Same data path.
