# ShipBox multi-repo — inline brief (deck-next → dbf feat shipbox-multi-repo)

Top open item in M6 "Improvements (after M5)" (`ROADMAP.md:311`), recorded as an
open follow-up in two other places: `ROADMAP.md:74` and
`docs/planning/shipbox/prd.md:118` ("multi-repo list" — an explicit non-goal of
slice 1, not a blocker).

## The ask

ShipBox currently watches one `owner/repo` (`ShipBoxSettings.repo: String`,
`native/Shared/DeckSettings.swift:486`). Grow it to a small list of repos:

- Settings picks N targets (cap it low, ~5, for GitHub rate limits at the 60s
  agent cadence).
- The snapshot carries runs tagged by repo.
- The face shows them newest-first across repos, with the repo named on each row.
- Migrate the old single `repo` string into the list tolerantly, the way
  MarketBox migrated `symbols` → `tickers`.

## The design point to settle first

`FetchSource.shipbox` is a single key for what becomes N repos
(`native/Shared/FetchStatus.swift:19`). Either it aggregates worst-wins — and
then the widget note *and* the settings sentence must name **which** repo failed,
or the message is useless — or the enum grows per-repo keys, which it cannot do
statically. Follow MarketBox's one-key/several-providers precedent
(`FetchStatus.swift:24`): fail only when no repo at all could be fetched, render
partial results with a note.

## Why now (from deck-next)

- Pure shell reuse, zero new data-source risk: the GitHub Actions loader, the
  agent block and the fetch-status plumbing all ship today; this is a fan-out
  over an existing proven call.
- Every open design point already has a shipped precedent — MarketBox for the
  single-key/several-sources status and for the curated slot-picker settings
  pattern + tolerant migration, PRBox for per-row deep links.

## Not in scope (carried from the original ShipBox non-goals)

- No checks/commit-status API, no deployments, no PR merge status.
- No "latest per workflow" grouping.
- No widget-side fetch (the sandbox has no network entitlement).
