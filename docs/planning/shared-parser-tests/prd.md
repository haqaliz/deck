# PRD: shared-parser-tests

**Slug:** `shared-parser-tests` (branch `feat/shared-parser-tests/aliz`)
**Source:** deck-next handoff (2026-08-15), `docs/planning/_card/issue.md`
**Type:** task (M4 milestone) — no user-visible widget surface.

## 1. The ask

Add a permanent XCTest target for the Shared parsers (ROADMAP.md:53-54) so the
repo stops deleting its tests at merge. Every feature so far did TDD in a
throwaway scratch SwiftPM package that was removed with a "remove scratch test
package" commit (git log: `79845fd`, `d7c1110`, `01e9f0c`, `c9565da`); the
merged repo has zero tests and no test target in `native/project.yml`.

There is no widget surface: the deliverable is a test suite + the minimal
refactors needed to test the pure logic where it lives.

## 2. Test-target spec (the "front face" of this work)

- New xcodegen target `DeckSharedTests`: `type: bundle.unit-test`, platform
  macOS, deployment target 15.0.
  - Sources: `native/Shared` (compiled as-is — imports are Foundation /
    AppKit / SwiftUI / SQLite3, all fine in a macOS test bundle) + new
    `native/SharedTests/` (test files + fixture JSON).
  - Settings: `OTHER_LDFLAGS: $(inherited) -lsqlite3` (matches the other
    targets), `GENERATE_INFOPLIST_FILE: YES`, `SWIFT_VERSION: "5.10"`,
    `CODE_SIGN_STYLE: Automatic` with the same team.
- Scheme: explicit `schemes:` entry in project.yml with the `DeckSharedTests`
  target in the test action (or extend the DeckApp scheme's test action —
  decide in plan; either works for `xcodebuild test`).
- Verification command: `xcodebuild test -scheme DeckSharedTests
  -derivedDataPath native/build`.
- CI: add a test step to `.github/workflows/deck.yml` (after "Generate
  project", before packaging) running the suite on macos-latest.

## 3. Coverage matrix (what gets tests, and the source of truth)

| Area | Code under test | Test source |
|---|---|---|
| ShipBox | `ShipBoxSnapshot` status map / parse / formatting | Port from f0c94c4 (197 ln) |
| HomeBox | `HomeBoxSnapshot` wttr parse, icon symbol, zone rows | Port from 989999a (150 ln + amsterdam fixture) |
| ClipBox | `ClipBoxSnapshot` kind, previews, dedupe, merge | Port from d2f81a0 (139 ln) |
| OpenBox cost | `CostSeries.buildSeries/points/displayID` (post-move) | Port from e8e1c11 (179 ln) |
| Settings | `DeckSettings` tolerant decode | Port from 8ca082b (131 ln) |
| OpenBox tools | `OpenCodeReader.mapToolRows` | Port from 2c899e7 (82 ln) |
| LiveBox | per-core tick delta math (see §5 scope note) | Port from afb1d37 (66 ln) |
| GitBox | `GitBoxSnapshot` dayCounts, daysBack, bucket, streak, shortName, formatters | Written fresh (never had scratch tests) |
| OpenBox model | `ModelParser.parse`, `OpenCodeFormatters` (post-move) | Written fresh |
| DB SQL | `OpenCodeReader` SQL against fixture schema (in-memory sqlite) | Written fresh |

Ported tests assert **current behavior** — they pass against shipped code as-is
(they were written against the same code before the deletion). Fresh tests are
written from behavior. If a test exposes a real parser bug, fixing it **is in
scope** — that is the point of the milestone.

## 4. Required production refactors (mechanical, zero behavior change)

1. **OpenBox pure logic → Shared.** `ModelParser`, `CostSeries`,
   `OpenCodeFormatters` are `private` inside `DeckWidgets/OpenBoxWidget.swift`
   (lines 444-602); the roadmap names ModelParser as a Shared parser, and the
   widget target can't be compiled into a unit-test bundle. Extract them
   verbatim into `native/Shared/OpenBoxCore.swift` (internal), delete the
   private copies, keep call sites identical.
2. **OpenCodeReader SQL test hook.** The 5 SQL strings and `rows(_:_:)` are
   private; `load()` hardcodes `dbPath`. Minimal expose: make the SQL strings
   internal and add an internal `load(from db: OpaquePointer) -> OpenCodeSnapshot?`
   that the public `load()` delegates to. Tests create an in-memory sqlite DB,
   create the opencode `session`/`part` schema, insert fixtures, and run the
   real SQL. (`json_extract` is available in the macOS system sqlite.)

## 5. Scope decision: staged slices

First slice (this PR):
- Test target + scheme + CI step.
- Ported suites: ShipBox, HomeBox, ClipBox, OpenBox cost, Settings, OpenBox
  tools.
- Refactor 1 (OpenBoxCore extraction) + fresh ModelParser/formatters tests.
- GitBox parser/formatter tests (fresh).
- DB SQL fixture tests (refactor 2).

Deferred to follow-on slices (still untested after this PR, recorded in
ROADMAP):
- DevBox lsof/docker parsers (`DevBoxSnapshot`).
- `RemoteOpenCodeLoader` aggregation functions (pure, currently untested).
- `ProcessSnapshot` ps parsing.
- Loader formatters in `DeckWidgets/Loaders/` (NetworkMetrics.formatRate,
  BatteryMetrics formatters, SystemMetrics per-core math) — the LiveBoxCore
  port is only feasible if the per-core math moves to Shared, which touches the
  LiveBox widget file; keep it out of the first slice.

## 6. Non-goals

- No widget/settings/agent behavior changes; no new features.
- No test coverage for SwiftUI views or WidgetKit timelines (UI is verified by
  build + gallery re-add per CLAUDE.md conventions).
- No CI coverage gate (failing tests already fail the build).
- No moving Loader code into Shared in this slice.

## 7. Acceptance criteria

1. `xcodegen generate && xcodebuild test -scheme DeckSharedTests` passes.
2. All three existing targets still build (`xcodebuild build -scheme DeckApp`).
3. OpenBox widget renders identically (ModelParser/cost-chart extraction is
   byte-for-byte logic — verified by build + a gallery re-add of OpenBox).
4. CI runs the suite on every PR.
5. ROADMAP.md M4 "Tests" item checked; deferred items listed with the
   "Deferred" wording so deck-next doesn't re-recommend them.

## 8. Open questions

Answered with recommendations (confirmed at the review gate):
- **Q1 Scope staging** → as §5; deferrals recorded, not dropped.
- **Q2 ModelParser move** → yes; it is the roadmap's named parser and the only
  way to test it without compiling widget sources.
- **Q3 DB SQL fixture fidelity** → fixture schema mirrors the real opencode
  tables (`session`, `part` with JSON `data`); exact columns derived from the
  SQL strings themselves, so the fixture is self-consistent with the queries.
- **Q4 Found-bug policy** → fixes in scope, noted in the PR.
- **Q5 CI** → `xcodebuild test` on macos-latest; expected ~+1-2 min.

## 9. Shell-fit check

No panel invariants touched (no card, flip face, settings, or agent changes).
The only non-test production edits are the two §4 refactors, both behavior-
preserving by construction.
