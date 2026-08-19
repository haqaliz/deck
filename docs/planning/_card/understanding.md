# Understanding: livebox-per-metric-thresholds

## What the work is really asking

Split LiveBox's single shared warn/alarm threshold pair into **per-metric
pairs** (CPU / MEM / DISK), so a busy CPU or a full disk can alarm independently
instead of sharing one pair. This is the recorded follow-on from
`docs/planning/livebox-threshold-coloring/prd.md:67` ("No per-metric threshold
pairs (follow-on if asked)"). Pure settings + view-color work: no agent, no
snapshot, no loader, no timeline change (path 1, self-sampled, in CLAUDE.md).

## Current state (what shipped)

- `LiveBoxSettings` (Shared/DeckSettings.swift:75-117): one pair
  `warnThreshold=80` / `alarmThreshold=90` + master `showThresholdColors=true`,
  tolerant-decode init (missing keys → defaults, so old settings.json keeps
  loading).
- `ThresholdTier` (Shared/LiveBoxCore.swift:10-26): pure `tier(value:warn:alarm:)`
  (alarm wins over warn when warn > alarm) + shared warn/alarm colors. Covered by
  `SharedTests/ThresholdTierTests.swift`.
- `LiveBoxFace.tierColor(for:)` (DeckWidgets/LiveBoxWidget.swift:470-481) applies
  the ONE pair to: metric-row value text (`metricRow`, :456-466), CPU/MEM/DISK
  chart lines (:423/:434/:445), and per-core CPU lines (:411, each core by its own
  value).
- Settings UI "Thresholds" section (DeckApp/DeckApp.swift:349-358): toggle + 2
  steppers (0...100), both disabled while toggle off.
- NetBox precedent: `NetBoxThresholdTier` wrapper (Shared/NetBoxCore.swift:85-92)
  adds a no-reading guard + unit conversion; NetBox floors threshold steppers at 1
  (DeckSettings.swift:186-187). NetBox keeps ONE pair by design (its PRD §5
  non-goals "no per-direction pairs") — this feature is LiveBox-only.

## Design shape (for the PRD interview)

- **Settings:** 6 new keys — `cpuWarnThreshold`, `cpuAlarmThreshold`,
  `memWarnThreshold`, `memAlarmThreshold`, `diskWarnThreshold`,
  `diskAlarmThreshold` — each tolerant-decoding with a **fallback chain:
  per-metric key → legacy `warnThreshold`/`alarmThreshold` → default 80/90** so
  existing customizations survive the migration (settings-schema-migration
  precedent, ROADMAP.md:56).
- **Pure helper** in Shared (testable in DeckSharedTests; widget target can't be
  compiled into the test bundle): a `Metric` enum (cpu/mem/disk) + a resolver that
  returns the (warn, alarm) pair for a metric, or directly the tier for a
  (metric, value, settings) triple. Mirrors `NetBoxThresholdTier`'s wrapper shape.
- **Widget:** `tierColor(for:)` → `tierColor(metric:value:)`; per-core chart lines
  use the **CPU** pair; per-volume disk rows stay **untinted** (disk-per-volume
  PRD: thresholds are the aggregate DISK row's story).
- **UI:** LiveBoxSettingsView Thresholds section gains per-metric rows (e.g. three
  "CPU / MEM / DISK" stepper groups), single master toggle retained.

## Affected files

- `native/Shared/DeckSettings.swift` — LiveBoxSettings keys + tolerant decode.
- `native/Shared/LiveBoxCore.swift` — add metric resolver (or new
  `LiveBoxThresholdCore.swift`).
- `native/DeckWidgets/LiveBoxWidget.swift` — per-metric tier application.
- `native/DeckApp/DeckApp.swift` — LiveBoxSettingsView Thresholds section.
- `native/SharedTests/LiveBoxThresholdTests.swift` (new) +
  `DecodeTests.swift` LiveBox suite.

## Ambiguities for the interview

1. **Migration:** when per-metric keys are missing but legacy keys exist, inherit
   the legacy pair (one-time) — agreed? And stop encoding legacy keys afterward?
2. **Defaults:** 80/90 for all three metrics, or different sensible defaults
   (e.g. DISK lower)? Stepper range 0...100 like today?
3. **Per-core CPU lines:** use the CPU pair (yes, they are CPU).
4. **Per-volume disk rows:** stay untinted (yes per disk-per-volume PRD).
5. **UI layout:** three compact stepper groups vs. a single warn/alarm column per
   metric row.

## Shell invariants

None touched: material card, dynamic height, corner mask, settings persistence
(path/format), agent, refresh cadences all unchanged. Verified against CLAUDE.md.