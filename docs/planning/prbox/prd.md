# PRBox — PRD

**Slug:** `prbox` · **Type:** `feat` · **Branch:** `feat/prbox/aliz`
**Inputs:** `docs/planning/_card/issue.md`, `understanding.md`, `probe.md`

## 1. The ask, in one sentence

A thirteenth widget showing **one review queue mixed from two providers** —
the pull requests you opened and the ones waiting on your review, across
**GitHub** and **Azure DevOps Git** — configured from per-provider sub-tabs
that each carry their own include toggle and credentials.

## 2. Front face

Three sizes, same visual language as ShipBox/TaskBox (rounded system fonts,
monospaced digits, colored-dot rows, section title tracked 1pt).

**Header (all sizes)** — the two numbers that make it a queue:

```
PRBOX                       ⌁ 14:32
  ●  3  MINE      ●  5  REVIEW
```

`MINE` = open PRs you authored. `REVIEW` = PRs awaiting your review. Counts are
the **union across enabled providers**, and are honest about a half-failure
(§7).

**Small:** header + the two counts only. No list — three rows of truncated
titles at 158pt is unreadable, and the counts are the glanceable fact.

**Medium:** header + up to 3 rows. **Large:** header + up to 8 rows
(`prCount`, one global cap, default 6, range 3…12).

**Row shape** — one line, provider-tagged:

```
● GH  deck #41          Review queue widget          2h
● AZ  manifold #4397    Task 7792: Add Xcelerate…    10d
```

- **Dot** = role: `MINE` color (default blue) or `REVIEW` color (default
  orange). Role is the thing you act on, so it gets the color.
- **`GH` / `AZ`** = provider, a 2-character monospaced tag in secondary. *Not a
  logo:* neither GitHub nor Azure DevOps has an SF Symbol, and vendoring brand
  marks into an Apache-2.0 repo is a trademark question this widget does not
  need to answer.
- **`repo #number`** — repo is the short name (`deck`, `manifold`), truncated
  before the title is.
- **Title** truncates with a tail ellipsis.
- **Age** = time since creation, `2h` / `10d` (§4 explains why creation).
- A draft PR renders its title in secondary with a `DRAFT` tag.

**Sort:** newest first by **creation date**, one key for both providers (§4).
Ties broken by provider then number, so the order is stable between ticks.

**Empty states:**
- No provider enabled, or an enabled provider missing credentials →
  "Not configured" + the fetch-status chip naming what is missing.
- Enabled and configured, nothing to show → "No open PRs" — a real answer, and
  visually distinct from a failure.

## 3. Back face (settings)

The PRBox tab is a `Form` whose top section is a **provider picker**
(segmented: GitHub · Azure DevOps), switching the section below it. Deck has no
sub-tab precedent yet; a segmented control inside the Form is the least
un-native way to get one and keeps the 640×500 window unchanged.

**GitHub sub-tab**
| Control | Default |
|---|---|
| `Toggle` Include GitHub | **off** |
| `SecureField` GitHub token | "" |
| `TextField` Scope (optional) — e.g. `org:acme` | "" |
| Caption: token is sent only to api.github.com over TLS | — |
| `FetchStatusCaption(source: .prboxGitHub)` | — |

**Azure DevOps sub-tab**
| Control | Default |
|---|---|
| `Toggle` Include Azure DevOps | **off** |
| `TextField` Organization | "" |
| `TextField` Project | "" |
| `SecureField` Personal access token | "" |
| Caption: token is sent only to dev.azure.com over TLS; read-only **Code (Read)** is enough | — |
| `FetchStatusCaption(source: .prboxAzure)` | — |

**Shared section (below the picker)**
| Control | Default |
|---|---|
| `Toggle` Show list | on |
| `Stepper` PR count | 6 (3…12) |
| `ColorPicker` Mine | blue |
| `ColorPicker` Review | orange |

Both providers default **off**: a widget added from the gallery must not fire
network requests with no credentials, and "not configured" is the correct first
render.

Tokens live in **PRBox's own fields** — no coupling to `ShipBoxSettings` or
`TaskBoxSettings`. Every Deck widget owns its settings today; a shared
credentials section would be a schema change plus a migration carrying already-
pasted tokens, for the sake of one paste.

## 4. Data source

Network on both sides, so this is the **agent-pumped path**, unchanged:
`DeckAgent` (60s) → `prbox.json` in the widget container → the widget renders.
No new entitlement, no sandbox question.

### GitHub — 2 calls/tick

```
GET /search/issues?q=is:pr+is:open+author:@me[+<scope>]&per_page=<cap>
GET /search/issues?q=is:pr+is:open+review-requested:@me[+<scope>]&per_page=<cap>
```

`@me` resolves server-side, so no identity call. Verified live: 2 authored, 0
review-requested, and `/rate_limit` reports **search 30/min** — 2 per 60s tick
is 2/30. Per-repo fan-out is what that budget forbids, and nothing here does it.

Fields used: `number`, `title`, `draft`, `created_at`, `html_url`,
`repository_url` (last path component = repo name).

### Azure DevOps — 3 calls/tick (2 after the first)

```
GET {org}/_apis/connectionData                                  → authenticatedUser.id
GET {org}/{project}/_apis/git/pullrequests?searchCriteria.status=active
      &searchCriteria.creatorId=<guid>
GET  …&searchCriteria.reviewerId=<guid>
```

Basic auth with `":"+PAT` base64, reusing `AzureTarget.normalise` and
`AzureDate` from `Shared/AzureDevOpsLoader.swift`.

**🔴 The GUID is load-bearing, and this is the one non-obvious rule in the
whole widget.** There is no `@Me` macro for the Git PR API. `creatorId=@me`
returns **HTTP 200 with every active PR in the project** — the probe measured 6
with no criteria and the same 6 with `@me`, while a well-formed unknown GUID
correctly returned 0. So:

> If `connectionData` fails or yields no id, the Azure fetch **fails** and
> records `.authOrTarget`. It must never fall back to an unfiltered query.

This is the twin of TaskBox's WIQL discovery: a project-scoped *URL* does not
filter, and the API says 200 either way.

The project-level endpoint **spans every repo in the project** (one probe page
returned `manifold`, `manifold-swa`, `manifold-validation-swa`), so one call
per role covers the project — no per-repo fan-out.

**Reviewer results are filtered to `vote == 0`.** `reviewerId` returns PRs you
are a reviewer on *including ones you already voted on* (the sample showed
`aliz vote 10`, approved), whereas GitHub drops a PR from `review-requested`
once you review it. Without the filter the same list would mean two different
things in its two halves and REVIEW would over-count.

**Sort key is creation date for both providers.** The Azure payload has **no
`updatedAt`** — keys are `codeReviewId, createdBy, creationDate, description,
isDraft, lastMergeCommit, lastMergeSourceCommit, lastMergeTargetCommit,
mergeId, mergeStatus, pullRequestId, repository, reviewers, sourceRefName,
status, supportsIterations, targetRefName, title, url`. Sorting GitHub by
`updated_at` and Azure by `creationDate` would sink a freshly-pushed Azure PR
below a stale GitHub one and read as a bug; fetching per-PR update times is the
fan-out the rate budget forbids.

### Model (provider-agnostic from day one)

Following `TaskItem`'s precedent (`Shared/TaskBoxSnapshot.swift:19`):

```swift
enum PRProvider: String, Codable { case github, azureDevOps, unknown }
enum PRRole: String, Codable     { case authored, reviewing }

struct PullRequestItem: Codable, Equatable {
    var id: String            // "gh:owner/repo#41" — String so GitLab/Bitbucket fit
    var number: Int
    var title: String
    var repo: String          // short name
    var role: PRRole
    var provider: PRProvider
    var isDraft: Bool
    var createdAt: Date
    var url: String
}

struct PRBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    var authoredCount: Int    // uncapped totals, so the header can exceed the rows
    var reviewingCount: Int
    var pullRequests: [PullRequestItem]   // pre-sorted; the widget renders, it does not decide
}
```

Tolerant decode on `provider` and `role` (unknown → `.unknown` / drop the row)
so a snapshot from a newer agent still renders.

A PR that is **both** authored by you and awaiting your review dedupes to one
row with `role = .authored` — you cannot review your own PR, and two identical
rows would read as a bug.

## 5. Shell fit

Reused unchanged: `HostGitHubLoader`'s request shape, `AzureTarget`,
`AzureDate`, `FetchClassifier.outcome(for:)` (**already handles both
`GitHubError` and `AzureDevOpsError`** — `Shared/FetchStatus.swift:81,99`),
`FetchStatusStore`, `FetchChip`, `FetchStatusCaption`, `AtomicFile`,
`TimelineReloadPolicy.after(60s)`, the ShipBox provider/entry skeleton.

**No CLAUDE.md invariant is touched**: no new data path, no settings UI inside
a widget, no sub-60s cadence, no subprocess, one timeline entry.

Two enum widenings are unavoidable and are the only cross-cutting edits:

- `FetchSource` gains **`prboxGitHub` and `prboxAzure`** (two, not one — each
  provider sub-tab needs its own caption under its own fields). The `reason`
  and `hint` switches (`FetchStatus.swift:156,165,192,204,212`) are exhaustive
  over `FetchSource`, so both cases need all four strings each.
- `DeckWidget` gains `prbox` (title "PRBox", symbol
  `arrow.trianglehead.pull` — falls back to `arrow.triangle.pull` if the
  former is unavailable on macOS 15).

**Version bump required**: `1.20`/`20` → `1.21`/`21` in all three
`project.yml` targets, or the Widget Center reuses its cached descriptor set
and PRBox never appears.

## 6. Refresh cadence

60s, matching every other agent-pumped widget. A snapshot that exists is always
rendered with its timestamp — data is never blanked for age (the M4 behaviour
change); the >5min age hint and the chip carry the honesty.

## 7. Failure behaviour — the two-provider rule

The face has room for **one** chip line. The rule:

| Situation | Chip |
|---|---|
| Both providers fine | none |
| One enabled provider failed | `"GitHub: check token"` — **named**, because the counts silently exclude that provider's PRs |
| Both failed | the GitHub line, with `"+1 more"` appended |
| Neither enabled | `"Not configured"` |

Naming the provider is the point: a REVIEW count of 2 when GitHub is down is
not wrong, it is partial, and only the chip can say so.

Per-provider statuses are stored under their own `FetchSource` keys, so a
GitHub failure never clears an Azure success and each settings sub-tab shows
its own sentence under its own fields.

## 8. Non-goals

- **No review state / approval counts.** The GitHub search payload has no
  review data; getting it means one call per PR — the fan-out the 30/min search
  budget forbids.
- ~~**No deep links** (`widgetURL`).~~ **Added after review** — the URL was
  already in the model for both providers (GitHub's `html_url`, Azure's
  constructed `…/_git/{repo}/pullrequest/{id}`), so rows became `Link`s and the
  small face got a `widgetURL` to the top pull request. PRBox is the first Deck
  widget to deep-link at all. `PRFormatting.destination(for:)` restricts it to
  http(s) with a host: the snapshot is data, not instruction, so a row opens a
  pull request in a browser and nothing else.

  **Shipping this needed two app-side changes, found by testing the click.**
  WidgetKit delivers the URL to the *containing app*, so the first build
  launched Deck, dropped the URL and left a new settings window behind on every
  click — the browser never opened. `DeckAppDelegate` now forwards the URL to
  `NSWorkspace` and, when the launch existed only to carry that click, quits
  without showing a window; `.handlesExternalEvents(matching: [])` stops
  SwiftUI manufacturing a second settings window when Deck is already open.
  Measured after the fix: cold click → 0 Deck windows, page opens; click with
  settings open → window count stays 1, page opens.
- **No multi-project / multi-org.** One `org/project` for Azure, matching
  TaskBox; the same follow-up as ShipBox multi-repo.
- No CI status per PR (that is ShipBox), no merge-conflict state, no comment
  counts, no assigned-but-not-requested PRs.
- No GitLab / Bitbucket — `PRProvider` is where they would go.
- No Keychain storage; `settings.json` is 0600 and Keychain is a tracked M7
  item for all three existing tokens at once.

## 9. Tests (XCTest, `DeckSharedTests`)

Pure logic only — the loaders take injected `Data`:

- `GitHubPRParser`: item → `PullRequestItem`, repo name from `repository_url`,
  `draft` honored, missing/garbage fields drop the row not the list.
- `AzurePRParser`: PR → item, **`vote == 0` filter** (fixture with votes 10, 0,
  -5 → one row), `isDraft`, `AzureDate` fractional-second parsing.
- `ConnectionDataParser`: id extracted; **absent id → nil**, and the loader
  turns nil into a thrown error (the unfiltered-query guard, pinned by a test).
- `PRFormatting.sorted`: created-date descending, stable tie-break, dedupe of
  authored+reviewing.
- `PRBoxSnapshot` tolerant decode: unknown `provider`/`role`.
- `FetchStatus` reason/hint totality for the two new sources.

⚠️ xcodegen enumerates files at generation time — a new test file needs
`xcodegen generate` or it is silently not compiled and the suite still reports
success.

## 10. Open questions (for the review gate)

1. **GitHub scope.** `author:@me` spans every repo the token can see — the
   probe surfaced two PRs from 2022 in personal repos. Proposed: an optional
   free-text Scope field appended to the query (`org:acme`, `repo:owner/name`),
   empty = everything. Accept, or hard-scope to an org field?
2. **Drafts.** Proposed: shown, marked `DRAFT`. Alternative: a "hide drafts"
   toggle per provider (more settings in a tab that already has sub-tabs).
3. **Small face.** Proposed: counts only, no rows. Alternative: one row for the
   oldest PR awaiting your review (the "nagging" face).
4. **Symbol availability.** `arrow.trianglehead.pull` needs checking on macOS
   15; fallback named above.
