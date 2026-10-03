# Understanding — azure-project-cap (2026-10-03)

## What the work is really asking

Let one Azure DevOps account cover all of the user's projects. The org
(`ForesightAnalytics`) has **six**; `AzureAccountProjects.maxProjects` is **5**
(`native/Shared/CredentialAccount.swift:100`), so one project is unreachable
from TaskBox and PRBox without a second account.

## Correction to the handoff brief

`deck-next` framed this as a "cost-vs-ceiling decision". The code and the
original probe say otherwise:

- `CredentialAccount.swift:97-99`: "Cost is not what bounds this ... it is how
  many pickers fit."
- `azure-multi-project/probe.md` F3: "Cost is not the constraint — six projects
  is 6 WIQL + 1 batch — so the cap is a UI decision about slot count, not a
  budget ... raising it is a one-constant change."

The cost arithmetic (TaskBox N+1, PRBox 2N+1, `prd.md:38-39`) is real but has
already been judged affordable at N=6. A live measurement at N=6 is still worth
taking as confirmation, not as the deciding input. The open question is the
**UI shape**, not the budget.

## Affected files

Behaviour (one constant, three readers):
- `Shared/CredentialAccount.swift` — `maxProjects`; `setSlot` (guard, :113) and
  `normalise` (cap, :134) both read it. Doc comments at :97-100, :102, :152.
- `DeckApp/DeckApp.swift:1553` — `ForEach(0..<maxProjects)` builds the slots, so
  the form grows by itself. Title is "Project" / "Project N (optional)".

Already scale-free (no change expected, to be confirmed by test):
- `AzureIDMerge.interleave` caps globally at the batch's 200 ids
  (`AzureDevOpsLoader.swift:102`), so more projects only thin each one's share.
- `AzureTargets.normalise`, `CredentialsMigration`, `CredentialsCopy`,
  `CredentialVerification` all route through `normalise`.

Copy that says "five" and must change with the number:
- `DeckApp.swift:1544`, `:1599` (comments), `:2335` (user-visible: "up to five projects")
- `README.md:60`, `:62`, `:219`
- `CredentialVerification.swift:141` (comment), `CredentialsMigration.swift:14`
- `docs/planning/azure-multi-project/*` are history; leave them.

Tests pinning 5:
- `AzureAccountProjectsTests.swift:36-41` `testCapsAtFive` (+ `maxProjects == 5`),
  `:157-189` setSlot (`setSlot(5, ...)` is the "past the cap" case).

## Things that look affected but are not

- Settings on disk: raising the cap is backward-compatible (lists of <=5 decode
  unchanged). Downgrading is lossy: an older build `normalise`s a 6-project list
  to 5 on decode and rewrites it. Acceptable; worth one sentence in the PRD.
- The sprint chip shows only with exactly one project — unaffected.
- No widget-extension read depends on project count (CLAUDE.md trap on
  extension-side settings reads is not triggered).
- No shell invariant is at risk: no new widget, no Charts, no version-gated
  descriptor change. A version bump is a release matter, not a feature one.

## Ambiguities / open questions (for the interview)

1. **Ceiling.** 6 (exactly the org), or headroom (8? 10?). Past ~6 the slot form
   becomes a tall wall of identical pickers.
2. **Slots vs. a list.** Keep numbered slots and bump the constant, or replace
   them with an add/remove list (the MarketBox ticker precedent), which scales
   without a cap that is really a layout limit.
3. **Live probe.** Wanted: request count, wall-clock and snapshot size at N=6
   (and the chosen ceiling if higher). It needs the stored PAT read from the
   keychain to hit the live org — needs the user's go-ahead.
4. **PRBox fan-out width.** It is an unbounded `withThrowingTaskGroup` over 2N
   queries. Fine at 6; if the ceiling goes high, decide whether to bound it.
