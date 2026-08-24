# PRBox — live API probe (2026-08-24)

Read-only calls with the PATs already in `settings.json`
(GitHub `haqaliz`, Azure `ForesightAnalytics/ForesightManifold`).

## 🔴 Azure DevOps silently ignores an invalid `creatorId` / `reviewerId`

The headline finding, and the twin of TaskBox's WIQL bug.

```
GET {org}/{project}/_apis/git/pullrequests?searchCriteria.status=active            → count 6
  …&searchCriteria.creatorId=@me                                                   → count 6   ← HTTP 200, UNFILTERED
  …&searchCriteria.creatorId=00000000-0000-0000-0000-000000000001                  → count 0
```

There is **no `@Me` macro** for the Git PR API (unlike WIQL, which has one). A
non-GUID value is not rejected — it returns **200 with every active PR in the
project**. A well-formed but unknown GUID correctly returns 0.

**Consequence for the design:** the Azure loader must resolve the PAT owner's
identity GUID *first* and must **fail the fetch** if it cannot, never fall back
to an unfiltered query. Otherwise PRBox renders the whole team's pull requests
and looks perfectly healthy doing it.

## Identity resolution works

```
GET {org}/_apis/connectionData?api-version=7.1-preview
→ authenticatedUser.id = 5d48bc9c-…  (= authorizedUser.id), providerDisplayName "Ali Haqiqi"
```

One extra call per tick, cacheable — the GUID only changes if the PAT's owner
changes.

## Project-level query spans every repo — no fan-out needed

One page of 5 returned PRs from **three different repositories** (`manifold`,
`manifold-swa`, `manifold-validation-swa`). So one call per role, not one per
repo — which also keeps the request count flat.

## 🟡 Azure PRs carry no "updated" timestamp

Payload keys: `codeReviewId, createdBy, creationDate, description, isDraft,
lastMergeCommit, lastMergeSourceCommit, lastMergeTargetCommit, mergeId,
mergeStatus, pullRequestId, repository, reviewers, sourceRefName, status,
supportsIterations, targetRefName, title, url`.

**There is no `updatedAt`/`changedDate`.** GitHub gives both `created_at` and
`updated_at`; Azure gives only `creationDate`. A mixed list sorted by "last
activity" is therefore not possible without a per-PR extra call. **Sort both
providers by creation date** so one key means the same thing in both halves.

## 🟡 "Awaiting my review" means different things per provider

`searchCriteria.reviewerId=<me>` returns PRs where the user is *a reviewer*,
including ones already voted on — the sample PR shows `aliz vote 10`
(approved). GitHub's `review-requested:@me` drops a PR once the review is
submitted. To make one list mean one thing, filter Azure results to
`reviewers[me].vote == 0`.

Vote scale: `10` approved · `5` approved with suggestions · `0` no vote ·
`-5` waiting for author · `-10` rejected.

## 🟡 No web URL in the Azure payload

`url` is the REST URL and `repository.webUrl` is absent, so a browser link has
to be built: `https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}`.
Only matters if `widgetURL` deep links are in scope (they are a TaskBox
follow-up, not shipped).

## GitHub side: no surprises

```
GET /user                                        → login haqaliz
GET /search/issues?q=is:pr+is:open+author:@me            → total 2
GET /search/issues?q=is:pr+is:open+review-requested:@me  → total 0
GET /rate_limit → search: limit 30/min · core: 5000/hr
```

- `@me` **does** resolve server-side for GitHub search — no identity call needed.
- Works with and without `advanced_search=true`; no `Deprecation`/`Sunset`
  header came back on either form.
- Items carry `draft`, `updated_at`, `created_at`, `html_url`, `repository_url`,
  `user.login` and a `pull_request` sub-object (`merged_at`, `html_url`).
  Review *state* is **not** in the search payload — showing "2 approvals" would
  need a per-PR call, i.e. fan-out. Out of scope for slice 1.
- 2 searches per 60s tick against a 30/min budget = 2/30. Safe; per-repo
  fan-out would not be.

## Request budget per tick (settled)

| Provider | Calls | Notes |
|---|---|---|
| GitHub | 2 | authored + review-requested, `/search/issues` |
| Azure | 3 | `connectionData` (cacheable → 2 after first) + created + reviewing |
