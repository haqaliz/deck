# Understanding: ShipBox (GitHub Actions run status)

## What the work is really asking

A ninth widget in the Deck shell: GitHub Actions runs for a configured
repository, shown as a status list with colored dots. Pending M3 candidate
(ROADMAP.md:48). Not local-first by design — the gitbox PRD explicitly carves
out "No GitHub/remote activity (ShipBox's job — ROADMAP.md:49, not local-first)"
(docs/planning/gitbox/prd.md:86).

## Shell mapping (grounded in files)

- **Widget template**: HomeBoxWidget — the newest agent-pumped widget
  (HomeBoxWidget.swift:23-95): snapshot store + staleness windows (fresh
  <5 min, stale hint 5–30 min, unavailable >30 min) + unavailable view.
  GitBoxWidget for the colored-dot list-row language
  (GitBoxWidget.swift:211-221 countRow, REPOS section :167-188).
- **Agent pump (the fetch home)**: `DeckAgent/main.swift:52-56` — the HomeBox
  block is the exact precedent: `try? await HostWeatherLoader.fetch(...)` then
  "always written so writtenAt drives the staleness window". ShipBox gets the
  same shape: `HostGitHubLoader.fetch(owner/repo, token)` → `ShipBoxSnapshot`.
  The widget sandbox has NO network entitlement (DeckWidgets.entitlements —
  only app-sandbox), so the fetch must run agent-side; this is proven, not a
  probe.
- **Token pattern**: OpenBox remote mode — `OpenBoxSettings.token` +
  `serverURL`, no default token ever sent (README.md:53-58,
  DeckAgent/main.swift:15-22). ShipBox mirrors it: token is required for the
  widget to show anything; without it the agent skips the fetch and the widget
  shows the unavailable state with a "paste a token in settings" hint.
- **Settings**: `ShipBoxSettings` struct + tolerant `init(from:)` decode
  (pattern: HomeBoxSettings, DeckSettings.swift:248-265), registered in
  DeckSettings.swift:34-42; tab in DeckApp.swift (DeckWidget enum:233-265 +
  detail switch:36-46 + settings view struct).
- **Registration**: `ShipBoxWidget()` in DeckWidgets.swift bundle
  (:14), project.yml sources are directory-based → regenerate with xcodegen;
  register in README + ROADMAP (blueprint ROADMAP.md:8-21).

## GitHub REST contract (Actions API)

`GET /repos/{owner}/{repo}/actions/runs` — headers `Authorization: Bearer
<token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version:
2022-11-28`. Response `workflow_runs[]` key fields (all JSON strings):

- `name` (workflow name), `display_title` (commit subject), `head_branch`,
  `event` (push/pull_request/…), `run_number`
- `status`: `queued | in_progress | completed | waiting | requested | pending`
- `conclusion`: `success | failure | neutral | cancelled | skipped |
  timed_out | action_required | stale | null` (null while not completed)
- `created_at`, `updated_at` (ISO8601) — completed-run duration =
  updated − created
- `html_url`

Rate limits: 5000 req/h with a token, 60/h unauthenticated — token is
required, unauthenticated is a dead end for a 60s-polling agent.

## Ambiguities / open questions (for the PRD interview)

1. Repos: single `owner/repo` field vs list? (GitBox has a paths list precedent.)
2. Token required vs optional-but-recommended — the caveat says required.
3. Face layout per size: small = latest-run summary (status dot + branch +
   duration); medium = recent runs list; large = more rows + per-status totals?
4. Status → color/icon mapping (queued gray, in_progress yellow, success
   green, failure red, cancelled/skipped gray) — pure logic, TDD-able.
5. Staleness windows: reuse HomeBox 5/30 min; what's the failure rate of a
   60s poll against the 5000/h limit? (Trivial: 1440 polls/day ≪ 5000.)
6. What does "configured repo" mean for the widget title — "owner/repo" as-is?
7. Fetch success with 0 runs (brand-new repo): show "No runs yet" not error.
8. Large face: show totals (e.g. "2 failing · 3 passing")?

## Invariants check (CLAUDE.md)

No shell invariant is touched: new widget file, new snapshot + store in
Shared, new settings struct, new tab, agent append. All existing targets keep
their sources; Shared is already compiled into all three targets. Widget must
not regress: re-add from the gallery to verify after install.
