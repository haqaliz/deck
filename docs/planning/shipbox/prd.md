# ShipBox PRD

Slug: `shipbox`
Source: deck-next handoff brief (`docs/planning/_card/issue.md`).
Date: 2026-08-14

## 1. The ask

A ninth Deck widget showing GitHub Actions run status for one configured
repository, as a glanceable status list with colored dots. Closes M3
(ROADMAP.md:48). Not local-first by design — remote activity was explicitly
carved out for ShipBox by GitBox ("No GitHub/remote activity (ShipBox's job —
ROADMAP.md:49, not local-first)", docs/planning/gitbox/prd.md:86).

## 2. User-visible spec

### Front face (3 sizes)

Small / medium / large, all following the shell language (rounded system
fonts, monospaced digits, colored-dot rows, tracked section titles):

- **Header line**: repo `owner/repo` (truncated) + status totals when runs
  exist, e.g. `2 fail · 3 pass · 1 run`. When the snapshot is stale (5–30 min),
  append a muted `· HH:mm` last-update hint (HomeBox stale precedent,
  HomeBoxWidget.swift:273-278).
- **Runs list** (colored-dot rows, newest first, all workflows):
  - dot color = run status (see §4)
  - workflow `name` + `run_number`, e.g. `CI #42`
  - trailing: `head_branch` short + duration for completed runs (e.g.
    `main · 3m12s`), or `RUNNING` for in-progress
- **Empty states**:
  - No snapshot / token missing → unavailable view: "ShipBox" /
    "No build data" / "Paste a repo + token in Deck settings."
  - Snapshot stale (>30 min) → same unavailable view.
  - Token set but fetch failing (network/rate-limit) → snapshot not written;
    widget shows stale/unavailable once the old snapshot ages out.
  - Repo valid, zero runs → header with repo name + "No runs yet".

Size split:
- **Small**: header + 2 latest runs.
- **Medium**: header + 4 latest runs.
- **Large**: header + 8 latest runs + totals line (`statusTotals` row).

### Settings (Deck app, ShipBox tab)

- `repo` — text field, `owner/repo` (default `""`).
- `token` — SecureField, GitHub personal access token (default `""`). Required:
  without it the agent skips the fetch and the widget shows the unavailable
  state. Same security stance as OpenBox remote: no default token is ever sent
  (README.md:53-58).
- `showList` toggle (default true) — show the runs list.
- `runCount` stepper 2–8 (default 4) — runs shown on medium/large.
- Status colors: 4 ColorPickers — `queuedColor` (orange), `runningColor`
  (yellow), `successColor` (green), `failureColor` (red). Cancelled/skipped
  render in a fixed secondary gray.

All settings tolerant-decode like the other widgets (pattern:
HomeBoxSettings, DeckSettings.swift:248-265).

## 3. Data source

- **Endpoint**: `GET https://api.github.com/repos/{owner}/{repo}/actions/runs?per_page=10`
  with headers `Authorization: Bearer <token>`,
  `Accept: application/vnd.github+json`,
  `X-GitHub-Api-Version: 2022-11-28`.
- **Transport**: agent-side only — the widget sandbox has no network
  entitlement (DeckWidgets.entitlements), proven pattern: HomeBox wttr.in
  fetch in `DeckAgent/main.swift:52-56`. `HostGitHubLoader` lives in
  `Shared/ShipBoxSnapshot.swift`, called from DeckAgent + Deck app refresh
  (same dual-pump as HomeBox).
- **Cadence**: 60s agent tick. Rate math: 1440 polls/day ≪ 5000 req/h token
  limit — token comfortably covers it (unauthenticated 60/h would not: token
  is required).
- **Parse**: `workflow_runs[]` → `ShipRun` rows (name, runNumber, branch,
  status, conclusion, createdAt, updatedAt, htmlURL). Status mapping:
  `queued|waiting|requested|pending` → queued; `in_progress` → running;
  `completed` + conclusion `success` → success; `completed` + conclusion
  `failure|timed_out|action_required|stale` → failure; other conclusions
  (cancelled/skipped/neutral) → neutral (gray).
- **Snapshot**: `ShipBoxSnapshot { writtenAt, repo, runs: [ShipRun] }` written
  to `DeckSettings.containerDirectory/shipbox.json`; store with load/save
  (pattern: HomeBoxSnapshotStore).
- **Staleness**: fresh <5 min, stale hint 5–30 min, unavailable >30 min
  (HomeBoxWidget.swift:80-82 precedent).

## 4. Status → color mapping (pure, TDD-able)

| Status | Dot color | Row detail |
|---|---|---|
| queued (waiting/requested/pending) | orange (setting `queuedColor`) | branch + "QUEUED" |
| running (in_progress) | yellow (setting `runningColor`) | branch + "RUNNING" |
| success (completed+success) | green (setting `successColor`) | branch + duration |
| failure (completed+failure/timed_out/action_required/stale) | red (setting `failureColor`) | branch + duration |
| neutral (cancelled/skipped/neutral) | secondary gray (fixed) | branch + duration |

Duration = `updatedAt − createdAt` for completed runs, formatted `XmYs`.

## 5. Shell fit

- New files: `Shared/ShipBoxSnapshot.swift` (snapshot + store +
  `HostGitHubLoader` + parser + status mapping), `DeckWidgets/ShipBoxWidget.swift`.
- Touched files (all append-only, no invariant changes):
  `DeckSettings.swift` (struct + registration), `DeckApp.swift` (enum case,
  detail switch, settings view, refresh), `DeckAgent/main.swift` (fetch block),
  `DeckWidgets.swift` (bundle), README.md + ROADMAP.md (registration).
- xcodegen regenerate (directory-based sources); no Info.plist/project.yml
  edits needed.
- No panel invariant touched (CLAUDE.md conventions).

## 6. Non-goals

- No multi-repo support (single `owner/repo`; list comes later if wanted).
- No checks (commit status) API, no deployments, no PR merge status.
- No "latest per workflow" grouping — all workflows, newest first.
- No widget-side fetch (sandbox has no network entitlement).
- No run detail drill-down (tap opens nothing; htmlURL unused in UI).

## 7. Open questions

None blocking — resolved in interview: single repo; runs list + status totals
on large; all workflows newest first.

Follow-ups (not slice 1): distinguishing auth/404 fetch errors in the widget
("Check repo + token" vs "No runs yet") — slice 1 degrades both to the same
unavailable state; multi-repo list.
