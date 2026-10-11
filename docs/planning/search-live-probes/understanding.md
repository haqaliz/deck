# search-live-probes — understanding note (Phase 2)

## What the work is really asking

The Search panel shipped with five *deferred* (non-per-keystroke) sources, two
of them network-backed. Both were written from API documentation and fixtures,
and both say so in their own headers: `PRSearch.swift:5-9` ("Built and tested on
FIXTURES ONLY — no live request has been made against either service") and
`TaskSearch.swift`'s design notes. The roadmap makes running the probes the
first thing owed before anyone trusts the feature (`ROADMAP.md:1069-1073`,
`:1077-1079`).

So the unit of work is: **run the read-only probes, and fix what they
contradict.** It is a verification task whose output is (a) a corrections
record and (b) code/test fixes where a fixture-guessed shape is wrong.

## Affected code (the exact shapes to probe)

Work items — `native/Shared/TaskSearch.swift:39-57`, sent by
`HostAzureDevOpsLoader.search` (`AzureDevOpsLoader.swift:580-608`):

- WIQL condition `[System.Title] CONTAINS '<text>' OR [System.Tags] CONTAINS
  '<text>'` (+ `OR [System.Id] = N` for a short number), optionally wrapped
  `AND [System.WorkItemType] IN GROUP 'Microsoft.*Category'`.
- Wrapped by `WiqlClause.query(for:)` (`WiqlClause.swift:78-82`): Deck owns
  `SELECT … FROM WorkItems WHERE [System.TeamProject] = @project AND (…) ORDER
  BY [System.ChangedDate] DESC`, `$top = searchLimit + 1` (26).
- Batch (`workitemsbatch`, org-scoped) requests `System.Id/Title/State/
  WorkItemType/ChangedDate/TeamProject/Tags` (`AzureDevOpsLoader.swift:670-681`).

Pull requests — `native/Shared/PRSearch.swift`:

- GitHub query: `is:pr <scope> "<word>"… in:title,body`, scope default
  `involves:@me` (`PRSearch.swift:108-121`); bare number → second query over
  `recentLimit = 100` by `sort=updated`.
- Azure: bare number → org-level `_apis/git/pullrequests/{id}`
  (`byIDURL`, `PRSearch.swift:182-184`); words → per-project list of the most
  recent 100 of any status, filtered locally (`listURL`/`filter`, `:186-204`);
  `AzurePRSearchParser` reads `repository.project.name` per row.

Wiring: `PullRequestSearchSource` / `WorkItemSearchSource` in
`native/DeckApp/AsyncSearchCoordinator.swift:181-361`.

## What the shipped verification explicitly left unverified

`spotlight-remote-search/verification.md:28-39`:

- That `[System.Tags] CONTAINS` / `[System.Title] CONTAINS` match the way the
  settings copy promises (partial words, case).
- That closed/old items come back with no state filter.
- Latency and size of a broad term at `$top=26`.
- How Azure answers `'`, `)`, `[`, `]`, `%` after escaping.
- That `workitemsbatch` returns `System.Tags`.
- That every account accepts `IN GROUP 'Microsoft.*Category'`.
- The multi-project path (N+1 requests).

`spotlight-more-sources/verification.md:29-37`:

- GitHub: `involves:@me` + `in:title,body` returns what the examples promise;
  the "100 most recently updated" number lookup; Azure by-id 404 behaviour; the
  100-PR pool being useful.

## Ambiguities / open questions (for the interview)

1. **Scope.** The roadmap bullet names the Azure/GitHub probes only. Calendar
   search (`EventKit`, off by default) is a *separate* M10 bullet — in or out?
2. **How to run.** Read-only `curl`/`gh` against the two services is cleanest
   and spends none of the panel's rate budget; driving the installed app proves
   the wiring but shares the 30/min GitHub search budget. Which?
3. **Credentials.** The probes need the user's PAT / GitHub token (Deck already
   stores them in the keychain). The task cannot complete without them.
4. **Fix policy.** A contradicted *request shape* → code + test change. A mere
   API surprise that the code already handles → `verification.md` + any
   user-facing copy (examples, `exampleSummary`). Confirm both count.

## Panel invariants to respect (CLAUDE.md)

- Search is **host-app-only on user interaction**; `grep -rn "HostAzureDevOps…
  HostGitHubPRLoader.search" native/DeckAgent native/DeckWidgets` must stay
  empty. A probe harness must not add a caller in the agent or a widget.
- Only a prefix may reach GitHub from the panel; every typed word stays a
  quoted term. Any fix must not loosen that (the quoting is mutation-tested).
- No new request is added to the agent's 60s tick.
