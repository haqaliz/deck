# PRD: search-live-probes

**Slug:** `search-live-probes` · **Branch:** `task/search-live-probes/aliz`
**Picked by:** `deck-next` · **Closes:** the first M10 follow-up, `ROADMAP.md:1077-1079`
**Type:** verification + targeted fix (`dbf task search-live-probes`)

## 1. Summary

The Search panel's two network providers — Azure DevOps **work-item** search and
**pull-request** search (GitHub + Azure) — were built and fixture-tested but
**never run against a live service** (`docs/planning/spotlight-remote-search/verification.md:28-39`,
`docs/planning/spotlight-more-sources/verification.md:29-37`). Their request
shapes are educated guesses at the services' behaviour.

This unit runs read-only probes against the two services, records what is
actually true, and **fixes whatever the shipped code gets wrong** — a request
shape, a parser, a category, or user-facing copy that overpromises.

## 2. Scope

**In:** the two sources named in the roadmap bullet.

- Work-item search: `TaskSearch.condition(for:)` (`native/Shared/TaskSearch.swift:39-57`)
  through `HostAzureDevOpsLoader.search` (`AzureDevOpsLoader.swift:580-608`) and
  the batch at `:683-698`.
- Pull-request search: `PRSearch.swift` in full, plus
  `HostGitHubPRLoader.search` (`PRBoxSnapshot.swift:630-648`) and
  `HostAzurePRLoader.search` (`AzureDevOpsLoader.swift:1124-1166`).

**Out (separate M10 bullets, not this unit):** calendar/EventKit search; commits;
markets; the panel's local providers; any new source or UI.

## 3. Method — read-only API harness

Direct `curl` against `dev.azure.com` and `api.github.com`, replicating the
exact request each loader builds. This spends **none** of the panel's shared
rate budget and isolates the request shape from the app. The installed panel is
not driven (the shapes are what is unverified, not the wiring).

- WIQL: `POST {projectBase}/_apis/wit/wiql?api-version=7.1&$top=26`
  body `{"query": "<WiqlClause.query(for: …)>"}`.
- Batch: `POST https://dev.azure.com/ForesightAnalytics/_apis/wit/workitemsbatch?api-version=7.1`.
- GitHub: `GET https://api.github.com/search/issues?q=<query>&per_page=25&sort=updated&order=desc`.
- Azure PR list: `GET {projectBase}/_apis/git/pullrequests?searchCriteria.status=all&$top=100&api-version=7.1`.
- Azure PR by id: `GET https://dev.azure.com/ForesightAnalytics/_apis/git/pullrequests/{n}?api-version=7.1`.

**P0 — authentication gate.** Before the matrix: `GET https://api.github.com/user`
(core GitHub identity, a non-search call) must answer 200 for the GitHub token,
and `GET https://dev.azure.com/ForesightAnalytics/_apis/connectionData?api-version=7.1-preview`
200 for the PAT. A token that fails auth invalidates the whole run rather than
being misread as a code contradiction.

**The harness must reproduce requests from the app's own builders, not by
hand.** Before each probe, run the loading code's pure builders and use their
output verbatim: `WiqlClause.query(for:)` + `WiqlResponse.url(target:top:)`,
`workitemsbatch`'s body fields (`HostAzureDevOpsLoader.batchFields`),
`GitHubPRSearch.query(tokens:scope:)` + `.url(query:perPage:)`,
`AzurePRSearch.listURL(target:)` / `.byIDURL(target:id:)`. A hand-typed request
that disagrees with the builder would report a contradiction the app does not
have. (Throwaway Swift snippets printing these are fine; they are not committed.)

Raw requests and raw responses (truncated) are captured in
`docs/planning/search-live-probes/probe.md` — the corrections record. The only
file any probe writes is `probe.md` (no `--output=` files, no temp artifacts).

## 4. Credentials & safety

Tokens come from Deck's own keychain items (user-approved):

- Azure `5e44e76d-…` → org `ForesightAnalytics`, projects
  `[ForesightManifold, MachineLearning]`.
- GitHub `7f5be0ef-…` → fine-grained `gho_` PAT as `haqaliz`.

Service `com.deck.app`, item `account.<id>.token`. **No token is written to any
file or log** — it is passed to `curl` via a shell variable only. Each request
is `GET`/`POST`-read: no mutating Azure or GitHub call is made.

**Both providers are on today.** A selected account *is* "on" since the
credential redesign (`CredentialsMigration.swift:170-183`), so PRBox's legacy
`enabled:false` in `settings.json` is inert and the panel's `pr ` source is
live; Spotlight has `taskEnabled:true` and `prEnabled:true`. The probe is
therefore meaningful — this is not testing a disabled feature.

## 5. Probe matrix

### A. Work-item search (Azure)

| # | Question | Where it lands if wrong |
|---|---|---|
| A1 | `[System.Title] CONTAINS 'x'` — partial word? case? multi-word? | `TaskSearch.condition`; panel ordering / examples copy |
| A2 | `[System.Tags] CONTAINS 'x'` — does it match a whole tag, a partial tag, or any substring? | `TaskSearch.condition`; `workitemsbatch` returns `System.Tags`? |
| A3 | `[System.Id] = N` finds the item in a configured project | `TaskSearch.condition:47-49` |
| A4 | No state filter → closed/old items come back | examples copy ("of any age or state") |
| A5 | `$top=26` on a **broad** term: latency + payload size | `searchLimit` |
| A6 | Escaping: text with `'`, `)`, `[`, `]`, `%` — quote-doubling accepted? a raw `'` rejected? | `TaskSearch.sanitise`/the literal; `WiqlResponse.interpret` |
| A7 | Each `IN GROUP 'Microsoft.{Bug,Requirement,Epic,Feature,Task}Category'` accepted; an unknown category → 400 with message | `WorkItemKind.category`; `queryRejected` wording |
| A8 | Configured projects `ForesightManifold` + `MachineLearning`: N+1 requests, each row's project correct | `HostAzureDevOpsLoader.search`; `System.TeamProject` field |
| A9 | The bare-number path returns the item with a working `…/_workitems/edit/{id}` URL | `TaskSearch.results`; `WorkItemParser` URL |

### B. Pull-request search — GitHub

| # | Question | Where it lands if wrong |
|---|---|---|
| B1 | `is:pr involves:@me "<w>" in:title,body` returns what the examples promise; does **this fine-grained token** return anything at all? | `GitHubPRSearch.query`; `exampleSummary` |
| B2 | Quoted words AND-ed (all must match), any order; `in:title,body` honoured | `GitHubPRSearch.tokens/query` |
| B3 | Bare number: the second query over `sort=updated&per_page=100` actually contains a wanted older PR | `GitHubPRSearch.recentLimit`; example copy ("your 100 most recently updated") |
| B4 | `is:pr` excludes issues (an issue has no `pull_request` key) | `GitHubPRSearchParser.parse` |
| B5 | Rate: request count per search ≤ the 30/min search budget | `HostGitHubPRLoader.search` |

### C. Pull-request search — Azure

| # | Question | Where it lands if wrong |
|---|---|---|
| C1 | by-id route (org-level) returns the PR; unknown id → **404**; known-but-other-project → restricted out | `AzurePRSearch.byIDURL`/`interpretByID`/`restrict` |
| C2 | list route: `value[]` rows carry `repository.project.name`; `status` maps completed→merged, abandoned→closed | `AzurePRSearchParser.hit` |
| C3 | The list is project-scoped and returns up to 100 of any status — a useful pool; local token filter behaves | `listURL`; `AzurePRSearch.filter` |
| C4 | Deep-link URL `…/_git/{repo}/pullrequest/{id}` is valid | `AzurePRParser.webURL` |

## 6. Corrections policy (fix vs document)

For every contradiction found:

1. **Request shape / parser / category wrong** → change the code **and** add a
   test; where a guard already exists, mutation-check it (remove the guard,
   the suite must fail).
2. **Service behaves as documented, but the shipped copy overpromises** (an
   example, `exampleSummary`, or a settings sentence) → fix the copy. No code.
3. **Service behaves as promised** → no code; record the measurement in
   `verification.md` and close that "NOT verified" bullet.
4. **Not answerable on this machine** (see caveat) → the *only* accepted reason
   is a token-scope limitation, and it must be recorded with the exact query and
   the observed `total_count`/status. Vague "couldn't verify" is not an outcome.

Nothing in the panel's *rules* changes: no prefix guard, quoting, or rate
policy is loosened to make a probe pass.

## 7. Non-goals

- Not enabling calendar search or changing any search default.
- Not adding a request to the agent's 60s tick.
- Not a general audit of the local (instant) providers.
- Not extending either API's coverage (no new filters, no pagination).

## 8. Shell invariants (must hold at the end)

- `grep -rn "HostCoinSearchLoader\|HostStockSearchLoader\|HostGitHubPRLoader.search\|HostAzureDevOpsLoader.search\|HostGitCommitSearch\|HostEventSearch" native/DeckAgent native/DeckWidgets` stays empty.
- Search stays host-app-only, on user interaction; only a prefix reaches
  GitHub; every typed word stays a quoted term.
- `xcodegen generate` run for any new/edited test file; `DeckSharedTests` green
  with a non-zero executed count.

## 9. Acceptance criteria

1. `docs/planning/search-live-probes/probe.md` holds the measured evidence for
   A1–A9, B1–B5, C1–C4 (raw request + observed response/status).
2. Every contradiction is fixed (with a test) or documented with its reason.
3. `docs/planning/spotlight-remote-search/verification.md` and
   `docs/planning/spotlight-more-sources/verification.md` are updated: each
   relevant "NOT verified" bullet is resolved or narrowed with evidence.
4. `ROADMAP.md:1077-1079` is ticked (or narrowed to what genuinely remains).
5. `DeckSharedTests` green; both CLAUDE.md grep checks empty.

## 10. Known caveat (recorded, not hidden)

The GitHub credential is a **fine-grained `gho_` PAT scoped to two repos**
(`prbox-review-state/probe.md:56-75`), and the GitHub **search** API returned
`total_count: 0` for it in an earlier probe. So the GitHub PR probe may be
uninformative *by token*, not by code: A/B results that depend on broad search
visibility may be recordable only as "shape accepted, result set empty for this
token". The plan must probe a query within the token's reachable repos before
concluding the code is wrong.

## 11. Open questions

None outstanding — scope, method and credential source were confirmed
2026-10-11.

## 12. Self-critique resolutions

- 🔴 **The harness could measure itself, not the app.** A hand-built request
  that drifts from `WiqlClause`/`GitHubPRSearch`/`AzurePRSearch` would invent a
  contradiction. Fixed in §3: builders' output is used verbatim, P0 auth-gates
  the run first.
- 🔴 **A "fix" must never loosen a safety rule.** The pressure to make a probe
  pass could tempt weakening the prefix guard or the quoting. Fixed in §6
  (item 4) and §8: the rules are acceptance criteria, not tuning knobs.
- 🟡 **A dead token would look like a code bug.** Fixed by the P0 auth gate.
- 🟡 **"Leave it open" could close nothing.** Fixed in §6 item 4: only a
  token-scope limitation, with the query and `total_count` recorded.
- 🟡 **This is a non-widget task,** so the widget checklist (front face,
  back face, refresh cadence) does not apply; the applicable sections are data
  shape, failure states and shell fit. Stated here rather than left implicit.
- 🟡 **Azure throttling could corrupt a latency reading.** A5/A8 latency is
  indicative only; probes are sequenced, not burst, and no throttling figure is
  quoted as a benchmark.
