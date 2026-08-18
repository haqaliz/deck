# PRD: deferred-parser-tests

**Slug:** `deferred-parser-tests` (branch `feat/deferred-parser-tests/aliz`)
**Source:** deck-next handoff (2026-08-18), `docs/planning/_card/issue.md`
**Type:** task (M4 tests milestone, follow-on slice) — no user-visible widget surface.

## 1. The ask

Close out the M4 tests milestone by covering the slices explicitly deferred in
ROADMAP.md:57-62 and shared-parser-tests/prd.md:81-89:

1. DevBox lsof/docker parsers (`DevBoxSnapshot`)
2. `RemoteOpenCodeLoader` aggregation
3. `ProcessSnapshot` ps parsing
4. `BatteryMetrics` formatters

All four are pure parser/formatter logic. The infrastructure already exists:
`DeckSharedTests` (native/project.yml:93) compiles `Shared/` + `SharedTests/`,
and CI runs it on every PR (.github/workflows/deck.yml:59). No widget surface,
no new targets, no CI change.

## 2. Coverage matrix (code under test → behavior to pin)

| Slice | Code under test | Source of truth | Moves needed |
|---|---|---|---|
| DevBox lsof | `LsofParser.parse` — field-mode blocks (`c`/`n` tokens), dedup by `command\|name`, empty host skipped, port = int after last `:`, sort port asc / command asc | `Shared/DevBoxSnapshot.swift:117-159` | none (already internal) |
| DevBox docker | `DockerParser.parseContainers` — ps is identity, stats joined by name, stats-only dropped, ps row missing from stats keeps nil percents; name = first comma component; empty ps → `.noContainers` | `Shared/DevBoxSnapshot.swift:161-189` | none |
| DevBox percent | `DockerParser.parsePercent` — `"0.05%"` → 0.05, whitespace trimmed, garbage/`"5"` → nil | `Shared/DevBoxSnapshot.swift:192-198` | none |
| DevBox format | `Formatters.portLabel`, `Formatters.percentString` (nil → "—") | `Shared/DevBoxSnapshot.swift:201-209` | none |
| Remote agg (sessions) | `aggregate(sessions:now:)` — 14d window on `time.updated`, totals, today's sessions + input/output/cost, UTC day bucketing, modelKey (`provider/id`, `local/unknown` fallback), top-3 models cost desc, `costDaily` day asc / cost desc, `round4` | `Shared/RemoteOpenCodeLoader.swift:98-156` | make internal |
| Remote agg (messages) | `aggregate(sessions:messages:now:)` — `role == "assistant"` only, 13d message window, active-session membership (updated ≥ 14d), counted vs today session IDs, today totals from messages, modelKey `provider/model` with `local/unknown` | `Shared/RemoteOpenCodeLoader.swift:158-227` | make internal |
| Remote day bucket | `utcDayString` at UTC midnight boundaries (epoch ms) | `Shared/RemoteOpenCodeLoader.swift:280-294` | make internal |
| Process ps | New `PsParser.parse` — right-anchored: last two whitespace tokens are `%cpu`/`%mem`, remaining tokens joined as path → `lastPathComponent` name; < 3 tokens skipped; unparseable cpu/mem → 0; sorted cpu desc | extraction from `HostProcessSampler.top` (`Shared/ProcessSnapshot.swift:60-77`) | extract |
| Battery format | `BatteryFormatters.formatPercent` ("71%"), `formatTime` (nil → "—", "45m", "6h 35m"), `formatState` (AC Power precedes Full/Charging/Discharging) | `DeckWidgets/Loaders/BatteryMetrics.swift:93-114` | move to Shared |
| Battery math | `percent(current:max:)` clamped 0...100, max ≤ 0 → nil; `timeMinutes(seconds:)` ≤ 0 → nil, rounded | `DeckWidgets/Loaders/BatteryMetrics.swift:81-90` | move to Shared |

Tests are written from **intended** behavior (per shared-parser-tests
precedent: if a test exposes a parser bug, fixing it is in scope). Exact-output
pins (`"—"` in `percentString`/`formatTime`) assert the literal em-dash so a
stray hyphen never passes silently.

## 3. Required production refactors (behavior-identical except #3)

1. **RemoteOpenCodeLoader aggregation → internal.** Extract `enum
   RemoteOpenCodeAggregator` with internal fixture types (`RemoteSession`,
   `RemoteMessage`) and the two `aggregate` overloads + helpers (`utcDayString`,
   `round4`, `modelKey`). **One type set, no fork:** `load()` decodes JSON into
   these same internal types and hands them to the aggregator — no duplicate
   shapes, no dead code. Wire output identical.
2. **ProcessSnapshot parse → pure.** Extract `PsParser.parse(_ raw: String) ->
   [TopProcess]` (parse + cpu-desc sort) into `Shared/ProcessSnapshot.swift`;
   `HostProcessSampler.top` becomes `parse(text)` + `prefix(limit)`. **One
   intended behavior fix** (interview decision): parse `%cpu`/`%mem` from the
   last two whitespace tokens instead of `parts[0]` as path — `comm=` is a full
   path and may contain spaces (e.g. `/Applications/Google Chrome.app/...`),
   which today misreads the row.
3. **BatteryMetrics formatters → Shared.** Move `BatteryFormatters` and the
   private `percent`/`timeMinutes` helpers verbatim into
   `native/Shared/BatteryCore.swift` (internal, `BatteryMath.percent` /
   `BatteryMath.timeMinutes`). The IOKit loader in DeckWidgets keeps
   `BatterySnapshot`/`PowerSource` and calls the shared helpers. Pure-core
   extraction (LiveBoxDiskCore precedent), not whole-loader move — no
   `import IOKit.ps` lands in the app/agent/test targets.

## 4. Interview decisions (2026-08-18)

- **ps parsing: fix right-anchored parse** in this slice (was an ambiguity —
  see §3.2).
- **BatteryMetrics: pure-core extraction** to Shared, loader stays in the
  widget target (see §3.3).
- RemoteOpenCodeLoader: aggregation extracted, `load()` transport untouched
  (URLSession path is not unit-tested — build + manual verify only).
- SystemMetrics per-core math: **out** — needs the math moved to Shared and
  touches the LiveBox widget file; recorded follow-on (see §6).

## 5. Non-goals

- No SystemMetrics per-core math coverage (`Shared/ProcessSnapshot.swift`
  sibling work lives in the LiveBox widget file — follow-on slice).
- No tests for `RemoteOpenCodeLoader.load()` networking (URLSession/JSON
  transport; error mapping is verified by build + existing behavior).
- No tests for `HostDevBoxSampler.snapshot()` subprocess-branch logic
  (docker `.unavailable`/`.noContainers`/`.running` mapping behind `run()`;
  the pure `DockerParser` state tuple is tested).
- No widget, settings, agent, or snapshot-store behavior changes.
- No snapshot JSON round-trip decode tests (DecodeTests already covers
  settings tolerant decode; not part of the deferred list).
- No SwiftUI/WidgetKit timeline tests (UI is verified by build + gallery
  re-add per CLAUDE.md conventions).
- No CI changes (suite already runs on every PR).

## 6. Acceptance criteria

1. `xcodegen generate && xcodebuild test -scheme DeckSharedTests
   -derivedDataPath native/build` passes, including the four new suites.
2. `xcodebuild build -scheme DeckApp` (Release) still builds — widgets, agent,
   and app all compile with the refactors.
3. RemoteOpenCodeLoader wire output identical (aggregation extraction is
   byte-for-byte logic; `load()` unchanged).
4. ps parsing now handles paths with spaces; other rows parse identically.
5. ROADMAP.md deferred line updated: DevBox, RemoteOpenCodeLoader,
   ProcessSnapshot, and BatteryMetrics marked covered; SystemMetrics per-core
   math stays listed as the remaining deferred item.
6. Widget gallery sanity: DevBox + LiveBox + BatBox re-added from the gallery
   render as before (no visual regression from the refactors).

## 7. Open questions

None blocking — the two real decisions were resolved in the interview (§4).
