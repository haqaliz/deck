# PRD: ShipBox per-repo fair share

**Slug:** `shipbox-fair-share` · **Branch:** `feat/shipbox-fair-share/aliz`
**Date:** 2026-09-05 · **Source:** `docs/planning/_card/issue.md`
**Supersedes a non-goal:** `docs/planning/shipbox-multi-repo/prd.md:190-191`
("No per-repo fair share or grouping. A busy repo crowding out a quiet one is
the accepted cost of the merged stream") — retired by decision, per the
recorded follow-up (`plan_20260825.md:279`, `ROADMAP.md:310-312`).

## 1. The ask

ShipBox merges runs from up to five repos into one newest-first list and the
face shows the first `runCount` rows. A repo that pushes often can fill the
whole visible window with its own history, so another repo's latest run —
including a red CI — never appears. Add a **fair-share merge**: a pure
reordering of the same runs that guarantees every watched repo's newest run
sits inside the visible window, controlled by a settings toggle, with no
change to fetching, totals, failure handling or the face layout.

## 2. User-visible spec

### Front face (unchanged layout, changed order)

- **Medium / large:** with the toggle on, the merged list interleaves repos
  round-robin by creation date. The first row is still the globally newest
  run; within the first `repoCount` rows every repo with any run appears at
  least once. A busy repo's history no longer hides a quiet repo's latest
  run.
- **Small (2 rows):** unchanged. The window is smaller than the repo count,
  so the rule degrades to "the two newest runs" — the small face cannot show
  five repos in two rows.
- **Header, totals, dots, rows, links:** unchanged. `widgetURL` still opens
  `runs.first`, which remains the globally newest run (round 0 of the
  interleave is the repos' newest runs sorted newest-first; its first
  element is the global maximum — pinned by test).

### Back face (settings)

- ShipBox tab, beside the repo-mode controls: **"Fair share across repos"**
  toggle, **default ON** (the crowding is a defect, not a preference; users
  who want pure newest-first turn it off).
- Label copy: `Fair share across repos` with a one-line caption
  (`Each repo's newest run is shown before any repo repeats.`).

## 3. Data source and fetch policy

Unchanged: `DeckAgent` (60 s) → `shipbox.json` → widget; the host app's
`refreshShipBox()` mirrors it. No new requests, no payload change:

- `per_page = max(runCount, 2)` per repo already supplies up to `runCount`
  runs per repo. A fair top-`runCount` across ≤5 repos consumes at most
  `ceil(runCount / 5)` levels per repo (≤ 2 for `runCount ≤ 8`), so today's
  page is provably sufficient — the plan verifies this with a test rather
  than a probe.
- The snapshot stores the full fair-merged list; the widget slices as today.
- **Merge call site** (`ShipBoxSnapshot.swift:310`):
  `settings.fairShare ? ShipBoxMerge.fairMerge(perRepoRuns) : ShipBoxMerge.merge(perRepoRuns)`.

## 4. The rule (round-robin interleave, pinned by tests)

`ShipBoxMerge.fairMerge(_ perRepo: [[ShipRun]]) -> [ShipRun]`:

1. Each repo's runs are already newest-first (GitHub's page order; the
   existing merge does not reorder within a repo either).
2. Emit level by level: level 0 = every repo's newest run, level 1 = every
   repo's second-newest, and so on, skipping repos that have no run at that
   level.
3. Within a level, order by `createdAt` descending; ties break by the order
   the repos were fetched in (the existing merge's stability rule, so a
   stable snapshot never reshuffles between ticks).

Guarantees (each pinned by a test):

- **Fairness:** with `k` repos each having ≥1 run, every repo appears in the
  first `k` positions.
- **Newest first:** `result.first` is the globally newest run.
- **Intra-repo order:** a repo's runs stay newest-first relative to each
  other.
- **Degradation:** with fewer runs than repos (or one repo, or none), the
  output equals the current merge's semantics (one repo → newest-first;
  empty input → empty output).
- **Stability:** equal timestamps never reorder between ticks.

## 5. Failure policy

Unchanged in every row of the multi-repo table (PRD §6 of
`shipbox-multi-repo`): a repo that failed this tick contributes no runs and
is named in `note`; fair share operates on whatever `perRepoRuns` the fetch
returned. No interaction with `FetchStatus`, chips, or the last-good
snapshot.

## 6. Shell fit

**Reused unchanged:** `ShipBoxMerge` (new pure sibling), `ShipRun.repo` (the
only grouping key), `RunFormatting`, the loader, the widget face, the agent
path, `FetchStatus` machinery.

**Settings:** `ShipBoxSettings.fairShare: Bool?` with `decodeIfPresent`
default `true` (tolerant decode is the schema-migration rule). The field is
read by the **agent** (which has keychain access) at merge time — the widget
extension never reads it, so the "two settings fields read inside the
extension" trap (CLAUDE.md) does not apply; grep check in the plan.

**Migration:** absent key → `true` (the new default). No legacy key to
clear — the field is new, not renamed. `scrubbedOfSecrets` unaffected.

**Invariants checked (CLAUDE.md):** no Charts near the face; one timeline
entry; one snapshot file, atomic writes; tolerant decode; version bump to
**1.39 / 39** across the three targets in `project.yml`.

**Deviation:** none. This is a pure-function addition with one call-site
change and one settings toggle.

## 7. Non-goals

- No grouping, headers, or per-repo sections — the list stays one merged
  stream.
- No per-repo colors, counts, or quota setting (one global toggle only).
- No change to the small face's two-row limit or its `widgetURL` semantics.
- No change to totals (they count the whole list, order-independent), notes,
  chips, fetch fan-out, payload size, or discovery (dynamic mode) — fair
  share applies to whatever repos were fetched.
- No interaction with the `runCount` setting's range or the per-repo page
  size.

## 8. Open questions

Resolved in the interview (2026-09-05): rule = round-robin; default = ON;
small = degrade to newest two; scope = run list only; placement = ShipBox
tab. Two assumptions the plan will pin rather than ask again:

1. `result.first` stays the globally newest run (and therefore the small
   face's link target is unchanged) — pinned by test.
2. A snapshot written by a pre-upgrade agent (global-newest order) renders
   unchanged until the new agent's first tick rewrites it — acceptable, and
   the standard upgrade behavior for every snapshot.