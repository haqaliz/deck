# PRBox Review State — PRD

**Slug:** `prbox-review-state` · **Type:** `feat` · **Branch:** `feat/prbox-review-state/aliz`
**Inputs:** `docs/planning/_card/issue.md`, `_card/understanding.md`, `probe.md`
**Closes:** `ROADMAP.md:193` (PRBox open follow-up), `docs/planning/prbox/prd.md:255`
(the PRD's first non-goal).

## 1. The ask, in one sentence

Add a **coarse review-state glyph** to each PRBox row — approved /
changes-requested / no-one-voted — so the queue is prioritizable at a glance,
with a settings toggle to hide it, at zero extra Azure cost and a bounded,
fan-out GitHub cost.

## 2. Front face (what changes)

The row shape gains one element between the title and the age:

```
● GH  deck #41          Review queue widget        ✓     2h
● AZ  manifold #4397    Task 7792: Add Xcelerate…  ✗    10d
● GH  deck #38          wip: agent cadence · DRAFT       2d
```

- **`✓`** (`checkmark.circle.fill`, ~10pt, `RGBA.systemGreen`) — someone other
  than you has approved; no one is asking for changes.
- **`✗`** (`xmark.circle.fill`, ~10pt, `RGBA.systemRed`) — someone other than
  you is asking for changes (a rejection folds in too).
- **nothing** — no substantive review yet (only comments, pending/dismissed
  reviews, or nobody voted). This is also what a row renders when its state is
  unknown (see §5).

Fixed colors, **no new settings colors**: green/red are already in the palette
(MarketBox thresholds, NetBox thresholds) and the glyph must not compete with
the role dot. The state is orthogonal to the role dot; both render.

**Both roles get the glyph.** A MINE row that someone wants changes on is the
highest-priority row in the queue; a REVIEW row that is already approved tells
you the hard review is the one with the ✗.

**Small face:** no rows, so no glyph — unchanged.

## 3. Back face (settings)

One toggle in the existing **Queue** section of the PRBox tab:

- **"Show review state"** — `PRBoxSettings.showReviewState`, **default ON**.

When off, the face hides every glyph **and** the GitHub loader skips the
per-PR fetches (don't pay the rate budget for a feature you hid). Azure costs
nothing either way — its votes ride the existing payload — but the face still
gates on the setting.

## 4. Data source (both providers, measured)

**Azure — zero extra requests** (probe §1). `reviewers[]` with `vote` is
already in the `pullrequests` payload `AzurePRParser` parses. Votes: `+5`,
`+10` = approved; `-5`, `-10` = changes requested; `0` = no vote. The PAT
owner's own entry is **excluded** — an authored row must not read as approved
because the author voted on their own PR (measured: PR 4397/4396 carry the
owner's own `+10`).

**GitHub — one request per PR, fan-out, capped** (probe §2). `GET
/repos/{owner}/{repo}/pulls/{n}/reviews` per row. Measured: 6 PRs = 6.31s
serial, **1.09s concurrent** — so `withThrowingTaskGroup`, the ShipBox/
azure-multi-project precedent. Rate impact: ≤ 2 + `prCount` calls/tick
(~840/hr at `prCount` 12) against the 5000/hr core budget; the 30/min search
budget is untouched (reviews are not search).

**Row cap (pure policy).** Review state is fetched only for the provider's own
newest `prCount` rows (by creation date, pre-merge) — the rows that can
render. `prCount` is the honest bound: the merged face shows at most
`prCount` rows, and a provider cannot know the other's rows pre-merge.

**Aggregation (pure, both providers).** The row's state is the **latest
substantive review from each distinct reviewer**, folded:
- **GitHub: latest-per-user among *substantive* reviews only** — APPROVED and
  CHANGES_REQUESTED are the only states that count; COMMENTED, PENDING and
  DISMISSED never do (a dismissed approval is not an approval, and a pending
  review is not a submitted one — this is GitHub's own decision logic). Ties
  on `submitted_at` break by array order, so the fold is deterministic.
  - any reviewer's latest substantive review is CHANGES_REQUESTED →
    `.changesRequested` (CHANGES_REQUESTED outranks APPROVED);
  - else any reviewer's latest is APPROVED → `.approved`;
  - else (no substantive reviews) → nil.
- **Azure: any negative vote (−5, −10) → `.changesRequested`** (mixed folds
  negative, mirroring GitHub's precedence); else any vote ≥ 5 → `.approved`;
  else → nil.
- No `/user` call needed: a review-requested row cannot carry your own review
  (GitHub drops you from the queue once you review), and GitHub refuses
  self-approval, so APPROVED/CHANGES_REQUESTED on an authored row is by
  definition someone else.

**Cadence:** rides the existing 60s agent tick; the per-PR pass runs inside
`HostGitHubPRLoader.fetch` in parallel with everything else.

## 5. Failure behavior

- **A per-PR review fetch fails (transport, 404, scope)** → that row keeps no
  glyph; the queue still renders; the tick does not fail; the chip says
  nothing new (the queue fetch itself succeeded). Rows are honest without a
  prioritization aid. A wholesale failure therefore reads as "no one has
  voted" — a white lie only in the failure case, bounded per row, and the
  agent-level staleness/chip machinery already reports a broken agent.
- **Snapshot from an older build / a provider without state** → `reviewState`
  decodes absent → no glyph. Tolerant, one field.
- **Provider half fails** → unchanged: the other half renders with its own
  state (the `PRSnapshotBuilder` union behavior is untouched — state rides the
  rows).

## 6. Shell fit

Copies the proven PRBox shell: rows, chip, per-provider keys, gate, builder.
No new snapshot surface beyond one optional field on `PullRequestItem`; no
shell invariant touched. The only new mechanism is the GitHub per-PR fan-out,
which reuses the `withThrowingTaskGroup` pattern already in the codebase
(`HostAzurePRLoader.inParallel`). No Charts anywhere near the face.

## 7. Non-goals

- No counts ("2✓ 1✗"), no reviewer names, no comment counts, no CI status
  (that is ShipBox), no merge-conflict state.
- No glyph on the small face (no rows).
- No new colors in settings; no state column/section.
- No `/user` identity call for the GitHub half (unnecessary, §4).
- No change to the Azure review-queue filter (`vote == 0`) — the glyph is
  other reviewers' state, the filter is your own.

## 8. Tests (XCTest, `DeckSharedTests`)

- **`GitHubReviewParser`** (new, hand-built fixture `github_pr_reviews.json` —
  the probe could not capture a non-empty live payload; the documented shape
  is pinned, same approach as `azure_prs_votes.json`): state folding,
  latest-per-user, CHANGES_REQUESTED-over-APPROVED, DISMISSED/PENDING ignored,
  empty → nil, malformed → nil.
- **`AzurePRParser` state**: +5/+10 → approved; -5/-10 → changes requested;
  mixed → changes requested; owner's own vote excluded; only-owner → nil;
  empty reviewers → nil. Extends the existing vote-matrix tests.
- **Cap policy**: `GitHubReviewStateCap` limits the per-provider probe set to
  the newest `prCount` rows.
- **Decode**: `PullRequestItem` with absent `reviewState` decodes nil;
  round-trip with a state; a snapshot written before the field decodes whole.
- **Settings**: `showReviewState` defaults on; toggle wiring decodes.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Row width: glyph + DRAFT tag + long title on the 3-row medium face | The glyph is ~10pt before the right-aligned age; titles truncate first. Verification must eyeball medium with long titles + drafts |
| Fine-grained token without pull-request read → reviews endpoint 404s per PR | Fail-open (§5); rows render without glyphs; the queue itself is unaffected |
| Per-PR fan-out pushes the tick past 60s | Measured 1.09s for 6 concurrent; 10s per-request timeout bounds the worst case; parallel with existing fetches |
| `prCount = 12` rate pressure | ≤ 14 calls/tick ≈ 840/hr vs 5000/hr; toggle-off skips the fetches entirely |
| Glyph misleads when state is unknown (fetch failed) | Documented white lie, bounded per row; setting can hide it |
| Azure folding mismatches GitHub's precedence | Both fold to the same two states; the mixed-vote case folds negative on both |
| App and agent call sites drift | The `showReviewState` flag must gate the fetch in **both** `DeckApp.refreshPRBox` and `DeckAgent/main.swift` — the repo convention is line-for-line; the plan makes it a checklist item |

## 10. Open questions

None — interview answered (coarse glyph, probe-first, toggle default ON) and
the probe settled the cost questions. The one honest limitation is recorded
(§8): the non-empty GitHub payload shape is unit-pinned from documentation,
not live capture, because the dev token's two granted repos have no reviewed
PRs.