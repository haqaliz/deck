# Probe — custom WIQL against a live org (2026-09-25)

Org `ForesightAnalytics`, project `ForesightManifold`, the TaskBox account's PAT
(read from the keychain, never printed). `POST {org}/{project}/_apis/wit/wiql?api-version=7.1`.
Every query below is `SELECT [System.Id] FROM WorkItems WHERE … ` unless noted.

| # | Query (WHERE part) | Result |
|---|---|---|
| P1 | built-in: `TeamProject = @project AND AssignedTo = @Me AND State NOT IN (…)` | 200, 11 items |
| P2 | `… AND ([System.State] = )` | **400**, `message: "Expecting field name or expression. The error is caused by «)»."`, `typeKey: VssPropertyValidationException` |
| P3 | `… AND ([Custom.Nope] = 'x')` | **400**, `"TF51005: The query references a field that does not exist. The error is caused by «[Custom.Nope]»."` |
| P4 | `… AND ([System.State] = 'Doen')` (typo'd value) | **200, 0 items**: silently empty |
| P5 | built-in **without** the TeamProject clause | 200, **53** items (vs 11), the known cross-project leak |
| P6 | `FROM WorkItemLinks … MODE (MayContain)` | 200, `queryType: oneHop`, **`workItemRelations`** (3556 rows), no `workItems` key |
| P7 | `… AND ([System.IterationPath] = @CurrentIteration)`, no team in URL | 200, 70 items: resolves against the project's default team |
| P8 | `… AND (State NOT IN (…))`, unassigned | 200, 129 items |
| P9 | user text `[System.State] = 'Active') OR ([System.Id] > 0` inside our `AND ( … )` | 200, **7559 items, the whole org**. Unbalanced parens escape the wrapper and the project clause with it |
| P10 | `… AND ([System.Id] > 0)` with `&$top=200` | 200, exactly 200 items, **no total field** |
| P11 | same, no `$top` | 200, 4690 items |
| P12 | `ORDER BY` inside the user's clause | **400**, `"Expecting left bracket. The error is caused by «ORDER»."` |
| P13 | `[System.Title] CONTAINS 'a)'` | 200, 4 items: a paren inside a string literal is legitimate |
| P14 | `[System.Title] CONTAINS 'it''s'` | 200, 2 items: `''` is WIQL's quote escape |
| P15 | `[System.CreatedBy] = @Me AND [System.ChangedDate] >= @Today - 30` | 200, 91 items: macros work in the clause |

## Cost of a broad query

`… AND ([System.Id] > 0) ORDER BY [System.ChangedDate] DESC`, measured twice:

| `$top` | bytes | time |
|---|---|---|
| none | 577,287 | 4.55s, **17.80s** |
| 201 | 25,140 | 1.18s, 0.98s |

The loader's `timeoutInterval` is 10s, so an uncapped broad query **times out at
random** and would read as "unreachable". The built-in query is 1,769 bytes / 0.8s.

## What this settles

1. **"Wrong" and "empty" are distinguishable for syntax.** P2, P3 and P12 answer 400
   with a readable `message`. Today that maps to `.badResponse` ("unexpected
   response"). Only a semantically wrong but valid clause (P4) is silently empty,
   which the TaskBox PRD's non-goal feared. A settings-side "Test" that shows the
   match count addresses that.
2. **Wrapping in parens is not isolation (P9).** The clause must be validated
   before it is sent: parentheses balanced outside `'…'` literals (with `''`
   escapes, P13/P14). A clause that fails validation is never sent.
3. **The user writes only the WHERE clause.** Deck owns `SELECT`, `FROM WorkItems`,
   the project clause and `ORDER BY`. That makes link queries (P6) and
   `ORDER BY` (P12) impossible by construction, so no `workItemRelations` parser
   is needed.
4. **`$top` is required for custom clauses and costs the exact total (P10).**
   `$top = idLimit + 1` detects the cap the way `AzurePRCap` does, so the header
   can say "200+ open".
5. **`@CurrentIteration` works without a team segment (P7)**, against the default
   team.
