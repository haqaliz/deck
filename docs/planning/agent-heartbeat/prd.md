# PRD — A heartbeat witness for the 60s agent

**Slug:** `agent-heartbeat` · **Type:** feat · **Branch:** `feat/agent-heartbeat/aliz`
**Date:** 2026-08-30 · **Brief:** [`../_card/issue.md`](../_card/issue.md) ·
**Dig:** [`../_card/understanding.md`](../_card/understanding.md)
**Follow-up from:** [`../agent-liveness/prd.md`](../agent-liveness/prd.md) — the two
open items that shipped with it, recorded at `ROADMAP.md` M7.

## 1. The ask, in one sentence

Deck's liveness check can prove one of its two agents is running; give the other
one evidence of its own, and let the notice say which half stopped.

## 2. Why this is not already covered

`AgentLivenessPolicy` reads exactly one witness — the age of `processes.json`
(`DeckApp.swift:541`). That file's single writer is the **fast** agent
(`DeckAgent/main.swift`, `sampleProcesses()`, reached only under
`DECK_AGENT_ROLE == "processes"`). The **60s** agent, `com.deck.agent`, writes
ten snapshots and the host app writes every one of them too
(`DeckApp.swift:283, 295, 305, 314, 330, 383, 415, 447, 735, 748`), so not one of
them can distinguish "the agent ran" from "Deck was open".

The consequence is a real blind spot, not a theoretical one:

| What is down | What Deck says today |
|---|---|
| Both agents | "Background refresh has stopped" ✅ |
| Fast agent only | "Background refresh has stopped" ✅ |
| **60s agent only** | **nothing** — eight widgets go stale in silence |

The eight are OpenBox, GitBox, TaskBox, CalBox, PRBox, ShipBox, WeatherBox and
MarketBox. LiveBox keeps ticking in front of the user throughout, which is what
makes the silence convincing.

The v1.36 PRD stated this scope honestly rather than fixing it: *"the snapshot
witnesses only `com.deck.agent.processes` … the notice says 'background refresh
has stopped' and never names an agent."* This is that follow-up.

## 3. Decisions taken with the user (2026-08-30)

| # | Question | Decision |
|---|---|---|
| D1 | Notice shape with two witnesses | **One notice, one Restart button, but it names the half that stopped.** Both agents are registered and repaired by one call, so two buttons would do the same thing; and the measured fault took both down at once, which would draw two warnings for one cause. |
| D2 | Staleness limit for the new witness | **Its own constant, 240s** — four missed ticks at the agent's fixed 60s cadence. Not the existing `max(4 * processRefreshInterval, 120)`, which is keyed to a *LiveBox* setting that has nothing to do with the 60s job and would call it down after 120s at the 5s default. |
| D3 | Corrupt vs absent `processes.json` | **Kept apart inside the policy; no new user-facing state.** The only visible change is wording: a file that exists but will not decode stops claiming "No refresh has been recorded", which is false — something wrote it. No repair UI for a condition the next tick overwrites. |

## 4. User-visible spec

This is a feature, not a widget: it has no face and no settings. Its entire
surface is one notice in **Settings → General → Background refresh**, beside the
two notices already there.

`.healthy` and `.unknown` draw nothing. Silence stays the healthy state, as it is
for every other notice in that tab.

### The three `.down` wordings

| Scope | Text |
|---|---|
| **Both** | "Background refresh has stopped. Deck's agents are registered but macOS is not running them." *(today's wording, unchanged)* |
| **60s agent only** | "Widget data has stopped refreshing. Deck's data agent is registered but macOS is not running it. LiveBox is still updating." |
| **Fast agent only** | "LiveBox's process rows have stopped refreshing. Deck's process agent is registered but macOS is not running it. Other widget data is still updating." |

Each is followed by one evidence sentence and one **Restart agents** button
(unchanged behaviour: `removeAgents()` then `registerAgents()`).

### The evidence sentence, from D3

| Evidence | Sentence |
|---|---|
| A timestamp | "Last refresh: 3 hours ago." *(unchanged)* |
| No file at all | "No refresh has been recorded." *(unchanged)* |
| A file that will not decode | "The last refresh could not be read." **(new)** |

When both agents are down the sentence reports the **more recent** of the two —
the honest answer to "how long has this been broken" is the last time *anything*
ran.

## 5. Data source

A new file in the widget container, `agent-heartbeat.json`, holding one field:
the time the 60s agent last completed a full refresh.

- **Cadence:** every 60s tick, written once at the **start** of the full-refresh
  path, before any fetch is attempted (C1). It witnesses that the 60s agent
  **was launched and started work** — not that it finished. Writing it at the end
  would let a slow-but-healthy tick (ten mostly-serial sources at 10s timeouts,
  or a first opencode resync) cross the 240s limit and be reported dead, while
  catching nothing extra: a hung agent stops advancing the stamp either way,
  because launchd starts no new tick while one is running.
- **Written unconditionally.** It witnesses that the agent *ran to completion*,
  never that the fetches succeeded. Every fetch in that path can fail — a revoked
  token, no network — and the heartbeat must still be written, or Deck tells a
  user with a bad token that macOS is not running their agents. Fetch health is
  already owned by `FetchStatusStore` and is not this file's business.
- **Written only on the full path.** `main.swift` already branches at :54; the
  fast role returns before it.
- **Unavailable state:** absent (never ran) and unreadable (corrupt) are the two
  failure shapes, and per D3 they are distinguished.

### Why a file rather than a field on `DeckSettings`

**This is the load-bearing decision of the whole slice.** `ContainerMigration`
copies **only `settings.json`** across the bundle rename, deliberately
(`ContainerMigration.swift:44-50`: everything else "is a snapshot the agent
rebuilds within one 60s tick"). So:

- a heartbeat **file** cannot cross the rename — the new container starts with no
  evidence, which is exactly true, and the grace clock covers the gap;
- a heartbeat **field on `DeckSettings`** would cross verbatim, and the renamed
  app would open holding a timestamp from the old install with a brand-new agent
  that has never run. That is precisely the false positive
  `AgentRegistrationClock` was written to prevent, re-introduced one file over.

## 6. Design

### The evidence type

```swift
/// What a witness file says. `never` and `unreadable` are different answers:
/// something wrote an unreadable file.
enum AgentEvidence: Equatable {
    case ran(at: Date)
    case never
    case unreadable
}
```

`ProcessSnapshotStore.load()` returns `nil` for a missing file *and* for
undecodable bytes (`ProcessSnapshot.swift:31-34`), which is where the conflation
lives. Reading evidence checks existence first, then decodes.

### The verdict

`AgentLiveness.down` grows from `down(lastRefresh: Date?)` to a small struct
carrying the scope and both pieces of evidence, so the view can word all three
cases without re-deriving anything.

Each witness is judged **independently, with its own threshold**, by the same
five-step ladder the current policy uses (recent evidence wins before the grace
window; a future timestamp is a bad clock, not a dead agent; no registration
clock means unknown). The two verdicts then combine:

- any witness `down` → `.down`, scoped to which ones;
- else all `unknown` → `.unknown`;
- else → `.healthy`.

The two global guards are unchanged and stay structural: `intent == false` and
`state != .enabled` return `.unknown` before any witness is read, so a Login
Items veto still cannot raise a second notice about its own cause.

### Thresholds

| Witness | Limit | Why |
|---|---|---|
| `processes.json` | `max(4 * processRefreshInterval, 120)` | unchanged |
| `agent-heartbeat.json` | `4 * dataAgentInterval` = `240` | 4 × the agent's fixed 60s cadence (D2) |

`dataAgentInterval` is a named constant, not a literal `240`, and it is **pinned
against `StartInterval` in `DeckApp/LaunchAgents/com.deck.agent.plist`** by a test
using the `#filePath` source-tree idiom (C3). Swift never reads that plist at
runtime, so retuning the agent's cadence would otherwise leave a threshold that
fires on every healthy tick with nothing failing.

The grace window after registration uses each witness's own limit, so the
existing behaviour for the fast agent is bit-for-bit unchanged.

### The upgrade grace window (C2)

The new witness is absent on the release that introduces it, and an upgraded
install has an `agentsRegisteredAt` days old with both agents already `.enabled`
— so `AgentRegistrationClock` restamps nothing and the very first evaluation
returns `.down` on a healthy machine. That is the bug class CLAUDE.md already
names ("the notice firing falsely on the exact release it exists to protect"),
reproduced one file over.

`AgentRegistrationClock` therefore gains a **third trigger**: restamp when the
heartbeat is **absent while the process witness is healthy**. A live fast agent
with no heartbeat at all is either this release shipping or a 60s agent that has
never run once, and both deserve one grace window before an accusation. Gating on
the *process* witness being healthy is what keeps it from weakening the existing
check — a real both-agents-down fault has no healthy witness and is unaffected.

### Ordering the evidence when both agents are down (C4)

A timestamp outranks both non-dates; `.unreadable` outranks `.never`, because
"No refresh has been recorded" is exactly the false claim D3 exists to remove.
Two `.never`s report "No refresh has been recorded."

## 7. The invariant this feature is made of

**`DeckApp` must never write `agent-heartbeat.json`.** The file is evidence only
because exactly one process writes it; the moment a host-app refresh path calls
`save`, the witness is destroyed and the notice goes silently and permanently
quiet — the same way the ten snapshots already lost that property.

Nothing structural prevents it: `Shared/` compiles into both targets. So the
invariant is **pinned by a test that reads the non-agent target sources from the
source tree** (`DeckApp/` and `DeckWidgets/`) and asserts none of them writes to
the store — the idiom `DeckBundleTests` already uses to pin `DeckBundle` against
`project.yml` through `#filePath`.

**Stated honestly (C5):** that test is a substring search. It catches the
realistic regression — someone adding a heartbeat write to a host refresh path by
copy-paste, which is how the ten snapshots lost the property — and it would not
catch a wrapper function or a renamed store. The comment on the test says so
rather than letting a later reader take it for proof.

## 8. Non-goals

- **No heartbeat for the widget extension.** It is not an agent, and WidgetKit
  throttling makes its silence normal.
- **No per-fetch health.** `FetchStatusStore` owns "the fetch failed"; this owns
  "the process never ran". Conflating them is what would tell a user with a
  revoked token that macOS is broken.
- **No launchd label in the user-facing text.** "Deck's data agent" and "process
  agent", not `com.deck.agent`.
- **No new settings, no new widget, no face change.**
- **No repair UI for a corrupt snapshot** (D3).
- **Not a fix for the underlying launchd fault.** This reports; the repair is
  still the Restart agents button.

## 9. Verification

- The policy is pure and already table-tested (`RefreshPoliciesTests.swift:144`);
  extend that table rather than replacing it. Both-down, each-alone, corrupt,
  absent, future-timestamp and in-grace cases are unit-pinned.
- Round-trip the heartbeat model in `DecodeTests` — `JSONEncoder` writes `Date`
  as seconds since the **2001 reference date**, which the last cycle pinned by
  test after it confused a reader of `settings.json`.
- The single-writer invariant (§7) is a test, not a comment.
- **Live check on the installed copy**, because SMAppService cannot register from
  `build.noindex`: install, confirm the heartbeat advances every 60s, then
  `launchctl bootout gui/$(id -u)/com.deck.agent` — the fast agent keeps writing,
  the heartbeat stops, and within 240s the General tab must name the data agent
  while LiveBox is still visibly updating. `evaluateLiveness()` already runs on a
  60s timer while the window is open (`DeckApp.swift:219`), so this is watchable
  without relaunching.
- **The upgrade path is part of the live check**, not an afterthought: install
  over a configured v1.36 with the agents running and confirm the General tab
  stays **silent** at first open (C2). A false accusation there is the one
  outcome that discredits the whole feature.
- **Expect the scope to change across a repair.** Pressing Restart agents
  restarts the grace clock, so the notice goes quiet for one window and can
  return naming a narrower scope than before (both → data-only) if one agent
  recovers and the other does not. Designed, not a bug (C6).
- **`xcodegen generate` after adding any file.** xcodegen enumerates sources at
  generation time, so a new file in `Shared/` or `SharedTests/` is silently not
  compiled and the suite still reports success (CLAUDE.md).

## 10. Open questions

None blocking. D1–D3 close the three that mattered, and the self-critique
([`critique.md`](critique.md)) closed two 🔴 and four 🟡 — both reds were
false-positive paths, folded back into §5, §6 and §7 above. The rest were settled
by the dig (storage shape, write placement, erase behaviour — `eraseDeckData` sweeps the
container directory, so the heartbeat is cleaned up with everything else).
