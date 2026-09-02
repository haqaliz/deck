# Probe — prbox-review-state (2026-09-02)

Live measurements against the real APIs, using the configured PRBox
credentials (GitHub account `7f5be0ef…` = fine-grained `gho_` PAT as
`haqaliz`; Azure `ForesightAnalytics`, project `ForesightManifold`, PAT
owner aliz GUID `5d48bc9c-…`).

## Findings

### 1. Azure costs zero extra requests — confirmed live

The `…/{project}/_apis/git/pullrequests?searchCriteria.{creator,reviewer}Id=…&api-version=7.1`
payload the loader already parses embeds `reviewers[]` with `vote` values:

```
PR 4524 (authored): reviewers=2  [('MohammadReza', 5), ('javad', 10)]
PR 4397 (authored): reviewers=2  [('MohammadReza', 0), ('aliz', 10)]
PR 4396 (authored): reviewers=2  [('MohammadReza', 0), ('aliz', 10)]
PR 3591 (authored): reviewers=0  []
PR 2509 (authored): reviewers=1  [('MohammadReza', 0)]
```

Observed votes: `0`, `+5` (approved w/ suggestions), `+10` (approved).
Negative votes (`-5` waiting-for-author, `-10` rejected) are not present in
this sample; the existing hand-built `azure_prs_votes.json` fixture already
covers them.

**Two design consequences, both measured:**
- **Exclude the PAT owner from the aggregation.** PR 4397/4396 carry the
  owner's own `+10`; an authored row must not read as "approved" because the
  author approved their own PR. Excluding `me` leaves 4397 as "MohammadReza
  hasn't voted" → no-state, which is the honest signal.
- The `reviewerId` query returns the author's own PRs too (the creator is a
  reviewer of record with `vote: 0`), which is why the existing
  `vote == 0` review-queue filter and the `.authored` dedup rule exist. The
  state glyph is orthogonal to both — it aggregates **other** reviewers.

### 2. GitHub is one request per PR — measured cost is fine with fan-out

`GET /repos/{owner}/{repo}/pulls/{n}/reviews`, six PRs (`haqaliz/deck`):

| | serial | concurrent |
|---|---|---|
| 6 PRs | **6.31s** (~1.0–1.1s each) | **1.09s** |

Against a 60s tick, serial is 10% of the budget and concurrent is ~2%.
Rate impact: 6 calls/tick → ~360/hr vs the 5000/hr core budget (search's
30/min is untouched — reviews are not search calls). `rate-left` stayed
above 4980 throughout. The 2B payloads (no reviews) confirm the cost scales
with rows shown, not repo size.

**Concurrent fan-out is mandatory** — the same measured ratio as ShipBox
(9.4s → 2.1s), and the codebase's `withThrowingTaskGroup` precedent applies
directly (`HostAzurePRLoader.inParallel`).

### 3. No live GitHub PR with reviews was observable — parser gets a hand-built fixture

The token's fine-grained scope reaches exactly two repos (`haqaliz/dev`,
`haqaliz/deck`), and every deck PR (42–47) was merged with **zero reviews**
(empty `[]` arrays, 2B payloads). So the non-empty payload shape cannot be
captured live from this token. The parser will be pinned against a
hand-built fixture on the documented shape — the same approach
`azure_prs_votes.json` already takes ("hand-built on the same shape to cover
the vote matrix"). Documented shape: `[{user: {login}, state,
submitted_at}]` with `state ∈ APPROVED | CHANGES_REQUESTED | COMMENTED |
DISMISSED | PENDING`, one entry per submitted review (not per user).

### 4. Side finding: GitHub search returns `total=0` for this token

Both PRBox queries (`author:@me`, `review-requested:@me`) return 200 with
`total_count: 0` and 79B payloads — correct behavior for a fine-grained
token whose two granted repos have no open PRs. PRBox's GitHub half is
genuinely empty on the dev machine; the review-state feature must (and
does) degrade to "no rows → no per-PR fetches" without special handling.
Not a regression and not in scope.

### 5. Latency context

Search ~1.1–1.3s, `/user` ~1.0s, Azure connectionData ~0.7–1.0s, Azure PR
query ~0.75s (19.4KB payload for 5 rows). A concurrent review-state pass
adds ~1.1s worst case to the tick, in parallel with the existing fetches —
the agent's tick stays well under the 240s limit and the 60s cadence.

## Open items the probe cannot settle

- The latest-review-per-user aggregation and the CHANGES_REQUESTED-over-
  APPROVED precedence are GitHub's own documented rules (mirrored by the
  PR page's decision box); they'll be unit-pinned, not live-verified.
- Whether Azure's `+5` should fold into "approved": yes — the review
  queue's purpose is prioritization, and `+5` is an approval with
  suggestions. Mixed votes (any negative) fold to "changes requested",
  matching GitHub's precedence.