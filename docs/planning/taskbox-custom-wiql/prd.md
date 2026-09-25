# PRD — TaskBox: custom WIQL

Status: draft for review, 2026-09-25. Inputs: `../_card/issue.md`,
`../_card/understanding.md`, `probe.md` (live org, 15 queries).

## 1. Ask

Let TaskBox show work items matched by the user's own WIQL condition instead of
the fixed "assigned to me, not closed" filter. Everything downstream of the id
list is unchanged: the org-scoped batch, lanes, sort, face layout and the
multi-project fan-out.

This reverses a recorded non-goal (`taskbox/prd.md:295`, echoed at
`AzureDevOpsLoader.swift:393-395`). The reason for that non-goal was that a bad
query and an empty result look the same. The probe shows that is only half
true. Syntax and unknown-field errors answer **400 with a readable message**
(P2, P3, P12). Only a valid-but-wrong clause (P4) is silently empty. This PRD
handles each half separately: its own fetch outcome for the first, and a
settings-side **Test** that shows the match count for the second.

## 2. Decisions (interview 2026-09-25, all recommendations accepted)

| # | Question | Decision |
|---|---|---|
| Q1 | Replace or add to the default filter? | **Replace.** Empty field means the built-in filter. "Start from default" pastes the built-in condition in for editing |
| Q2 | Header wording under a custom query | Custom query: **"N items" / "No matches"**. Default query keeps "N open" / "Nothing assigned" exactly |
| Q3 | `$top` on the default query too? | **Yes**, one code path |
| Q4 | Presets menu? | **No**, free text only. Presets are a follow-up |

## 3. User-visible spec

### Settings (the TaskBox tab): a new **Query** section between "Azure DevOps" and "Tasks"

- **Multi-line text field**, "WHERE condition", monospaced, empty by default.
  The placeholder shows the built-in condition.
- Caption: "Deck always limits the query to each of the account's projects and
  sorts by last change. Write only the condition — no SELECT, FROM or ORDER BY.
  Empty uses the built-in filter: open items assigned to the PAT's owner."
- **Inline validation** (pure, as you type, no network): one red caption line when
  the clause is rejected locally (§5.1), e.g. "Unbalanced parentheses" or
  "ORDER BY is added by Deck — remove it".
- **Apply** button: the field edits a **draft**. Only Apply writes
  `settings.taskbox.query` (and triggers one host refresh). Apply is disabled
  while local validation fails or the draft equals the saved value. A caption
  "Unsaved changes" shows while they differ. See critique A1 for why.
- **Test** button (runs the draft): host-app only, one click = one WIQL call per project (≤5),
  never as-you-type. Disabled while a test runs, when there's no Azure account,
  or when local validation fails. The result line shows:
  - success: "11 matches" (one project) or "ForesightManifold 11 · Ops 0"
    (several). "200+" when capped. A **0** is printed plainly: that's the P4
    case, and the only place it can be caught.
  - 400: Azure's own `message`, verbatim, e.g. "TF51005: The query
    references a field that does not exist. The error is caused by
    «[Custom.Nope]»."
  - anything else: the existing `FetchStatusCopy.hint` for the classified
    outcome.
  - The result clears when the text or the account changes.
- **Start from default** button: sets the draft to the built-in condition.
  Emptying the draft and pressing Apply goes back to the built-in filter.
- The existing `FetchStatusCaption` covers the agent's last tick, including the
  new outcome (§5.3).

### Front face

- Unchanged layout. Only the text changes when the snapshot says it came from a
  custom query:
  - header "N open" becomes **"N items"**, and **"N+ items"** / **"N+ open"**
    when capped
  - empty state "Nothing assigned" becomes **"No matches"**
- The chip line gets a new reason: **"Check the query"** (§5.3).
- Gallery description stays "Azure DevOps work items assigned to you." It's
  static and describes the default.

## 4. Data path

Unchanged transport: agent every 60s, plus the host's refresh on settings
change (`DeckApp.refreshTaskBox`). One WIQL per project, concurrently
(existing `inParallel`), then one org-scoped `workitemsbatch`.

### 4.1 Composition

Deck owns everything but the condition:

```
SELECT [System.Id] FROM WorkItems
WHERE [System.TeamProject] = @project AND (<condition>)
ORDER BY [System.ChangedDate] DESC
```

`<condition>` is the user's clause, or the built-in
`[System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Removed', 'Done')`.
The project clause stays outside the user's text. That's not enough by itself
(P9), so §5.1 validation is what makes it hold.

`FROM WorkItems` only, so tree/one-hop (`workItemRelations`, P6) cannot be
requested, and no relations parser is needed.

### 4.2 Cap

WIQL URL gets `&$top=201` (`WiqlIdParser.idLimit + 1`). Measured: broad clause
577 KB / 4.5–17.8s uncapped (over the 10s timeout) against 25 KB / ~1s capped.
A response with 201 ids is **capped**: its total is a lower bound, "200+"
(`AzurePRCap` precedent). The per-project lists are then interleaved to 200 as
today.

### 4.3 Snapshot (`TaskBoxSnapshot`, tolerant decode, both default `false`)

- `totalIsLowerBound: Bool`: any project came back capped.
- `isCustomQuery: Bool`: the face's wording comes from the data it describes,
  not from `settings.json`. After an edit, the old snapshot keeps its old
  wording until the next tick replaces it.

## 5. Failure behaviour

### 5.1 Local validation (`WiqlClause`, pure, unit-pinned)

Rejected before any request. Scanning skips `'…'` literals (with `''` escapes,
P13/P14) and `[…]` field references:

1. parenthesis depth never goes below 0 and ends at 0 (P9: `a) OR (b` is
   balanced overall but dips below 0)
2. no unterminated `'` or `[`
3. no `ORDER BY`, `ASOF`, `MODE`, `SELECT`, `FROM` keywords (whole-word,
   case-insensitive, outside literals/brackets)
4. at most 4,000 characters (well inside WIQL's 32K limit, and large enough for
   any hand-written condition)

Whitespace-only counts as empty (built-in). A rejected clause on the agent path
throws `AzureDevOpsError.invalidQuery` with **no network call**. The outcome is
`queryRejected` and the last good snapshot stands.

### 5.2 Server rejection

A **400 from the WIQL call** becomes `AzureDevOpsError.queryRejected(message)`,
with the message taken from the error body's `message` (trimmed, first line), or
nil if unreadable. A 400 from any other call keeps today's mapping. The 203
sign-in page and 401/403/404 stay `authOrTarget`.

### 5.3 New `FetchOutcome.queryRejected`

- face line: "Check the query"
- settings hint: "Azure DevOps rejected the TaskBox query. Press Test to see
  its reason."
- Only `.taskbox` can produce it. Other sources return nil (the
  `credentialsUnavailable` precedent). An older build decodes the unknown raw
  value as `.ok` (existing tolerant decode), so a downgrade shows no chip rather
  than a wrong one.

### 5.4 Multi-project

Per-project results follow the existing partial rule. A clause referencing a
field that exists in only one project's process fails in the others. That's a
partial answer with the note "Ops: check the query", or a throw if every
project failed.

## 6. Shell fit

- No new widget, no new snapshot file, no new sampler. It reuses
  `HostAzureDevOpsLoader`, `inParallel`, `AzureIDMerge`, `AzureProjectNote`,
  `FetchStatusCaption`.
- **The extension reads no new setting.** The wording comes from the snapshot
  (§4.3), which satisfies the "extension has no keychain" trap trivially.
- `TaskBoxSettings.query: String`, tolerant-decoded to `""`. Check for a
  hand-written `encode(to:)` (CLAUDE.md trap: `ShipBoxSettings` had one).
- New source files need `xcodegen generate` before the tests count.

## 7. Non-goals

- Presets menu (Q4 follow-up).
- Link/tree queries, user-controlled `ORDER BY` or columns.
- Per-project queries: one condition applies to every project on the account.
- Team context for `@CurrentIteration` / `@TeamAreas`. They resolve against
  each project's default team (P7). A team segment in the URL is a follow-up.
- Saved/shared Azure queries by id (`_apis/wit/wiql/{id}`).
- Exact totals past 200.
- Syntax highlighting / autocomplete of field names.

## 8. Verification

- Unit (`DeckSharedTests`): `WiqlClauseTests` (every §5.1 rule + P9/P13/P14
  cases as fixtures), composition (default composes to today's semantics;
  the project clause always outside), `WiqlIdParser` cap at 201, 400 body →
  message parser (P2/P3 bodies as fixtures), `FetchClassifier` mapping,
  `FetchStatusCopy` totality, snapshot + settings tolerant decode, header
  wording (4 combinations).
- Live (Deck quit, `DeckAgent` driven directly): default query → same 11 items
  as P1; `[System.State] = 'Active'` → items + "N items"; P3 clause →
  chip "Check the query" and snapshot mtime unchanged; P9 clause → rejected with
  no request; broad `[System.Id] > 0` → "200+ items" within the tick.
- Settings: Test on each of the above shows count / Azure's message / local
  error.
- Re-add TaskBox from the gallery. All three sizes render.

## 9. Open questions

None blocking. Presets and team context are recorded as follow-ups.

## 10. Self-critique (2026-09-25)

No 🔴. Nothing touches a shell invariant, and the data path is the proven one.

### 🟡 A1: a half-typed query would go live (fixed above)

`DeckApp`'s 60s timer calls `refreshTaskBox()` with whatever is in settings, and
the agent reads `settings.json` on every tick. A field bound straight to
`settings.taskbox.query` would fetch whatever half-typed condition happened to
be there at that moment, e.g. `[System.State] = 'Act'` (valid, 0 rows) or
`[System.AssignedTo] = @Me OR` (400). The widget would flicker to "No matches"
or a chip while the user types. **Fix:** a draft/Apply split (§3). Test runs
the draft, and only Apply persists it. Apply is gated on local validation, so a
saved query is always locally valid. The agent-side guard stays for a
hand-edited `settings.json`.

### 🟡 A2: how the capped total adds up across projects

Specify: per project, `total = min(ids.count, 200)` and
`capped = ids.count > 200`. Snapshot `totalCount` = the sum,
`totalIsLowerBound` = any capped. So 200 + 11 renders "211+ items", which is a
true lower bound.

### 🟡 A3: pasting the default condition in reads as "custom"

`isCustomQuery` = the trimmed saved clause is non-empty. A user who presses
"Start from default" then Apply gets "N items" wording for the default filter.
Accepted: they chose a custom query, and the wording is still true. Not worth
a string comparison that breaks on whitespace.

### 🟡 A4: the clause must not reach logs or snapshots

A condition can name people (`[System.AssignedTo] = 'Jane Doe'`), and Azure's
400 message echoes fragments of it. Neither goes into `agentLog` (outcome
raw value only, as today) or into `taskbox.json` / `fetch-taskbox.json`. The
message is shown only in the settings Test result, in memory.

### 🟡 A5: keyword rejection could reject something legitimate

`SELECT`/`FROM`/`ORDER`/`ASOF`/`MODE` are rejected only outside `'…'` and `[…]`,
so `[System.Title] CONTAINS 'order'` and field names pass. WIQL has no bare
identifiers that collide with these, since fields are always bracketed and
values quoted. Macros (`@Me`, `@Today - 30`) contain none. Unit-pin a
positive case for each keyword inside a literal.

### 🟡 A6: the Test button and the agent share an Azure budget

Azure DevOps rate limits are per-identity and generous (TSTU-based, not a
small fixed count), and Test costs ≤5 requests per click, same as one agent
tick's WIQL fan-out. There's no CoinGecko-style exposure, but still:
click-only, disabled while running, no as-you-type.
