# Probe — search-live-probes (2026-10-11)

Read-only measurements of the Search panel's two network providers, using Deck's
own stored credentials and the request strings its own builders emit.

- **Azure** account `5e44e76d-…` → org `ForesightAnalytics`, projects
  `ForesightManifold` + `MachineLearning`.
- **GitHub** account `7f5be0ef-…` → fine-grained `gho_` PAT as `haqaliz`.

Requests were reproduced from `WiqlClause.query(for:)`, `WiqlResponse.url`,
`HostAzureDevOpsLoader.batchFields`, `GitHubPRSearch.query/url`, and
`AzurePRSearch.listURL/byIDURL` (dumped from a temporary test, since deleted).
No token is recorded here.

## P0 — authentication gate

| Call | Result |
|---|---|
| `GET https://api.github.com/user` | 200 — `login: haqaliz` |
| `GET …/ForesightAnalytics/_apis/connectionData?api-version=7.1-preview` | 200 — `Ali Haqiqi`, id `5d48bc9c-1cf3-419c-b2c5-43c4d36875d2` |

## A — Work-item search (Azure)

The query sent: `SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] =
@project AND (…) ORDER BY [System.ChangedDate] DESC`, `$top=26`.

| # | Measurement | Result |
|---|---|---|
| A1 | `[System.Title] CONTAINS` — partial word? case? | **Case-insensitive substring.** `'login'`→10, `'ogin'`→10, `'log'`→26, `'og'`→26, `'Login'`→10, `'LOGIN'`→10, `'in a'`→26, `'page and'`→8 |
| A2 | `[System.Tags] CONTAINS` — whole or partial? | **Case-insensitive whole tag**, not substring. On #8446 (`eventprocessor-worker; feed-extraction; prd-incident`): `'eventprocessor-worker'`/`'feed-extraction'`/`'prd-incident'`/`'EventProcessor-Worker'`→1 each; `'eventprocessor'`,`'worker'`,`'feed'`,`'extraction'`,`'incident'`→0 |
| A3 | `[System.Id] = N` finds the item | #7228 → 1 row, correct item |
| A4 | No state filter returns closed/old | login hits all `Done`; explicit `[System.State] = 'Done'`→26 |
| A5 | Broad term `'a'` at `$top=26` | 200, **3.6 KB, ~1.0 s** — capped and small |
| A6 | Escaping | Doubled `'o''brien'`→200; raw `'o'brien'`→**400** ("Expecting left bracket … «brien»"). `) [ ] % ; , - _ # + & \| @me $top` inside a **title** literal all →200 |
| A7 | `IN GROUP 'Microsoft.*Category'` | All five →200 (Epic 0 items = empty, still accepted). **A bogus category → 200 with 0 items, not 400** |
| A8 | Two configured projects | One WIQL per project + one org batch = **3 requests**; every row's `System.TeamProject` correct; `MachineLearning` reachable (broad query → 5 ids) |
| A9 | Bare-number item URL | `…/ForesightManifold/_workitems/edit/7228` → 200 |

### Bug found and fixed — a typed `,` or `;` blanked the whole search

`[System.Tags] CONTAINS 'worker;'` → **400 `TF401265: The tag name '…' is
invalid. The name contains an invalid character, such as ','`**. Swept a
punctuation set against the tag literal: **only `,` and `;` are invalid**; every
other punctuation mark is accepted. Because the builder ORs the title and tags
clauses with the same literal, a typed comma or semicolon 400'd the **whole**
search (`queryRejected` → "The service rejected that search.") even though the
title half would have matched:

```
([System.Title] CONTAINS 'login, logout' OR [System.Tags] CONTAINS 'login, logout')  -> 400   (old)
([System.Title] CONTAINS 'login, logout' OR [System.Tags] CONTAINS 'login logout')  -> 200   (fixed)
([System.Title] CONTAINS 'a;b'          OR [System.Tags] CONTAINS 'a;b')            -> 400   (old)
([System.Title] CONTAINS 'a;b'          OR [System.Tags] CONTAINS 'a b')            -> 200   (fixed)
```

No valid Azure tag contains `,` or `;`, so dropping them from the **tag** clause
loses nothing; the title clause keeps the text verbatim. When the tag-safe text
is empty (a query of nothing but delimiters), the tags clause is omitted rather
than sent as an empty literal (an empty literal is also a 400: "The specified
operator cannot be used in conjunction with an empty string").

## B — Pull-request search (GitHub)

Builder query: `is:pr involves:@me "…" in:title,body`, `per_page=25`,
`sort=updated&order=desc`.

| # | Measurement | Result |
|---|---|---|
| B1 | The builder's query for `login` | 200, **`total_count` 11**, 11 items, 1.76 s — this token **does** search |
| B2 | Quoted terms AND-ed, order-independent | `"search" "shell"`→1; `in:title` 3 vs `in:body` 11 vs `in:title,body` 11 (union) |
| B3 | Number pool | `is:pr involves:@me&per_page=100`→100 items; a bare number is found iff among the 100 most-recently-updated |
| B4 | `is:pr` excludes issues | `involves:@me "search"`→18, `is:pr involves:@me "search"`→**17** (the one issue dropped) |
| B5 | Requests per search | 1 (words) + ≤1 (a bare number) = **≤2**, against the 30/min search budget (25/30 left after the probe run) |

**The fine-grained-token caveat is resolved.** The earlier `total_count: 0`
(`prbox-review-state/probe.md:68-75`) was PRBox's own `author:@me is:open`
query — no *open* PRs in the token's two granted repos — not a search limit. The
panel's unbounded query returns 11 rows.

## C — Pull-request search (Azure)

Builder: by-id is the org-level route; words list each project's most recent 100
of any status (`searchCriteria.status=all&$top=100`) and filter locally.

| # | Measurement | Result |
|---|---|---|
| C1 | by-id | Real #4955 → 200 (`repository.project.name`=ForesightManifold, status `completed`); unknown #99999999 → **404** (handled as empty). Org-level route; `restrict` keeps only configured projects |
| C2 | list rows | 100 rows; each carries `repository.project.name`; statuses `active`/`completed` observed → open/merged |
| C3 | **payload cost** | ForesightManifold **535 KB / 2.65 s**, MachineLearning **642 KB / 1.92 s** — a words search downloads ~0.5–0.6 MB **per project** (~1.2 MB / ~4.5 s for two) |
| C4 | Deep link | `…/ForesightManifold/_git/manifold-validation/pullrequest/4955` → 200 |

## Corrections applied

| Finding | Action |
|---|---|
| Typed `,`/`;` 400s the whole work-item search (A, above) | **Code + tests.** `TaskSearch.condition` builds the tags literal from a delimiter-free variant; title keeps the text. `TaskSearchConditionTests` +2 (`testATypedCommaOrSemicolonNeverReachesTheTagClause`, `testADelimiterOnlyQuerySearchesTheTitleWithoutATagsClause`), RED→GREEN, and re-measured live 400→200 |
| Unknown category is 200-empty, not 400 (A7) | **Docs only.** `spotlight-remote-search/verification.md:47-48` corrected; no code (the fixed table is valid) |
| GitHub fine-grained token does search (B1) | **Docs only.** The `prbox-review-state` caveat narrowed; no code |
| Azure PR list costs ~0.5–0.6 MB per project (C3) | **Docs only,** recorded as the cost of the list-API design; no code (no server-side text criteria exists) |
| Tags match whole tags, not substrings (A2) | **No change.** Examples already say "with that tag"; recorded here |

`DeckSharedTests`: **1673 tests, 0 failures**. The two CLAUDE.md grep checks
(`…HostAzureDevOpsLoader.search…` from `DeckAgent`/`DeckWidgets`) stay empty.
