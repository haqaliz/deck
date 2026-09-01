# Understanding — prbox-review-state

**Date:** 2026-09-02 · **Branch:** `feat/prbox-review-state/aliz` · **PRD:** pending

## What the work is really asking

PRBox rows currently carry `role` (authored / reviewing), `isDraft`, creation
date and a link — but **nothing about the PR's review progress**. The queue
can't be prioritized at a glance: an approved PR and a blocked one look alike.
The work adds a provider-agnostic **review state** per row so the queue is
prioritizable (approved / changes requested / no one has voted), closing the
recorded follow-up (`ROADMAP.md:193`, `docs/planning/prbox/prd.md:255`).

## The two providers are not symmetric — this shapes everything

| | GitHub | Azure DevOps |
|---|---|---|
| Review data location | Separate endpoint `GET /repos/{o}/{r}/pulls/{n}/reviews` — **one request per PR** | `reviewers[]` with `vote` is **already in the PR payload** the loader parses today (`AzureDevOpsLoader.swift:640`) — zero extra calls |
| Vote semantics | `state` per review: APPROVED / CHANGES_REQUESTED / COMMENTED / DISMISSED / PENDING; latest review per reviewer counts; CHANGES_REQUESTED outranks APPROVED | `vote` per reviewer: -10 rejected, -5 waiting for author, 0 no vote, +5 approved w/ suggestions, +10 approved; only my row's vote is filtered today (`isAwaitingVote`, `AzureDevOpsLoader.swift:639`) |
| My own review | You drop off `review-requested` once you review, so queue rows never carry my review; self-approval is impossible, so authored rows don't either | Same by construction: the `.reviewing` filter keeps only `vote == 0` rows; my vote on my own PR is irrelevant to others' state |

So the state shown is **other reviewers' aggregate**, never my own — which is
exactly the prioritization signal. The row's own role dot stays as-is; the new
glyph is a second, orthogonal signal.

## Files that change

- `native/Shared/PRBoxSnapshot.swift` — `PullRequestItem` gains a review-state
  field (tolerant decode, nil when absent — upgraded snapshots and providers
  that didn't fetch it); `HostGitHubPRLoader.fetch` fans out per-PR review
  fetches (new `withThrowingTaskGroup`, ShipBox precedent) capped to the rows
  that will render; a pure parser for the reviews payload.
- `native/Shared/AzureDevOpsLoader.swift` — `AzurePRParser.item(from:...)`
  derives the state from the already-present `reviewers` (exclude me, fold
  votes to a coarse state).
- `native/Shared/DeckSettings.swift` — `PRBoxSettings` gains a show toggle +
  colors if the face wants them (needs the settings tab too).
- `native/DeckWidgets/PRBoxWidget.swift` — per-row status glyph (no Charts —
  the widget-face Charts trap).
- `native/DeckAgent/main.swift` + `native/DeckApp/DeckApp.swift` — both call
  sites of `HostGitHubPRLoader.fetch` and `PRSnapshotBuilder.build` (signature
  or behavior change, e.g. the GitHub cap).
- Tests: new fixture for the GitHub reviews payload; extend
  `PRBoxGitHubTests`, `PRBoxAzureTests`, `PRBoxSnapshotTests`.
- `scripts/demo_data.py` (`demo-data.sh`) — sanitizes the PRBox snapshot;
  check whether the new field needs a fake value.

## Cost & rate-budget arithmetic (the PRD's recorded reason for cutting it)

- GitHub: 2 search calls + up to `prCount` review calls per tick, every 60s.
  `prCount` default 6 → 8 calls/min ≈ 480/hr, well inside the 5000/hr core
  budget. The 30/min search budget is untouched (reviews are not search).
- The real risk is **tick duration**: serial N×RTT; concurrent fan-out (~1 RTT)
  is the established fix (ShipBox: 9.4s serial → 2.1s concurrent).
- **Row cap policy:** fetch review state only for the provider's own rows that
  can render (newest `prCount` of that provider's list, pre-merge) — the merge
  happens after, so per-provider cap is the honest bound.

## Ambiguities to resolve in the PRD interview

1. **State granularity:** a coarse three-state glyph (approved / changes
   requested / none), counts ("2✓ / 1✗"), or both? Small face has no rows — is
   this medium/large only?
2. **Fail-open semantics:** a per-PR review fetch failing — row shows no glyph
   (fail-open, don't blank the queue) vs. provider-level note. Precedent says
   fail-open + MarketBox-style partial note.
3. **Settings surface:** show toggle (default on/off?), colors, or none
   (glyph fixed, colored by role colors)?
4. **Azure vote folding:** is +5/+10 both "approved" and -5/-10 both "changes
   requested"? Is a PR with approvals *and* rejections "changes requested"?
5. **DISMISSED / PENDING** on GitHub: excluded, presumably — confirm.
6. **Probe before PRD?** PRBox's own lesson: live-probe the reviews endpoint
   shape and real per-PR latency before freezing the design; Azure confirmed
   free from the existing payload (fixtures already carry `reviewers`).

## Shell invariants this must respect

- Snapshot is data, not instruction: new field tolerant, never changes the
  fallback behavior; provider half failing never blanks the other half.
- No Swift Charts in the widget face.
- Pure parsing + cap policy unit-pinned in `DeckSharedTests` (XCTest, fixtures).
- Both fetch call sites (agent + app) stay line-for-line.
- `xcodegen generate` after adding any new test file.
- No keychain/credentials changes — this rides the existing `.prboxGitHub` /
  `.prboxAzure` FetchSource keys and gates.