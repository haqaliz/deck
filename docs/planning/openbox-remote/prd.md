# OpenBox Remote Server Mode — PRD

Slug: `openbox-remote` · Type: feature · Source: `docs/planning/_card/issue.md` (deck-next handoff)

## 1. The ask

Add **remote server mode** to OpenBox. When a server URL is configured in
settings, usage metrics come from an `opencode serve` instance over HTTP
(basic auth) instead of the local `opencode db` SQLite. When no URL is
configured, behavior is unchanged (local DB).

Feasibility (verified against opencode docs + SDK types, Aug 2026):

- `opencode serve` exposes `GET /session` and `GET /session/{id}/message`
  (`opencode.ai/docs/server/`).
- There is **no usage/summary endpoint**: `Session` carries no cost/tokens.
  Usage must be aggregated client-side from `AssistantMessage` fields
  (`cost`, `tokens{input, output, reasoning, cache{read, write}}`,
  `time.created`, `modelID`, `providerID`).
- Auth is **HTTP basic** (`OPENCODE_SERVER_PASSWORD`, username `opencode`),
  not a bearer token — the current "Token" setting label is misleading.

## 2. User-visible spec

### Front face (unchanged layout, one label change)

- Header: today's IN / OUT tokens + COST — unchanged.
- Chart: daily input/output over last 14 days — unchanged.
- Models: top 3 by cost — unchanged (from aggregated remote data).
- Footer: local mode shows all-time totals; **remote mode shows 14-day window
  totals, labeled `14D`** (decision: bounded fetch; all-time would require
  pulling every message).

### Back face (settings)

- **"Server URL"** — text field, empty default. Auto-mode switch: URL set →
  remote, empty → local (decision).
- **"Token" → renamed "Server password"** — same persisted `token` key
  (backward compatible with existing `settings.json`), placeholder
  `OPENCODE_SERVER_PASSWORD`, default `OPENCODE_TOKEN` env (unchanged).
  Sent as basic-auth password with fixed username `opencode` (decision).
- Refresh picker (5/10/30/60s) — unchanged.

### Error / empty state

- Remote unreachable or 401: error line
  `Could not reach opencode server at <url>. Check URL and password.`
- Keeps last good data; same failure semantics as local mode today.

## 3. Data source

- Loader: `RemoteOpenCodeMetricsLoader` — pure, injected URL + password +
  HTTP transport (testable with fixture JSON).
- Fetch sequence per refresh:
  1. `GET {url}/session` (basic auth) → sessions; keep only
     `time.updated ≥ now − 14d` (bounded fetch).
  2. `GET {url}/session/{id}/message` per kept session → filter
     `role == "assistant"`, aggregate:
     - day bucket = UTC day of `time.created` (matches SQL `date()`);
     - model key = `providerID/modelID` (feed `ModelParser.parse`);
     - sums: input, output, cache read/write, cost; session count.
- Cadence: the existing refresh picker; no caching in this slice.
- 14-day window vs today: same bucket math as local queries.

## 4. Shell fit

- Touches only OpenBox: `OpenCodeMetrics.swift` (new loader + aggregation),
  `MetricsStore.swift` (choose loader by `serverURL`), `Settings.swift`
  (`serverURL` field), `SettingsView.swift` (URL row, rename label),
  `ContentView.swift` (footer "14D" label + remote error copy).
- **No panel-invariant changes**: no AppMain, no level/corner/height/card
  changes. Settings face grows by one row — dynamic height handles it.
- Local mode path is untouched; remote adds a parallel loader, does not
  refactor the shell.

## 5. Non-goals

- No server-side model restriction (server's `opencode.json` concern, not the
  widget's).
- No username setting (fixed `opencode`), no TLS pinning/cert UI.
- No all-time totals in remote mode; no caching/offline persistence.
- No changes to LiveBox or the native WidgetKit project.

## 6. Critique fixes (self-critique, Phase 4)

🟡 **Test-target structure.** `Package.swift` has only executable targets;
XCTest cannot import an executable. The pure logic under test must live in a
**library target** (`OpenBoxCore`) that both the OpenBox executable and the
XCTest target depend on. Plan: move `OpenCodeMetrics`, `ModelParser`,
formatters, and the remote aggregation into `OpenBoxCore`; keep Process-based
DB runner + UI in the executable.

🟡 **Main-thread blocking.** The current loader runs `Process` synchronously
on the main thread. Remote mode fans out to N requests per refresh
(1 + sessions), so it must run off-main: `URLSession` async on a background
task, aggregate, hop to `@MainActor`. Local loader untouched.

🟡 **Session-count semantics drift.** Local `today` counts sessions *created*
in 24h; remote counts sessions with ≥1 message in the window. Minor drift,
acceptable — document it in the loader comment.

🟡 **Payload size.** `/session/{id}/message` returns `parts` (full tool
outputs/files) per message, which we don't need. For a large DB this makes
each refresh heavy. First slice accepts it (personal server); if it hurts,
a follow-up can add a `limit`-based incremental sync. Noted as known risk.

## 7. Open questions (resolved)

- Auth: password via basic auth, username `opencode` (user decision).
- Totals in remote mode: 14-day window labeled `14D` (user decision).
- Mode selection: auto — URL set → remote (user decision).
- Test fixtures: use `opencode-go/deepseek-v4-flash-max` only; do not invent
  other model names in tests (user decision).

## Test strategy (TDD)

- New XCTest target (first test target in the package). Pure logic under test:
  - aggregation over fixture `session` + `message` JSON (today, daily buckets,
    model sums, cache sums);
  - 14-day session filter;
  - `ModelParser.parse` on `opencode-go/deepseek-v4-flash-max`
    (provider/id/variant split);
  - day-bucket = UTC (matches SQL);
  - error mapping (HTTP 401/5xx/connect → loader error string).
- UI/shell verified by `swift build -c release` + `swift run OpenBox
  --debug-flip` + window-bounds check (unchanged behavior expected).
