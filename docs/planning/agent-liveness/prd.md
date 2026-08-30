# PRD — Agent liveness check

**Slug:** `agent-liveness` · **Type:** feat · **Branch:** `feat/agent-liveness/aliz`
**Date:** 2026-08-30 · **Brief:** [`../_card/issue.md`](../_card/issue.md)
**Blocks:** the bundle rename — [`../bundle-identifier/flip-runbook.md:11`](../bundle-identifier/flip-runbook.md)

## 1. The ask, in one sentence

Deck must notice, and say, when its background agents are registered but not
running — the third of three ways they can be down, and the only one Deck is
currently blind to.

## 2. Why this is not already covered

`SMAppService.status` answers "does a registration record exist", not "did
launchd load the job". Measured on the dev machine
([`../bundle-identifier/probe.md`](../bundle-identifier/probe.md)): both agents
`[enabled, allowed]` in `sfltool dumpbtm`, the toggle on, `launchctl print
gui/$(id -u)/com.deck.agent` answering `Could not find service`, and **nothing
written for six hours**.

The three ways down, and what covers each today:

| State | BTM record | `SMAppService.status` | Covered by |
|---|---|---|---|
| Never registered | absent | `.notFound` / `.notRegistered` | `AgentReconcilePolicy` → `.register` / `.adoptIntent` |
| User veto in Login Items | `[enabled, disallowed]` | `.requiresApproval` | v1.34 `.reportBlocked` notice |
| **Registered, not loaded** | `[enabled, allowed]` | `.enabled` | **nothing** |

`AgentReconcilePolicy.resolve(intent: true, state: .enabled)` returns `[]`, which
is correct — there is nothing to reconcile. The registration is exactly what the
user asked for. The job simply is not there, and no API says so.

There is also no shell probe: **`launchctl list | grep com.deck.agent` prints
nothing on a healthy install** (CLAUDE.md, agent-health trap 1). SMAppService
jobs are not bootstrapped into `gui/<uid>` under their plist label. The README
and issue template asked for that command from v1.33 until it was corrected. So
the check must be inferential, from what a live agent leaves behind.

## 3. Ground truth

`processes.json`. **Verified in this worktree, not assumed:** the only writer is
`native/DeckAgent/main.swift:49`, inside `sampleProcesses()`, reached only on the
fast-agent branch (`DECK_AGENT_ROLE == "processes"`). `grep -rn
"ProcessSnapshotStore.save\|HostProcessSampler" native/DeckApp native/DeckWidgets`
is empty. Every other snapshot is written by the host app *and* the agent, which
is exactly why a dead agent is invisible while Deck is open.

Two properties make it the right witness:

- **`writtenAt` is always refreshed when sampled.** `sampleProcesses()` is
  always-write when it does not skip (the v1.33 "quiet machine" fix), so
  `writtenAt` is a true last-ran stamp, not a last-changed stamp.
- **The first tick always writes.** `ProcessRefreshPolicy.shouldSample` returns
  `true` for `lastSampleAt == nil`, and the plist carries `RunAtLoad` with a 5s
  `StartInterval`. A healthy registration produces a file within seconds.

**Decision: read `ProcessSnapshot.writtenAt`, not the file's mtime.** The
roadmap entry says mtime; `writtenAt` is the same fact, already decoded by
`ProcessSnapshotStore.load()`, already the input to `ProcessRefreshPolicy`, and
needs no `stat`. Reuses tested code instead of adding a second notion of "when".

## 4. Scope — what this can and cannot prove

**Decided: the fast agent only, worded so it never claims more.**

`processes.json` witnesses `com.deck.agent.processes`. The 60s `com.deck.agent`
has no unambiguous witness, because the host app writes every snapshot it writes.
Both agents are registered by one `AgentService.registerAll()` call and the
measured six-hour fault took both down together, so in practice this catches the
real case — but the notice says *"background refresh has stopped"*, never
"com.deck.agent is not running", because the second sentence is not proven.

Rejected: a heartbeat sidecar for the full agent (the `opencode-cursor.json`
precedent). More surface than the prerequisite needs; recorded as a follow-up.

## 5. The policy

Pure, in `Shared/RefreshPolicies.swift`, beside `ProcessRefreshPolicy` and
`AgentReconcilePolicy` — the file that already exists for exactly this.

```swift
enum AgentLiveness: Equatable {
    case healthy
    case unknown                    // not our business, or too early to tell
    case down(lastRefresh: Date?)   // nil = never ran at all
}

enum AgentLivenessPolicy {
    static func threshold(processRefreshInterval: Int) -> TimeInterval
    static func resolve(
        intent: Bool,
        state: AgentRegistrationState,
        lastRefreshAt: Date?,
        registeredAt: Date?,
        processRefreshInterval: Int,
        now: Date
    ) -> AgentLiveness
}
```

**Resolution order** (order matters, see the notes):

1. `intent == false` → `.unknown`. Nothing should be running; not a fault.
2. `state != .enabled` → `.unknown`. The other two notices own those states.
3. `lastRefreshAt` within `threshold` → `.healthy`. **Checked before the grace
   window**, so a restart that works clears the notice at the next tick instead
   of waiting out the grace.
4. `registeredAt == nil` → `.unknown`. No clock to judge against.
5. `now - registeredAt < threshold` → `.unknown`. The grace window.
6. otherwise → `.down(lastRefresh: lastRefreshAt)`.

**Threshold: `max(4 * processRefreshInterval, 120)` seconds** — 2 minutes at the
default 15s interval, 4 minutes at 60s. Deliberately more conservative than the
widget's own `ProcessSnapshot.maxAgeSeconds(for:)` (`max(2 * interval, 30)`),
because the consequences differ: that one dims a row on a missed tick, this one
tells the user macOS is not running their agents. A notice that flickers on a
transient hiccup is worse than one that takes two minutes.

One threshold serves both the staleness test (3) and the grace window (5). A
registration older than the threshold with nothing ever written is the
never-ran case, and it is the one the rename produces.

Clock skew: a `lastRefreshAt` in the future yields a negative interval and reads
as `.healthy`. Deliberate — never accuse on a bad clock.

**Precedence is structural, not an `if` in the view.** Rule 2 means a
`.requiresApproval` veto can never also raise a liveness notice. Two notices for
one condition, the second of them wrong about the cause, is the ShipBox C1
mistake (telling someone to fix what they already fixed).

## 6. The grace-period clock

**New top-level field: `DeckSettings.agentsRegisteredAt: Date?`** (default `nil`).
Needs a `CodingKeys` case, `decodeIfPresent`, and an `encode` line — all three.
`DeckSettings.CodingKeys` is hand-written, so a forgotten case compiles, decodes
as absent and never encodes; that bug cost the credentials work an entire
release's worth of accounts (ROADMAP M6, credentials self-critique).

Written at three moments:

- `reconcileAgents()` — after a successful `register()`.
- `reconcileAgents()` — **also when `state == .enabled` and the field is `nil`**.
  This is the upgrade path: an install that already had both agents registered
  before this feature shipped never calls `register()` again, so without this the
  field stays `nil` forever and rule 4 makes the check permanently silent. Adopting
  `now` on first sight means the field reads as *"the earliest moment Deck knew a
  registration existed"*, which is the right thing to grace-period from.
- The **Restart agents** button — reset to `now`, so the notice does not
  immediately reappear before the first tick after a restart.

It is a diagnostic timestamp, not a preference. It is never shown, and clearing
it only costs one grace window.

## 7. User-visible surface

General tab → **Background refresh** section, under the existing toggle and
beside the Login Items notice. Same `Label` + `exclamationmark.triangle.fill` +
`.orange` treatment already used for `agentNotice`.

**Never ran** (`.down(lastRefresh: nil)`):

> ⚠ Background refresh has stopped. Deck's agents are registered but macOS is
> not running them. No refresh has been recorded. **[ Restart agents ]**

**Stopped** (`.down(lastRefresh: date)`):

> ⚠ Background refresh has stopped. Deck's agents are registered but macOS is
> not running them. Last refresh: 6 hours ago. **[ Restart agents ]**

Relative age uses the same formatter conventions as the rest of the app (a
`RelativeDateTimeFormatter`; the exact call is a plan detail). `.healthy` and
`.unknown` render nothing at all — no green "all good" row. Deck's other
notices are silent when correct and this one matches.

**The button** does `AgentService.unregisterAll()` then `AgentService.registerAll()`
— the documented off→on cycle, already two existing calls, plus the
`agentsRegisteredAt = now` reset. It replaces prose telling the user to flip a
switch twice, which is a worse version of a button that flips it twice.

Two things it must get right:

- `AgentService.Agent.register()` guards on `status != .enabled`. After
  `unregisterAll()` the status must actually have dropped, or the re-register is
  a silent no-op and the button does nothing. **Verify this on the installed
  copy** — it is the one behaviour in this feature that no unit test can reach.
- A `register()` failure must surface through the existing `agentError` slot,
  not be swallowed.

## 8. Cadence

Evaluated at three moments, all cheap (one small file decode):

- `reconcileAgents()`, at launch, where `agentNotice` is already computed.
- The existing 60s `ContentView` timer — the notice appears and clears while the
  user is watching the tab, which is when they are looking.
- `applyAgent()`, on a toggle change, so the state is immediate.

No new timer. The 60s tick against a 120s floor threshold means the notice shows
within about one to two minutes of a fault.

## 9. Shell fit

No widget changes, no snapshot changes, no new container file, no data path.
This is host-app-only, and the only new persisted state is one optional `Date`.

CLAUDE.md invariants: untouched. The extension reads nothing new (the
"two settings fields are read inside the widget extension" trap does not apply
— `agentsRegisteredAt` is host-only, and `grep -rn "agentsRegisteredAt"
native/DeckWidgets/` must stay empty). `RGBA`/`NSColor` is not involved. No
Swift Charts. No new keychain item.

## 10. Non-goals

- **Not** a fix for the underlying launchd behaviour. Deck cannot make smd load
  a job it declined to load; the documented recovery is a re-registration.
- **Not** per-agent reporting (§4).
- **Not** a health indicator when everything works. Silence is the healthy state.
- **Not** driven from `settings.json`. That file is not a test seam for this:
  with the record `.enabled`, the reconcile policy re-adopts `agentAtLogin: true`
  from the registration and never unregisters (CLAUDE.md, trap 3).
- **Not** a notification, badge, or anything outside the General tab.

## 11. Tests

Pure policy, in the existing `native/SharedTests/RefreshPoliciesTests.swift`:

| Case | Expected |
|---|---|
| intent off, everything else stale | `.unknown` |
| `.requiresApproval` + stale | `.unknown` (veto notice owns it) |
| `.notFound` / `.notRegistered` + stale | `.unknown` |
| fresh write, old registration | `.healthy` |
| fresh write, registration inside grace | `.healthy` (rule 3 before rule 5) |
| no write, registration inside grace | `.unknown` |
| no write, registration older than threshold | `.down(nil)` |
| stale write, old registration | `.down(date)` |
| write in the future | `.healthy` |
| `registeredAt == nil`, stale write | `.unknown` |
| threshold: interval 15 → 120s; 60 → 240s; 5 → 120s | floors correctly |
| boundary: exactly at threshold | pinned either way, explicitly |

Plus a `DecodeTests` case: `agentsRegisteredAt` round-trips, and its absence
from an older `settings.json` decodes without disturbing any other field.

## 12. Verification that no test can do

One hand-driven pass on the **installed** copy (`/Applications/Deck.app` — a
`build.noindex` build cannot register with SMAppService at all):

1. Install, confirm the notice is absent and `processes.json` mtime advances.
2. Quit Deck. `launchctl bootout gui/$(id -u)/com.deck.agent.processes`.
3. Wait past the threshold. Launch Deck → the notice must appear with a
   plausible "last refresh" age.
4. Press **Restart agents** → within one interval the notice must clear and
   `processes.json` must start advancing again.

**This costs a real outage.** The one measured way into the fault state is a
`bootout` of a registered agent while the app is not running, and that leaves
the job down until the next login or a toggle cycle — smd does not reload it
spontaneously (measured 2026-08-27). Step 4 is also the repair.

## 13. Open follow-ups

- A heartbeat witness for the 60s `com.deck.agent` (§4).
- Correct the README / issue-template `launchctl list` guidance if any copy
  still survives; the check makes the manual command unnecessary anyway.

---

## 14. Self-critique

Findings from pressure-testing §1–13 against the code. Two red, three amber.

### 🔴 R1 — The rename carries a stale `agentsRegisteredAt`, which would fire the notice falsely on the very release this feature exists to protect

`ContainerMigration` copies `settings.json` into the new container verbatim, so
the renamed app's first launch reads an `agentsRegisteredAt` from hours or days
ago. The new container has no `processes.json` at all. Rules 3–5 then evaluate:
no write, registration timestamp long past the grace window → **`.down(nil)`**,
"no refresh has been recorded" — shown to every user of the rename release
seconds after they launch, while the new agents are registering perfectly
normally.

The scenario this feature was built for would be its first false positive.

**Fix — a hard ordering constraint inside `reconcileAgents()`, not an
afterthought:**

```
1. legacyCleanup()
2. for each agent: resolve + act (register / adoptIntent / reportBlocked)
3. stamp agentsRegisteredAt  (on successful register, or .enabled && nil)
4. evaluate AgentLivenessPolicy  ← must read the value written in step 3
```

On the renamed app the new labels are `.notFound`, so step 2 registers, step 3
stamps `now`, and step 4 sees a fresh registration inside the grace window →
`.unknown`. If registration *fails*, state stays `.notFound`, rule 2 returns
`.unknown`, and `agentError` reports it instead — also correct.

Pin it with a test that the stamp precedes the evaluation, not just that both
happen. Ordering bugs of this shape do not fail loudly.

### 🔴 R2 — The Restart button must reuse `registerAgents()`, not call `AgentService` directly

§7 says the button does `unregisterAll()` + `registerAll()`. Calling
`AgentService` directly skips `legacyCleanup()`, which the existing
`registerAgents()` runs **before** registering and with `waitUntilExit` — the
comment there is explicit that a fire-and-forget bootout races the registration
and the label collision rejects the new job. It also skips the `agentError`
assignment and the `.requiresApproval` re-check.

**Fix:** the button calls the existing private `removeAgents()` then
`registerAgents()`, plus the `agentsRegisteredAt = now` reset, then re-evaluates.
No new registration path. This is a two-line handler, not a new subsystem.

### 🟡 A1 — Corrupt is indistinguishable from absent

`ProcessSnapshotStore.load()` returns `nil` for a missing file and for one that
fails to decode, so an agent that is running but wrote garbage reads as
`.down(lastRefresh: nil)` — "no refresh has been recorded", which is wrong about
the cause. `AtomicFile`'s temp+rename makes a torn write very unlikely and the
recovery (restart the agents) is harmless either way. **Accepted**, recorded here
rather than fixed; not worth a second failure mode to distinguish.

### 🟡 A2 — Stamping in reconcile writes settings on one launch for every existing install

`.onChange(of: settings)` fires `settings.save()` and
`WidgetCenter.shared.reloadAllTimelines()`. Harmless, but it should happen
exactly once, not on every launch. **Fix:** guard the adopt-on-sight write on
`agentsRegisteredAt == nil` so the assignment is genuinely one-time.

### 🟡 A3 — The re-register no-op is still unproven

`AgentService.Agent.register()` returns early when `service.status == .enabled`.
Whether `unregister()` drops the status synchronously is not documented and not
measured. If it does not, the Restart button is a silent no-op — the worst
possible outcome for a button whose entire purpose is repair. No unit test can
reach this. It stays as §12 step 4, and if it proves to be a no-op the fallback
is to report the failure rather than to sleep-and-retry.

### Checked and found sound

- **`eraseDeckData()` cannot produce a false positive.** It calls
  `uninstallAgents()` (unregisters) and then `settings = DeckSettings()`, which
  resets `agentsRegisteredAt` to `nil` *and* `agentAtLogin` back to its `true`
  default. With the agents unregistered the state is `.notRegistered` /
  `.notFound`, so rule 2 returns `.unknown` before the `nil` timestamp is ever
  consulted. Two independent reasons it stays silent.
- **Fresh install is silent.** `agentAtLogin` defaults `true`, state `.notFound`
  → register → stamp → grace → `.unknown`.
- **The veto case cannot double-report.** Rule 2 is structural; a
  `.requiresApproval` install never reaches the staleness test.
- **`processes.json` genuinely has one writer.** Re-grepped in this worktree
  across `DeckApp`, `DeckAgent`, `DeckWidgets`, `Shared` and `scripts/`:
  `LiveBoxWidget.swift:83` reads it, `DeckAgent/main.swift:41` reads it to
  throttle, `DeckAgent/main.swift:49` is the only write.
- **Nothing crosses into the extension.** `agentsRegisteredAt` is host-only; the
  "two settings fields read inside the widget extension" trap does not apply.
