# PRD — Azure DevOps multi-project (TaskBox + PRBox)

Slug: `azure-multi-project` · Branch: `feat/azure-multi-project/aliz` · 2026-08-28

## 1. The ask

TaskBox and PRBox each show Azure DevOps work from **exactly one project**. Let
one Azure account cover **up to five projects in its organization**, so a user
whose work spans projects sees all of it in one widget.

Both widgets list this as an open follow-up (`ROADMAP.md:165`, `:193`).
TaskBox's own live probe measured **67 items across three projects against the
25 in the configured one** (`ROADMAP.md:151`) — the single-project scope is
correct today and hides most of this org's work.

**Decided in the interview (2026-08-28):**

| Question | Decision |
|---|---|
| Model | **Projects list on the account.** `CredentialAccount.project` → `projects: [String]`. One PAT, one keychain item, one org. |
| Picker | **Discovered slot pickers, cap 5**, from `{org}/_apis/projects`. |
| TaskBox header | **Org name, and the sprint chip only when exactly one project is configured.** |
| Project on rows | **Both widgets can show it, hidden by default**, user-toggled. |

## 2. Why this shape is cheap (measured against the code, not assumed)

Three of the four Azure calls are **organization**-scoped, not project-scoped,
so cost is sublinear in project count:

| Call | Scope | Cost for N projects |
|---|---|---|
| `_apis/wit/wiql` | project (`projectBase`) | **N** |
| `_apis/wit/workitemsbatch` | **org** (`orgBase`, `AzureDevOpsLoader.swift:281`) | **1** (merged ids) |
| `_apis/work/teamsettings/iterations` | project | N, and **0** when N > 1 (no sprint chip) |
| `_apis/connectionData` | **org** (`:490`) | **1** |
| `_apis/git/pullrequests` | project (`projectBase`) | **2N** (authored + reviewing) |

TaskBox at 5 projects: 5 WIQL + 1 batch = **6 requests** (vs 3 today).
PRBox at 5 projects: 1 identity + 10 = **11 requests** (vs 3 today).

**Fan out concurrently.** `URLSession.timeoutInterval` is per request; five
sources measured **9.4s serially against 2.1s concurrently** (CLAUDE.md), and
11 serial requests at a 10s timeout blow past the 60s agent cadence in the worst
case. Both loaders use `withThrowingTaskGroup`, following
`HostGitHubLoader.inParallel` — the codebase's only existing precedent.

## 3. Correctness bugs that multi-project introduces

These are not polish; each is a wrong face if unaddressed.

**3.1 🔴 PRBox row ids collide across projects.**
`PullRequestItem.id` is `"azureDevOps:\(repo)#\(number)"` (`:407`). PR numbers
are **per-repo** and repo names repeat across projects in one org, so two `api`
repos each with PR #12 produce one id — a duplicate `ForEach` id and a silently
dropped row. **Fix:** the id becomes
`"azureDevOps:\(project)/\(repo)#\(number)"`. Unconditional, regardless of the
row-display toggle.

**3.2 🔴 A merged batch deep-links every row into the wrong project.**
`WorkItemParser` builds `url` as `"\(target.projectBase)/_workitems/edit/\(id)"`
(`:194`). The `workitemsbatch` call is org-scoped and will now carry ids from
several projects, so one `target` cannot answer for all of them. **Fix:**
request `System.TeamProject` in the batch `fields` list and build each row's URL
from the item's own project. The field is load-bearing, not cosmetic.

**3.3 🟡 The 200-id cap becomes a fairness problem.**
`WiqlIdParser.idLimit = 200` is per call, and `workitemsbatch` accepts 200 ids
per request. Merging five projects' ids must cap **globally**. Naive
concatenation lets one busy project crowd out a quiet one — the per-repo fair
share that ShipBox left as an open follow-up (`ROADMAP.md:293`). **Fix:**
round-robin interleave the per-project id lists before truncating at 200, then
sort the resulting items by `changedAt` as today.

**3.4 🟡 A blanked legacy field must not come back.**
`TaskBoxSettings.organization/project` and `PRBoxSettings.azure.*`
(`DeckSettings.swift:807`, `:992`) are pre-accounts fields the credentials
migration blanks. `legacyCredential(for:)` maps them into the new shape as a
**one-element list**; nothing writes back to them.

## 4. Data model

### 4.1 `CredentialAccount` (`Shared/CredentialAccount.swift`)

```swift
var organization: String = ""
var projects: [String] = []          // was: var project: String = ""
```

On-disk migration, in the account's own tolerant `init(from:)`:
decode `projects` when present; otherwise decode the legacy `project` string
into a one-element list (empty string → empty list). Encode **only**
`projects` — CLAUDE.md's rule that a moved field must clear the old copy, or
the fallback keeps answering after the new control has taken over.

`AzureAccountProjects` (pure, unit-pinned) normalises a list: trim, drop empties,
de-duplicate **case-insensitively** keeping the first spelling (Azure treats
project names case-insensitively in URLs but displays them cased), cap at
`maxProjects = 5`.

### 4.2 `ResolvedCredential` / `gate` (`Shared/CredentialsMigration.swift:100`)

`project: String` → `projects: [String]`. The Azure branch of `gate` requires a
non-empty organization **and at least one** non-empty project after
normalisation; otherwise `.notConfigured`, exactly as today. `off` /
`notConfigured` / `unavailable` semantics are untouched.

### 4.3 Snapshots

`TaskItem` gains `var project: String?` — nil for rows written by an older
agent, and for a provider that has no such concept. `TaskBoxSnapshot` gains
`var note: String?` (partial-fetch wording, ShipBox's precedent).

`PullRequestItem` gains `var project: String?`. Both decode with
`decodeIfPresent`, so a snapshot written by the current agent still renders
after a downgrade.

## 5. Loader behaviour

### 5.1 TaskBox — `HostAzureDevOpsLoader.fetch(organization:projects:token:)`

1. Normalise to `[AzureTarget]` (one per project).
2. Concurrently, per target: WIQL (`[System.TeamProject] = @project` clause
   **stays** — a project-scoped URL does not filter, `ROADMAP.md:151`), and the
   current sprint **only when there is exactly one target**.
3. Interleave the id lists round-robin, truncate at 200.
4. One org-scoped `workitemsbatch` with `System.TeamProject` added to `fields`
   and `errorPolicy: omit` unchanged.
5. `totalCount` = sum of the per-project WIQL totals. `scope` = the org name
   when N > 1, today's `AzureTarget.scope` when N == 1.

**Partial failure:** a project whose WIQL fails is dropped, its projects' rows
are simply absent, and `note` says which one failed. The fetch throws **only
when every project failed** — MarketBox's "only fails when no row at all could
be priced" rule. A widget that blanks a working project because another one
404'd is worse than one that says so.

### 5.2 PRBox — `HostAzurePRLoader.fetch(organization:projects:token:cap:)`

One org-scoped `connectionData` identity call, still `requireIdentity` with
**no fallback** — an unparseable identity returns 200 and every active PR in the
project (`ROADMAP.md:193`), and that failure mode gets worse, not better, with
five projects. Then 2N concurrent role queries, each parsed with its own target
so `webURL` and the row id carry the right project. `vote == 0` filtering,
`$top=101` ceiling and creation-date sorting are unchanged; totals sum per role
and the capped flags OR together. Same partial-failure rule as 5.1.

### 5.3 Project discovery — `HostAzureProjectsLoader.list(organization:token:)`

`GET {org}/_apis/projects?api-version=7.1&$top=200`, host-app only, called from
the settings window — **never** from the agent tick. `AzureProjectsParser` is
pure and unit-pinned. Failure is non-blocking: the pickers fall back to free
text entry, because a PAT scoped to Work Items (Read) may not be able to list
projects and must not be locked out of configuring one.

## 6. Settings UI

**Credentials tab, Azure account editor** (`DeckApp.swift:1253`): the single
"Project" `TextField` becomes **five project slots**, each a picker over the
discovered list plus "None" — the ShipBox "Pick repos" / ClockBox / MarketBox
slot pattern. A "Refresh" affordance re-runs discovery; when discovery has not
succeeded, each slot degrades to a text field pre-filled with whatever is
stored, so an existing single-project account is never lost.

**TaskBox tab** and **PRBox → Azure DevOps sub-tab**: `Show project on rows`,
a toggle pinned right, **default off**. Off is the current face exactly.

Copy at `DeckApp.swift:2034` ("in that account's project only") is now wrong and
is reworded.

## 7. Face

Unchanged in every respect for a single-project account — that is the
regression bar.

**TaskBox.** Header left: `scope` (org name when N > 1). Header right: the
sprint chip only when N == 1; the fetch chip keeps outranking it. Rows
optionally carry the project name, in the same secondary style as the state.

**PRBox.** Rows optionally render `Project/repo` in place of `repo`. Row links
already resolve per item, so nothing changes in the deep-link path (http(s)
with a host, `DeckURLForwarding`).

## 8. Non-goals

- **Multi-org.** One account is one organization. Two orgs needs a slot that
  binds several accounts, which was interviewed and deliberately not chosen.
  Recorded as the natural next slice.
- **A general per-column visibility system** for widget rows. This ships one
  named toggle per widget, not a column framework.
- Custom WIQL, a third PR provider, review state / approval counts, per-project
  lane mappings (the lane map stays global — it is already editable text).
- Paging past 200 projects in discovery, or past the existing 101-PR ceiling.

## 9. Verification

- `DeckSharedTests` for every pure piece: `AzureAccountProjects` normalisation
  (trim/dedupe/cap), the account's `projects`/`project` decode migration and
  encode-clears-legacy, `gate` for zero/one/many projects, round-robin
  interleave + 200 cap, `WorkItemParser` reading `System.TeamProject` and
  building a per-item URL, `AzurePRParser` id containing the project,
  `AzureProjectsParser`, and the partial-failure rule (all-fail throws,
  some-fail notes).
- Live check against `ForesightAnalytics` with `ForesightManifold` + `Manifold`:
  item counts per project, no duplicate PRBox rows, correct per-row deep links.
- Single-project regression: a stored account with the legacy `project` string
  produces a byte-identical face.
- Build + install + re-add all three sizes from the gallery (CLAUDE.md).

## 10. Self-critique (2026-08-28)

Two gaps the first draft missed, now folded in, plus the risks that were
checked and found clear.

**🔴 C1 — the Verify cache would go stale on a project change.**
`CredentialIdentity`'s fingerprint is
`[token, organization, project, serverURL].joined(separator: "\0")`
(`Shared/CredentialVerification.swift:24`). It exists so a stored "Verified"
badge cannot outlive the thing it was checked against. With a list, a
fingerprint built from a single string would leave the badge standing after the
user adds or removes a project. **Fix:** the fingerprint joins the **normalised
project list** (order-independent — sort a lowercased copy for the hash only, so
re-ordering the five slots does not spuriously invalidate a good verification).

**🟡 C2 — `CredentialVerification.azure` reads `account.project` directly.**
`:131` passes `account.project.isEmpty ? "_" : account.project` into
`AzureTarget.normalise` purely to satisfy the signature — the probe itself hits
the **org-scoped** `connectionData`. **Fix:** pass the first normalised project
or `"_"`. **Decision: Verify stays organization-level.** Probing that all five
projects exist would cost five more calls in the settings window and would fail
a whole account over one typo'd slot; an unreachable project surfaces as a
per-project note on the face instead (§5.1).

**🟡 C3 — the host app has its own two call sites.**
`DeckApp.swift:318` and `:388` fetch TaskBox and PRBox for the settings
window's refresh, separately from `DeckAgent/main.swift:212` and `:281`. All
four move to the plural signature together; missing one leaves the app and the
agent disagreeing about scope, which reads as a widget that changes content when
you open settings.

**Checked and clear:**

- **Nothing in the widget extension reads `project`.** `grep -rn "\.project\|projects" native/DeckWidgets/` is empty, so this avoids the CLAUDE.md trap where a moved settings field silently breaks a face that reads it without a keychain. The extension only renders snapshots.
- **No new keychain item.** One account keeps one token; the id is untouched, so no token is stranded (CLAUDE.md: renaming an account id strands its token).
- **No new TCC grant, entitlement, agent or plist** — nothing in the SMAppService or notarization surface moves.
- **No Swift Charts** anywhere near these faces.
- **No timeline-size risk.** Row counts are capped as today (`prCount`, the task cap); this changes where rows come from, not how many.
- **Version bump not required** — no new widget, so the WidgetKit descriptor cache is not involved.

**Accepted risk:** `_apis/projects` has not been probed live against
`ForesightAnalytics`. Its shape (`value[].name`) is stable and documented, and
discovery failure is designed to be non-blocking (§5.3) — but the parser is
written against the documented shape rather than a captured payload, and the
first live run may need one correction. Probe it in phase 1 of the plan before
building the picker on top of it.
