# PRD: OpenBox remote incremental sync

**Type:** feat · **Slug:** `openbox-remote-incremental-sync` · **Source:**
`docs/planning/_card/issue.md` (deck-next handoff) + interview (2026-08-27,
all three recommendations accepted: sidecar state, capability detection with
no live probe, idle skip in slice 1).

## 1. The ask

Replace OpenBox remote mode's full re-fetch — every 60s tick,
`GET /session/{id}/message` for every active session, full histories with
`parts` — with a `limit`-based incremental fetch: per-session state carried
across ticks, only messages newer than the state fetched, existing aggregation
and outcome classification untouched, and nothing user-visible changed (face,
settings, `OpenCodeSnapshot` schema). This closes the known-risk follow-up
recorded at `docs/planning/openbox-remote/prd.md:102-105`.

## 2. User-visible spec

**Nothing changes on either face.** The front face renders the same snapshot
fields from the same `opencode.json`; settings are untouched; no new settings
keys. The only observable differences:

- The remote snapshot can be **fresh even when the previous tick fetched
  nothing new** (today it also would be — same result, less wire).
- An idle tick costs 1 request (`GET /session`) instead of 1 + N.
- The fetch chip and failure wording are byte-identical (same
  `FetchClassifier` path).

## 3. Data source and mechanics

`opencode serve`'s `GET /session/:id/message` (verified in opencode source,
both `sst/opencode` and the `anomalyco` fork — local install is 1.18.23):
`limit=N` returns the **newest N** messages; `before=<opaque cursor>` (requires
`limit`) pages older; `X-Next-Cursor` header advertises the next page;
`limit=0`/omitted returns full history. **There is no `after` param**, so
"newer than X" is found by paging newest-first until a page is entirely older
than the watermark. `parts` ride along in every page — the saving is fetching
few messages, not slim ones.

### Tick algorithm (message mode only)

Message mode is the branch where the server reports no session-level usage
(`sessions.contains { $0.cost != nil || $0.tokens != nil }` → the cheap
session-mode path is **untouched** and already 1 request). Message mode:

1. `GET /session` (always, 1 request). Derive active sessions (updated ≥ 14d).
2. **Idle skip**: if `state.sessions[id].lastUpdated == session.time.updated`
   → zero message requests for that session. (Included per interview.)
3. Otherwise page: `GET /session/{id}/message?limit=100`; then while the page
   contains any message with `created > watermark`, follow `before` cursors
   from the `X-Next-Cursor` header. A page whose messages are **all** ≤
   watermark (a session touched for a title change, say) merges nothing and
   still advances `lastUpdated`.
   **Tick budget:** paging is serial (like today's loader). An idle tick is 1
   request; a heavy catch-up after downtime is ~2 pages × active sessions —
   a 20-session catch-up measured at ~0.2s/request is ~8s, inside the 60s
   cadence. No `withThrowingTaskGroup`; the ShipBox fan-out lesson applies to
   N×2-request sources, not this.
4. **Pure API shape** (keeps TDD honest): `RemoteOpenCodeSync.plan(state,
   sessions) -> [Plan]` (skip / page / fullFetch) and
   `RemoteOpenCodeSync.merge(state, sessionID, page, hasNextCursor) ->
   (state, needMore)`. The loader's loop is thin glue: fetch the next page,
   feed it to `merge`, repeat while `needMore`. All decisions are testable
   without a server; only the GET calls live in the loader.
4. **Capability detection, on the fly, no live probe needed** (per interview):
   - response count > `limit` → the server ignores `limit` → **full-resync
     fallback** for that server (fetch everything, today's behavior), flagged
     in state so it never probes again;
   - a `before` page identical to the previous page → `before` ignored (older
     servers) → **single-page mode**: one `limit=100` fetch per tick, merge by
     id; the <100-messages-in-60s gap risk is accepted and documented;
   - a page whose decode fails under both accepted shapes → existing
     `RemoteError.transport` classification, nothing else changes.
5. Merge new messages into the archive (dedupe by id), advance the watermark
   to the newest `created` in the archive, then run the **existing**
   `RemoteOpenCodeAggregator.aggregate(sessions:messages:now:)` over archive +
   new messages. Evict archive entries with `created < now - 13d`.

### The message-shape fix (required for the feature to be real)

The loader decodes `/session/{id}/message` as `[{info, parts}]` envelopes
(the server shape openbox-remote was built against). Current opencode serves
flat `{...info, parts}` arrays. Message mode is dormant on this machine today
(local DB mode), so the mismatch has never surfaced; incremental sync exercises
this path, so the loader must accept **both shapes** — try the envelope decode
first, fall back to flat. A few lines + fixtures, no behavior change for the
working envelope path.

### State (sidecar, per interview)

Agent-only `opencode-cursor.json` next to `opencode.json` — the widget-facing
snapshot stays byte-stable and the agent's unchanged-skip check
(`DeckAgent/main.swift:94`) is untouched:

```json
{
  "version": 1,
  "server": "http://nuc:4096",
  "mode": "incremental" | "fullFetch" | "singlePage",
  "sessions": { "ses_abc": { "watermark": 1785000000000, "lastUpdated": 1785000000000 } },
  "messages": [ { "id": "...", "sessionID": "...", "role": "assistant",
                  "created": 1785000000000, "modelID": "...", "providerID": "...",
                  "cost": 0.12, "tokens": { "input": 1, "output": 2, "cache": { "read": 0, "write": 0 } } } ]
}
```

- `version` guards future schema changes: an undecodable state file reads as
  absent → full resync (self-healing).
- Written with `AtomicFile` (unique temp + rename), like every other store.

- `server` mismatch (account switched to another URL) → discard state → full
  resync.
- Missing/corrupt state → full resync (today's behavior), rewrite after.
- State persists **only on a fully successful tick**; an error mid-tick keeps
  the old state, and the next tick's overlapping merge is idempotent.
- Prune: drop `sessions` entries whose session is absent from `/session` and
  older than 14 days; evict messages past the 13-day window.
- The archive holds only decoded fields, never `parts` — a heavy 14-day
  history is roughly 1 MB of JSON; rewritten only when changed.

## 4. Shell fit

Pure follow-on slice, zero shell contact:

- `native/Shared/RemoteOpenCodeLoader.swift` — paging loop (transport);
  new internal `RemoteOpenCodeSync` enum next to `RemoteOpenCodeAggregator`
  (pure: merge, evict, decide, state codec) — the established
  loader-owns-transport / pure-logic-testable split.
- `native/DeckAgent/main.swift:61-102` — load sidecar, pass state in, persist
  new state beside the snapshot; opencode.json equality check unchanged.
- `native/SharedTests/RemoteOpenCodeAggregatorTests.swift` — **unchanged**;
  new `RemoteOpenCodeSyncTests.swift` pins the new logic.
- No widget, no `DeckSettings`, no `OpenCodeSnapshot`, no project.yml change.

## 5. Non-goals

- No change to session-usage mode (already 1 request per tick).
- No change to `probe()` / Verify.
- No UI for the sync state; no settings keys.
- No `after`/`time` param emulation on the server side.
- No live probe against the user's server (none is configured; capability
  detection replaces it — per interview).
- No fix to the dormant envelope-vs-flat decode beyond accepting both shapes.

## 6. Open questions (resolved)

- State location → **sidecar file** (interview).
- Live probe → **capability detection, no probe** (interview); the message
  shape is covered by dual-shape decode instead.
- Idle skip in slice 1 → **yes** (interview).
- Page size → 100 (10 requests = 1000 messages in a catch-up; old loader cost
  was the whole 14-day history, so any catch-up is ≤ old steady state).

## 7. Risks (stated honestly)

- **Dormant until remote mode is used.** Both opencode accounts on this
  machine have empty `serverURL`s; the feature is correct-but-idle until one
  is configured. Verified by reading the live `settings.json`.
- **Single-page-mode gap**: on servers without `before`, >100 new assistant
  messages in one 60s tick would leave a permanent small undercount (older
  than the watermark, never refetched). Documented in code; the old server
  shape is pre-2025, so the risk is theoretical for any server the user runs.
- **In-flight message drift** is handled by design: watermarking by `created`
  (stable) means a streaming message is refetched each tick until complete,
  so final tokens are never undercounted.
- **Session-usage servers never use this code path** — the win applies only
  to message-mode servers, which is exactly the case the original PRD flagged
  as heavy.
- **First tick after upgrade does a full resync** (no state file yet) — one
  heavy tick, then incremental forever after. A server whose message shape is
  neither envelope nor flat fails the fetch with the existing `transport`
  classification ("Can't reach the opencode server" wording) — unchanged,
  pre-existing behavior for a shape Deck has never supported.