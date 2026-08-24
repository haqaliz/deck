# PRBox — review queue across GitHub and Azure DevOps

Source: inline brief (deck-next pick, 2026-08-24). Type: `feat`. Slug: `prbox`.

## Brief

A review-queue widget: **your open PRs** and **PRs awaiting your review**.

Unlike the ROADMAP entry (which scoped GitHub only), this must support **two
providers**:

- **GitHub** (`api.github.com`) — reuses the ShipBox PAT path.
- **Azure DevOps git** (`dev.azure.com`) — reuses the TaskBox PAT path.

## Settings shape requested by the user

- The PRBox settings tab has **sub-tabs, one per provider** (GitHub, Azure
  DevOps, …).
- Each provider sub-tab carries **its own show/hide toggle** ("include this
  provider's results") plus that provider's own settings (token, org/owner
  scope, …).
- The widget face renders a **mix of both providers' results** in one list.

## Roadmap context

`ROADMAP.md` M5: "PRBox — GitHub review queue: your open PRs + PRs awaiting
review. Cheapest of the slate: reuses ShipBox's token, `HostGitHubLoader`, and
the `FetchClassifier` error path against the pulls/search endpoints."

## Known caveats carried in from deck-next

1. **Token ownership.** The GitHub PAT lives in `ShipBoxSettings.token`
   (`native/Shared/DeckSettings.swift:483`); the Azure DevOps PAT lives in
   `TaskBoxSettings`. PRBox needs both — either it reads other widgets'
   settings structs (cross-widget coupling) or the user pastes each token
   twice. Settle in the PRD; a shared section is a schema change needing
   tolerant decode.
2. **Rate limits.** GitHub `/search/issues` is capped at 30 req/min
   authenticated, much tighter than the REST endpoints ShipBox uses, against a
   60s agent cadence. Two searches per tick is fine; per-repo fan-out is not.
3. **Version bump.** Adding a widget requires raising
   `CFBundleShortVersionString` / `CFBundleVersion` in `project.yml`, or the
   Widget Center never enumerates it (CLAUDE.md).
4. **Fetch status is keyed per source.** `FetchStatus.Source`
   (`native/Shared/FetchStatus.swift:19`) is
   `shipbox, weather, opencodeRemote, taskbox, calbox` — two providers in one
   widget means either two new source keys or an aggregate.
