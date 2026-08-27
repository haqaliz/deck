# Understanding: OpenBox remote incremental sync

Source: `docs/planning/_card/issue.md` (deck-next handoff).

## What the work is really asking

`RemoteOpenCodeLoader.load` currently refetches **everything** each 60s tick
when the server reports no session-level usage: `GET /session`, then
`GET /session/{id}/message` for every session updated in 14 days — full
histories, `parts` (tool outputs, file contents) included, re-decoded and
re-aggregated from scratch (`RemoteOpenCodeLoader.swift:31-38`). The PRD that
shipped remote mode recorded this as the one known risk
(`docs/planning/openbox-remote/prd.md:102-105`): "if it hurts, a follow-up can
add a `limit`-based incremental sync."

This work replaces the full re-fetch with a `limit`-based incremental fetch:
per-session state carried across ticks, only messages newer than the state are
fetched, and aggregation continues to work as today. Two hard constraints from
the brief: existing aggregation stays intact (the pinned
`RemoteOpenCodeAggregator` tests keep passing unchanged), and the widget-facing
surface (face, settings, snapshot schema) does not change.

## Ground truth found in the dig

- **The server supports paging.** Both `sst/opencode` and the `anomalyco`
  fork implement `GET /session/:id/message?limit=N[&before=<opaque cursor>]`:
  `limit` returns the **newest N** messages (verified in their own test:
  `?limit=2` returns `ids.slice(-2)`); `before` walks older pages and requires
  `limit`; a `X-Next-Cursor` / `Link` header appears when more pages exist.
  `limit=0` or omitted → full history. **There is no `after`/`time` param** —
  "messages newer than X" must be found by paging newest-first until a page is
  entirely older than the watermark.
- **Parts ride along in every page** — paging does not drop `parts`, it only
  bounds *how many* messages carry them. The payload saving comes from
  fetching few messages, not slim ones.
- **The agent already has a cheap change signal**: `GET /session` returns
  `time.updated` per session. A session whose `updated` is unchanged since the
  last fetch needs **zero** message requests that tick.
- **Capability detection is free on the fly**: a server that ignores `limit`
  returns more messages than asked — request `limit=K`, and `count > K` means
  "not incremental" → fall back to today's behavior for that server/session.
- **In-flight messages drift**: a message streaming at fetch time carries
  partial tokens. Watermarking by `created` (stable) rather than by newest id
  makes the next tick re-fetch it (created ≥ watermark), so final tokens are
  never undercounted.
- **OpenBox is in local mode on this machine today**: the selected opencode
  account (`haqaliz@proton.me`) has an empty `serverURL`, so
  `openBoxUsesRemoteServer` is false and the `ok` fetch chip is local-DB data
  (`DeckAgent/main.swift:85-92`). The feature must be correct-but-dormant
  until a server URL is configured on an account.
- Installed opencode is 1.18.23; the routes match the paged shape above.

## Design sketch (for the PRD to pressure-test)

1. **State file** (decision in interview: sidecar vs embedded): per-session
   `{ watermark: newest created seen, lastUpdated: session time.updated at
   last fetch }` + a rolling **message archive** for the aggregation window.
2. **Tick**: `GET /session` → for each active session (updated ≥ 14d cutoff):
   skip if `lastUpdated == updated`; else page `limit=K` (+ `before`) newest-
   first until a page is entirely ≤ watermark, appending to the archive and
   advancing the watermark. Count > K on the first page → capability miss →
   full resync for that session (and flag the server in state so it never
   probes again).
3. **Aggregate**: run the **existing** `RemoteOpenCodeAggregator.aggregate(
   sessions:messages:now:)` over the archive (+ this tick's new messages).
   The archive holds only the decoded fields — no `parts` — so it stays small;
   evict messages with `created < now - 13d` after each tick.
4. **Failure paths**: no state file → full resync (today's behavior) and write
   state; a session missing from `/session` → drop its entry; fetch error →
   existing `RemoteError` classification, state untouched, next tick retries.

## Affected files

- `native/Shared/RemoteOpenCodeLoader.swift` — paging loop (transport stays
  here); new pure merge/evict/decide logic extracted alongside
  `RemoteOpenCodeAggregator` (internal, testable).
- `native/DeckAgent/main.swift:61-102` — load state, pass to loader, persist
  new state next to the snapshot; equality/"unchanged" check stays on the
  snapshot alone.
- `native/SharedTests/RemoteOpenCodeAggregatorTests.swift` — unchanged; new
  test file for the sync-state logic.
- No widget, no `DeckSettings`, no `OpenCodeSnapshot` schema change.

## Open questions for the interview

1. State location: sidecar file (`opencode-cursor.json`, agent-only) vs an
   additive optional field inside `OpenCodeSnapshot` (the brief's phrase
   "carried in the snapshot").
2. Live probe: no remote server is configured today — probe against a local
   `opencode serve` (the user can start one) to pin 1.18 behavior, or trust
   the source + capability-detection fallback?
3. Slice scope: include the per-session `updated`-skip (idle tick = 0 message
   requests) in slice 1, or ship paging-only first?