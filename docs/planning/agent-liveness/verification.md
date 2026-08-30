# Verification run — 2026-08-30

Phase 5 of [`plan_20260830.md`](plan_20260830.md), run against
`/Applications/Deck.app` (a `build.noindex` build cannot register with
SMAppService at all).

**The fault did not need inducing.** The dev machine was already in it. That is
the headline result: this check exists because the state is invisible, and it
was sitting there undetected for 38 hours on the machine of the person who
wrote the feature.

## Baseline found, not created

| Evidence | Reading |
|---|---|
| `processes.json` mtime | **2026-08-29 00:19:42** — 38.4 hours stale |
| `settings.json` → `agentAtLogin` | `true` |
| Deck running? | no |
| BTM record for both agents | present |
| `launchctl print gui/$(id -u)/com.deck.agent.processes` | **found**, and see below |

The app bundle had been installed 2026-08-28 22:49 and the agent wrote normally
for 90 minutes afterwards, then stopped. `parent bundle version = 35` matched
the installed `CFBundleVersion`, so this was not a version mismatch.

## Two findings that correct the existing documentation

### 1. `launchctl print` can report the job as present *and* be useless

The probe (`../bundle-identifier/probe.md`) measured the fault as
`launchctl print` answering `Could not find service`. Here the job was found —
and the detail is one line further down:

```
state = spawn scheduled
last exit code = 78: EX_CONFIG
job state = spawn failed
runs = 13741
```

Thirteen thousand seven hundred and forty-one failed spawns, every 5s, silently.
So "registered but not running" has **at least two shapes**: the job absent, and
the job present but failing to spawn. A check built on `launchctl print`
succeeding would have called this one healthy. `processes.json` catches both,
because it asks the only question that matters — did the agent *write* anything.

### 2. An in-app unregister→register repaired a state the docs call logout-only

CLAUDE.md records, from the rename rollback:

> Reinstalling the old bundle over the new one leaves **two BTM app records
> claiming the same URL**, after which launchd refuses both jobs with
> `EX_CONFIG`. The in-app toggle, `launchctl kickstart -k` and restarting `smd`
> all fail; only a logout/login repairs it.

Both halves of the premise held: `sfltool dumpbtm` showed **two** records with
`URL: file:///Applications/Deck.app/`, and both jobs were failing `EX_CONFIG` —
left over from the 08-29 rename probe, on a machine with 16 days of uptime and
no login since.

**The conclusion did not hold.** Replacing the app bundle and then pressing
**Restart agents** (`unregister()` → `legacyCleanup()` → `register()`) repaired
it, with no logout:

```
click at 14:45:12
processes.json mtime   14:45:13     (was 2026-08-29 00:19:42)
agentsRegisteredAt     14:45:12     (restamped)
last exit code = 0 · job state = exited · runs = 1   (was 78: EX_CONFIG, runs = 13741)
```

Whether the bundle replacement, the unregister/register cycle, or the pair of
them did the work is **not isolated here** — a controlled version would require
deliberately re-entering the two-record state. What is measured is that
"only a logout/login repairs it" is too strong, and the in-app button is worth
pressing before telling anyone to log out.

## The seven steps

| # | Step | Result |
|---|---|---|
| 1 | Install Release build over `/Applications`, launch | `agentsRegisteredAt` written at 14:40:50 — the adopt-on-sight arm firing on an upgrade with no re-registration |
| 2 | Baseline | — (machine already faulted; see above) |
| 3 | Induce the fault | not needed |
| 4 | Wait past `threshold` (120s at interval 15) | at +96s the computed state was `.unknown` (grace); it flipped to `.down` at +120s |
| 5 | Observe the notice | **rendered**, toggle still on |
| 6 | Press **Restart agents** | **repaired in 1 second**; witness then advanced every 20s |
| 7 | Relaunch twice (A2) | `agentsRegisteredAt` unchanged at 14:45:12 both times |

Step 5, verbatim from the window:

> ⚠ Background refresh has stopped. Deck's agents are registered but macOS is
> not running them. Last refresh: 1 day ago.  ·  **Restart agents**

Step 6 left the section drawing nothing at all, identical to its appearance
before this feature — silence is the healthy state.

## A3 is resolved

The plan's one unmeasurable risk was that `Agent.register()`'s early return
(`guard service.status != .enabled`) would make the button a silent no-op if
`unregister()` did not drop the status synchronously. **It does not.** The
re-registration took effect and the agent wrote within one second. The
"give the repair one grace window" behaviour was never exercised as a mask,
because the repair was faster than the grace.

## Incidental, and worth knowing

**`sfltool dumpbtm` prompts for an admin password** ("sfltool wants to make
changes") and blocks on it — it is not a read-only command from a script's
point of view, and it takes minutes to produce full output. Anything in a
runbook reaching for it should say so. The two queries used here were
`sfltool dumpbtm | grep -n "URL: file:///Applications/Deck.app/"` and the
`Identifier:` lines, both bounded with `head`.

**`settings.json` is rewritten on every launch** by something predating this
work, so its mtime is not evidence about the liveness clock. The value is what
matters, and step 7 asserts on the value.

---

# Root cause found: **Deck kills its own agents every time it launches**

Found while checking whether the repair held. It does — for as long as nobody
opens Deck.

## The measurement

Agents healthy, `runs = 24`, `last exit code = 0`, witness advancing every 20s.
Quit Deck, relaunch it, change nothing else:

```
BEFORE   witness = 14:58:21   runs = 24 · last exit code = 0
         (quit, relaunch, wait 25s)
AFTER    witness = 14:58:41   com.deck.agent           GONE (Could not find service)
                              com.deck.agent.processes GONE (Could not find service)
         +82s    witness = 14:58:41   — frozen at the moment of relaunch
```

Repeated twice, deliberately the second time. Left alone instead, the same
registration ran happily for three minutes and twenty clean ticks.

## Why

`reconcileAgents()` runs `legacyCleanup()` on **every launch**. That function
boots out and deletes `DeckBundle.Legacy.agentLabel` and
`.Legacy.fastAgentLabel` — and today those are **not** legacy values:

```swift
enum Legacy {
    static let agentLabel     = "com.deck.agent"            // == DeckBundle.agentLabel
    static let fastAgentLabel = "com.deck.agent.processes"  // == DeckBundle.fastAgentLabel
}
```

They only diverge *after* the rename. Before it, `legacyCleanup()` is a
`launchctl bootout` of the two jobs SMAppService is currently running. And then
nothing puts them back, because of a trap this repo already documented:

> booting out a *registered* agent takes the job down until the next login or a
> toggle-off/on cycle — the registration survives (status stays `.enabled`), so
> neither the app's reconcile nor smd reloads it.

So the sequence on every launch is: boot out the live jobs → ask the policy what
to do → `resolve(intent: true, state: .enabled)` → `[]` → do nothing. Background
refresh is dead until the user toggles the switch twice or logs in.

## What this explains

- The **6-hour** silence in `../bundle-identifier/probe.md`, Phase 1.
- The **38-hour** silence found at the top of this document.
- Why the toggle cycle is the documented recovery, and why `settings.json` is
  not: both notes are describing the symptom of this.
- Why it went unnoticed for so long: opening Deck is what breaks it, and opening
  Deck is also what makes the data look fresh, because the host app pumps every
  snapshot except `processes.json` itself.

## This blocks shipping the notice as-is

The liveness check works — it caught this three separate times today, including
once on its own timer with no relaunch. But shipping it against this bug means
**every user sees the alarm every time they open the settings window**, for a
fault Deck causes. An alarm for a self-inflicted wound trains people to ignore
alarms.

## The fix (proposed, not applied)

Boot out only what actually exists. A pre-SMAppService install (≤1.32) has a
real plist at `~/Library/LaunchAgents/<label>.plist` and genuinely needs the
bootout, because that hand-written job collides with the SMAppService
registration over the same label. A clean install has no such file and needs
nothing:

```swift
for label in [DeckBundle.Legacy.agentLabel, DeckBundle.Legacy.fastAgentLabel] {
    let plist = home/"Library/LaunchAgents/\(label).plist"
    guard FileManager.default.fileExists(atPath: plist.path) else { continue }
    bootout(label); remove(plist)
}
```

Precise, keeps the upgrade path, and the decision ("which labels need cleaning,
given which plists exist") is pure and unit-testable. Comparing legacy labels
against current ones would also work but is wrong for the release *after* the
rename, when the legacy jobs are real and must still go.

**Not applied here** — it is a separate shipped bug from the check that found
it, and out of this branch's approved scope.
