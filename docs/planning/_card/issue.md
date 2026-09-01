# Card — PRBox review state / approval counts

**Type:** feat · **Slug:** `prbox-review-state` · **Branch:** `feat/prbox-review-state/aliz`
**Source:** inline brief (`deck-next`, 2026-09-02). No GitHub issue.
**Follow-up from:** `ROADMAP.md:193` (PRBox entry — *"Open follow-ups: multi-org,
review state / approval counts (needs one request per PR), a third provider"*)
and `docs/planning/prbox/prd.md:255` (the PRD's first non-goal — *"No review
state / approval counts. The GitHub search payload has no review data; getting
it means one call per PR — the fan-out the 30/min search budget forbids."*)

## The brief

Add review state / approval counts to PRBox — the recorded follow-up at
ROADMAP.md:193 and prbox/prd.md:255. Each PR row gains an approval state
(approved / changes requested / not reviewed) so the review queue is
prioritizable at a glance; the snapshot stays provider-agnostic with one
optional field on `PullRequestItem`.

## What the work is (from deck-next's handoff)

1. Probe live first: measure real per-PR review-fetch volume and tick cost
   against the 60s cadence, for **both** providers.
2. GitHub: review state is one request per PR
   (`GET /repos/{owner}/{repo}/pulls/{n}/reviews`). Cap the probed rows and fan
   out concurrently (ShipBox precedent) so the core rate budget (5000/hr) and
   tick duration hold.
3. Azure: check whether the embedded `reviewers` votes (prbox/prd.md:163 lists
   `reviewers` in the response payload) cover it with **zero extra calls** —
   confirm in the probe before deciding the face.
4. Keep parsing + the row-cap policy pure and unit-pinned in DeckSharedTests.
5. Render as a per-row status glyph — no Charts in the widget face.

## Caveats to design around

- **Per-PR request cost is the reason the PRD cut it.** An uncapped set against
  the 60s tick threatens both GitHub's 5000/hr core rate limit and the tick
  duration (serial would be N×RTT). The design needs a measured row cap and the
  `withThrowingTaskGroup` fan-out pattern (ShipBox 2.1s concurrent precedent,
  azure-multi-project 2N+1).
- **The 30/min budget is for the *search* API, not the reviews endpoint.** The
  review-state fetch is plain REST (core budget), but the PRD's recorded reason
  must be re-derived against real numbers in the probe, not assumed away.
- **Azure's PR payload may already carry votes** (`reviewers[]` with `vote`)
  — if so, Azure costs nothing extra and the two providers are asymmetric:
  the face must not imply a fetch failure when only GitHub needed the extra
  calls.
- **The snapshot is data, not instruction** — any new field must tolerate
  absence (upgraded installs, partial provider failure) without changing the
  face's fallback behavior. Same rule as every other Deck snapshot: a failed
  provider half never blanks the other half.
- Verify on the **installed copy** — the widget extension renders from
  snapshots in the widget container; live API verification goes through the
  agent path (`DeckAgent` run directly, with Deck.app quit).