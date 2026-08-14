# Understanding: shared-parser-tests

## What the work is really asking

The M4 milestone (ROADMAP.md:53-54) wants a permanent XCTest target for the
Shared parsers — GitLogParser, ModelParser, formatters, DB SQL — because every
feature so far did TDD in a throwaway SwiftPM "scratch package" that was deleted
at merge (git log: `79845fd`, `d7c1110`, `01e9f0c`, `c9565da` "remove scratch
test package"). The merged repo today has **zero tests** and no test target in
`native/project.yml`. This work makes the test suite permanent and in-repo so
future widgets stop re-deriving it.

## Pure-logic surface to cover

- `native/Shared/` — compiles into all three targets, so a test bundle can
  compile it directly (imports are Foundation/AppKit/SwiftUI/SQLite3 — all
  macOS-testable):
  - `GitBoxSnapshot.swift` — `dayCounts(from:)`, `daysBack`, `bucket`,
    `streak`, `shortName`, formatters (the "GitLogParser" the roadmap names)
  - `OpenCodeReader.swift` — `mapToolRows` (pure), the 5 SQL strings + `rows()`
    (private — needs a minimal expose for DB SQL tests)
  - `OpenBoxWidget.swift` — **not** Shared: private `ModelParser`,
    `CostSeries`, `OpenCodeFormatters` live in the widget file (lines
    444-602). The roadmap names ModelParser, so these move to
    `Shared/OpenBoxCore.swift` (internal; pure extraction, no behavior change;
    only referenced inside OpenBoxWidget.swift)
  - `ClipBoxSnapshot.swift` — kind classifier, previews, dedupe, merge
  - `HomeBoxSnapshot.swift` — wttr parse, icon mapping, zone rows
  - `ShipBoxSnapshot.swift` — status map, parse
  - `DevBoxSnapshot.swift` — lsof/docker parsers, percent parsing
  - `ProcessSnapshot.swift` — ps output parse
  - `RemoteOpenCodeLoader.swift` — aggregate/daily/models/costDaily/utcDay
    (pure, untested anywhere)
  - `DeckSettings.swift` — tolerant decode

## Recoverable test assets in git history

Seven scratch packages had real tests (all under deleted `*Core/` dirs):

| Package | Commit | Tests |
|---|---|---|
| ShipBoxCore | f0c94c4 | ShipBoxCoreTests.swift (197 ln) |
| HomeBoxCore | 989999a | WttrParser/WeatherIcon/ZoneRows (150 ln) + amsterdam_j1.json fixture (1366 ln) |
| ClipBoxCore | d2f81a0 | ClipBoxCoreTests.swift (139 ln) |
| OpenBoxCostCore | e8e1c11 | CostCoreTests.swift (179 ln) |
| SettingsCore | 8ca082b | DecodeTests.swift (131 ln) |
| OpenBoxToolsCore | 2c899e7 | ToolCountTests.swift (82 ln) |
| LiveBoxCore | afb1d37 | PerCoreTests.swift (66 ln) |

GitLogParser and OpenBox formatters never had scratch tests (GitBox predates
the pattern) — coverage for those is written fresh from behavior.

## Files touched (planning ahead)

1. `native/project.yml` — one `bundle.unit-test` target `DeckSharedTests`
   (sources: `Shared` + a new `native/SharedTests/` dir, `-lsqlite3`,
   generated Info.plist) + a scheme with a test action.
2. New `native/Shared/OpenBoxCore.swift` — moved ModelParser/CostSeries/
   OpenCodeFormatters; OpenBoxWidget.swift drops its private copies.
3. `native/Shared/OpenCodeReader.swift` — minimal expose for DB SQL tests:
   SQL strings + a `load(from db:)` entry point (or `rows(_:_:)` internal).
4. `native/SharedTests/*` — ported + fresh test files.
5. `.github/workflows/deck.yml` — an `xcodebuild test` step so CI runs the
   suite on every PR.
6. No widget shell, no settings, no agent changes. No behavior changes to
   production code beyond the mechanical OpenBox extraction.

## Open questions for the PRD

1. **Scope**: all parsers above, or staged? (Recommendation: staged — first
   slice = the 7 ported suites + roadmap-named items; later slices = DevBox,
   RemoteOpenCodeLoader, ProcessSnapshot, Loader formatters.)
2. **ModelParser move**: pure extraction into Shared is the roadmap intent;
   confirm it's acceptable to touch OpenBoxWidget.swift mechanically.
3. **DB SQL tests**: build a fixture opencode schema (session/part tables) in an
   in-memory sqlite DB and run the real SQL strings against it — needs the
   minimal expose above. json_extract is available in macOS system sqlite.
4. **Found-bug policy**: if a ported test exposes a real parser bug, fixing it
   is in scope (that is the point of the milestone).
5. **CI cost**: `xcodebuild test` adds minutes per run — acceptable on
   macos-latest.

## No shell invariants broken

No card/flip/settings/agent behavior changes; the only non-test production
edit is the OpenBox extraction which keeps identical output.
