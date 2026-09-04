# Card — ShipBox per-repo fair share

**Type:** feat · **Slug:** `shipbox-fair-share` · **Branch:** `feat/shipbox-fair-share/aliz`
**Source:** inline brief (`deck-next`, 2026-09-05). No GitHub issue.
**Follow-up from:** `ROADMAP.md:310-312` (ShipBox multi-repo — *"Open
follow-ups: … per-repo fair share so a busy repo cannot crowd out a quiet
one"*) and `docs/planning/shipbox-multi-repo/prd.md:190-191` (the PRD's own
non-goal — *"No per-repo fair share or grouping. A busy repo crowding out a
quiet one is the accepted cost of the merged stream"*).

## The brief

ShipBox merges runs from up to five repos into one newest-first list
(`ShipBoxMerge.merge`, `native/Shared/ShipBoxSnapshot.swift:160-176`) and the
face slices `prefix(runCount)` for display (`ShipBoxWidget.swift:281`). With
`runCount` rows and a busy repo, one repo's newest runs can fill the whole
visible list and a quiet repo's latest run never appears — its CI could be
red for hours below the fold. Add a fair-share merge so each watched repo is
represented in the visible window, as a pure policy change in the shared
merge, unit-pinned in `DeckSharedTests`, with a settings toggle (default
decided in the PRD) and no fetch or face changes unless the probe says
otherwise.

## What the work is (from deck-next's handoff)

1. **Pure merge policy.** Add a fair-share variant beside `ShipBoxMerge.merge`
   — same inputs (`[[ShipRun]]` per repo, or the merged `[ShipRun]`), same
   output shape (`[ShipRun]`), so the loader and the face keep their current
   contracts. The per-repo `repo` tag already carried by every run is the only
   grouping key needed.
2. **Round-robin or guaranteed-slot** — the interview picks the rule. Both
   guarantee each repo's newest run appears within the first `repoCount` rows
   of the visible window; the difference is how the remaining rows fill.
3. **Payload check.** `per_page = max(runCount, 2)` per repo
   (`ShipBoxSnapshot.swift:291-294`). A fair top-`runCount` across 5 repos
   needs at most `ceil(runCount / 5)` runs per repo — within today's page, so
   the probe should confirm no fetch change is needed.
4. **Settings toggle** — on/off, default from the interview; new key decodes
   tolerantly (settings-schema-migration rule), extension reads only the
   non-secret bool (the `grep -rn "\.enabled\|serverURL"` trap in CLAUDE.md).
5. **Pure and pinned** — TDD the rule in `DeckSharedTests` beside
   `ShipBoxMergeTests`; no Charts, no shell changes, one timeline entry.

## Caveats to design around

- **The small face shows 2 rows.** Fair share cannot show 5 repos in 2 rows;
  the rule must degrade to "newest two" when the window is smaller than the
  repo count, without changing what the small face means.
- **Totals count the whole list, not the slice.** `RunFormatting.totals` runs
  over `entry.runs` (`ShipBoxWidget.swift:212`); reordering must not change
  what the header claims.
- **Stability rule.** The current merge breaks ties by fetch order so a stable
  snapshot never reshuffles between ticks (test-pinned,
  `ShipBoxMergeTests.swift:43-49`). The fair variant needs the same property.
- **`widgetURL` opens the newest run.** The small face's tap target is
  `entry.runs.first` (`ShipBoxWidget.swift:141`); if fair ordering changes
  what "newest" means on the small face, say so in the PRD rather than
  quietly reordering a link.
- **Fail-open.** Partial failure already renders survivors with a note; fair
  share must not interact with which repos are present (a failed repo simply
  has no runs this tick).