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
