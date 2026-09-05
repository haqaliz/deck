# shipbox-fair-share — understanding note

**Type:** feat · **Slug:** `shipbox-fair-share` · **Branch:** `feat/shipbox-fair-share/aliz`
**Date:** 2026-09-05 · **Source:** `docs/planning/_card/issue.md`

## What the work is really asking

ShipBox's merged list is globally newest-first: `ShipBoxMerge.merge` sorts all
runs from all repos by `createdAt` descending, and the face shows
`prefix(runCount)`. A repo that pushes often therefore fills the visible
window with its own history, and a repo that pushes rarely contributes
nothing visible even when its latest run is the piece of news the user cares
about ("is my CI red?"). The multi-repo PRD accepted this explicitly as a
non-goal (prd.md:190-191) and recorded fair share as an open follow-up
(plan_20260825.md:279, ROADMAP.md:310-312). This feature retires that
non-goal with the cheapest possible shape: a pure reordering of the same
runs, so each watched repo is guaranteed representation inside the visible
window. No new data, no new fetch, no face redesign.

## Code map

- `native/Shared/ShipBoxSnapshot.swift:160-176` — `ShipBoxMerge.merge(_:)`:
  the only merge. Concatenates per-repo runs, sorts `createdAt` descending,
  breaks ties by fetch order (stable under a stable snapshot — pinned by
  `ShipBoxMergeTests.testTiesBreakStablyByTheOrderTheReposWereFetched`).
- `ShipBoxSnapshot.swift:291-294` — fetch: `per_page = max(runCount, 2)` per
  repo, so each repo contributes up to `runCount` runs. A fair top-`runCount`
  across ≤5 repos needs ≤ `ceil(runCount/5)` runs per repo → today's page is
  already sufficient; no fetch change expected (probe in plan).
- `ShipBoxSnapshot.swift:310` — loader calls `ShipBoxMerge.merge(perRepoRuns)`;
  one call site.
- `native/DeckWidgets/ShipBoxWidget.swift:281` — face slices
  `entry.runs.prefix(maxCount)`; small = 2, medium/large = `runCount`.
- `ShipBoxWidget.swift:212` — `RunFormatting.totals(for: entry.runs)` counts
  the *whole* merged list; reordering is order-independent for totals.
- `ShipBoxWidget.swift:141` — small face's `widgetURL` is `entry.runs.first`
  (the newest run). Fair ordering changes who "first" is; must be named in
  the PRD.
- `native/SharedTests/ShipBoxMergeTests.swift` — the pure tests to extend.
- Settings: `ShipBoxSettings` in `native/Shared/DeckSettings.swift` (tolerant
  decode is the schema-migration rule; extension reads the non-secret bool).

## Candidate rules (for the interview)

1. **Round-robin interleave** — take each repo's newest, then each repo's
   second-newest, etc.; within a level, order by that run's `createdAt`
   descending. Guarantees: every repo's newest run sits in the top
   `repoCount` rows; newest activity still bubbles to the top of the face.
2. **Guaranteed slot + newest-first remainder** — place each repo's newest
   run (sorted newest-first), then fill the rest of the window with the
   current global merge of the leftovers. Simpler to explain; the top of the
   list stays as close to "global newest" as fairness allows.
3. **Settings toggle** — both rules need one: on/off, default ON (the busy
   repo crowding is a defect, not a preference), new key with tolerant
   decode, pinned in settings tests.

## Ambiguities / open questions for the interview

1. Which rule (round-robin vs guaranteed-slot)? The visible difference is
   whether a busy repo's second-newest run can outrank a quiet repo's newest
   once every repo has one slot.
2. Toggle default ON or OFF? (Existing installs would see the list reorder on
   upgrade either way; default decides whether that is a surprise.)
3. Small face: 2 rows, ≤5 repos — confirm the rule degrades to "newest two,
   unchanged" when the window < repo count, and that `widgetURL` semantics
   (opens `runs.first`) stay as-is.
4. Does fair share apply to the totals row / note composition? (Assume no —
   totals count all runs, order-independent; note names failures, unchanged.)
5. Does the setting live on the ShipBox tab (beside repo mode) with a
   "Fair share across repos" label, defaulting on?