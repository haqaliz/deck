# Phase 2 — Understanding

## What the work is really asking

Not "add a file". The liveness check shipped with a **witness gap**: it can prove
`com.deck.agent.processes` ran and can prove nothing at all about
`com.deck.agent`. The ask is to close that gap and then say something more
precise than "background refresh has stopped".

## Ground truth, measured in the code

| Fact | Where |
|---|---|
| Liveness reads exactly one witness | `DeckApp.swift:541` — `lastRefreshAt: ProcessSnapshotStore.load()?.writtenAt` |
| That witness is the fast agent's | `DeckAgent/main.swift:33-51` `sampleProcesses()`, reached only when `DECK_AGENT_ROLE == "processes"` |
| The host app writes **all ten** 60s snapshots | `DeckApp.swift:283, 295, 305, 314, 330, 383, 415, 447, 735, 748` |
| …so none of them can witness the 60s agent | that is exactly why the PRD scoped the notice to "an agent" |
| The notice deliberately refuses to name an agent | `DeckApp.swift:826-830` doc comment |

## The two caveats from the card, resolved by the dig

1. **`ContainerMigration` carrying a stale heartbeat — avoided by construction,
   if the heartbeat is a file.** The migration copies **only `settings.json`**
   (`ContainerMigration.swift:66`, and its doc comment says so deliberately:
   everything else "is a snapshot the agent rebuilds within one 60s tick"). So a
   heartbeat *file* cannot cross the rename, while a heartbeat *field on
   `DeckSettings`* would cross verbatim and reproduce the exact bug the last
   cycle caught. **This dictates the storage choice** and is the single most
   load-bearing finding here.
2. **The grace clock already covers any witness.** `agentsRegisteredAt` is not
   per-agent; `AgentLivenessPolicy` step 5 gates on it before returning `.down`.
   A second witness inherits that, provided it is compared against a threshold
   and not against zero.

## What the heartbeat has to be, and what it must not be

- Written **only** on the full-refresh path, and **unconditionally** — it
  witnesses "the 60s agent ran to completion", never "the fetches succeeded".
  Every fetch in that path can fail and the heartbeat must still be written, or
  a user with a revoked token gets told macOS is not running their agents.
- Never written by `DeckApp`. Nothing structural prevents it: `Shared` compiles
  into both targets, so a future refresh path could call `save` and silently
  destroy the witness — the same way the ten snapshots already did. This wants a
  guard, not just a comment.
- Swept by `eraseDeckData` for free (`DeckApp.swift:707-713` removes every item
  in the container directory).

## The second half: corrupt vs absent

`ProcessSnapshotStore.load()` (`ProcessSnapshot.swift:31-34`) returns `nil` for a
missing file **and** for undecodable bytes — `try? Data(contentsOf:)` then
`try? decode`. Liveness maps `nil` to "never ran". A truncated snapshot from a
crash mid-write therefore reads as a dead agent that is running perfectly well.
`AtomicFile` makes a partial write unlikely, not impossible (it falls back to a
plain atomic write when `replaceItemAt` throws).

## Affected files

- `native/DeckAgent/main.swift` — write the heartbeat at the end of the full path.
- `native/Shared/RefreshPolicies.swift` — `AgentLiveness` + `AgentLivenessPolicy`
  become two-witness; the shape of the `.down` case has to change.
- `native/Shared/` — a new heartbeat model + store (small; follows
  `ProcessSnapshot.swift`'s store pattern over `AtomicFile`).
- `native/DeckApp/DeckApp.swift` — `evaluateLiveness()` (:537) and
  `livenessNotice(lastRefresh:)` (:832).
- `native/SharedTests/RefreshPoliciesTests.swift` — the policy is pure and
  already table-tested; extend rather than replace.

## Shell invariants checked

Nothing here touches a widget face, a timeline, or the settings schema (if the
heartbeat is a file). No new TCC prompt, no subprocess, no network. The widget
extension never reads the heartbeat — it is host-and-agent only, like
`ContainerMigration`.

**One build trap applies:** xcodegen enumerates sources at generation time, so a
new file in `Shared/` or `SharedTests/` is silently not compiled until
`xcodegen generate` runs — and the suite still reports success (CLAUDE.md).

## Open questions for the interview

1. Does the notice **name** the agent now, or stay one generic notice?
   What does it say when both are down, versus one?
2. The 60s agent's cadence is fixed at 60s, but the current threshold is
   `max(4 * processRefreshInterval, 120)` — the *fast* agent's setting. Does the
   second witness get its own threshold constant?
3. What should a **corrupt** `processes.json` produce — its own user-visible
   state, or just "no evidence" with the ambiguity removed internally?
4. Does the heartbeat carry anything beyond a timestamp?
5. `.down(lastRefresh:)` shape: one case carrying both agents, or two cases?
