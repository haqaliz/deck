# Understanding — taskbox-custom-wiql

## What the work is really asking

Let the user replace the fixed filter (`AssignedTo = @Me AND State NOT IN
('Closed','Removed','Done')`) with their own WIQL condition. Examples: "my team's bugs",
"everything in the current sprint", "items I created in the last 30 days". Everything
downstream of the WIQL id list stays the same: the org-scoped batch, lanes,
sorting, the face and the multi-project fan-out.

## The prior decision this reverses

`docs/planning/taskbox/prd.md:295` rejected a custom WIQL field: "a bad query is a
silently empty widget, and the error copy can't distinguish 'your query matched
nothing' from 'your query is wrong'. Revisit once one provider is proven." The
same reasoning is in code at `AzureDevOpsLoader.swift:393-395`. The provider is
now proven, and the probe (`../taskbox-custom-wiql/probe.md`) shows the premise is
half true. Syntax and unknown-field errors are a **400 with a readable message**
(P2, P3, P12). Only a valid-but-wrong clause (P4, a typo'd state value) is
silently empty. So the design needs (a) the server's message surfaced as its own
outcome, and (b) a settings-side test that shows the match count, so "0 matches"
is seen while typing, not discovered on the desktop.

## Affected files

- `native/Shared/AzureDevOpsLoader.swift`: `wiqlQuery` becomes built from a
  clause; `workItemIDs` sends `$top`; `WiqlIdParser` learns the cap; a 400
  error body is parsed into a message; `HostAzureDevOpsLoader.fetch` takes the
  clause.
- New pure type (e.g. `WiqlClause`): validates and composes the user's clause:
  balanced parens outside `'…'` literals with `''` escapes, no `ORDER BY` /
  `ASOF` / `MODE`, blank → built-in default.
- `native/Shared/DeckSettings.swift`: `TaskBoxSettings` gains a tolerant-decoded
  query field (empty = built-in).
- `native/Shared/FetchStatus.swift`: a new outcome for a rejected query (or an
  Azure-specific mapping of 400), plus copy per `FetchStatusCopy`.
- `native/Shared/TaskBoxSnapshot.swift`: `totalCount` can be a lower bound
  (`isCapped`), and `totalLine` renders "200+ open".
- `native/DeckApp/DeckApp.swift`: `TaskBoxSettingsView` gets a query section
  (field, Test button, result line). `refreshTaskBox` passes the clause.
- `native/DeckAgent/main.swift:232`: passes the clause.
- `native/DeckWidgets/TaskBoxWidget.swift`: "Nothing assigned" and the
  gallery description are only true for the default query.
- Tests: `AzureDevOpsParserTests`, a new `WiqlClauseTests`, `TaskBoxSnapshotTests`,
  and settings decode.

## CLAUDE.md traps that apply

- **Anything the extension reads must be answerable from `settings.json`
  without a token.** The widget needs only "is a custom query set" to pick its
  empty-state copy. That's a non-secret field, so it's fine.
- **`DeckSettings` and some settings structs have hand-written coding.** A new
  field must be added to `init(from:)` (tolerant) and checked for a hand-written
  `encode(to:)`.
- **The settings window and the agent share rate limits.** Azure has no
  keyless-quota problem like CoinGecko, but "Test" must still be
  user-initiated, host-app-only and one request per click, never as-you-type.
- **A new source file needs `xcodegen generate`**, or the test is silently not
  compiled.
- **Editing `settings.json` by hand while Deck runs tests nothing.** Quit Deck
  and drive `DeckAgent` directly for the live check.

## Load-bearing findings from the probe

- P9: wrapping the clause in `AND ( … )` does **not** contain it. An unbalanced
  `)` escapes and the query spans the whole org (7559 items). Validation before
  sending is required, not optional.
- Broad clauses cost 577 KB and 4.5–17.8s uncapped (the timeout is 10s); `$top=201`
  costs 25 KB and ~1s. The cap goes on the WIQL call, not after it.
