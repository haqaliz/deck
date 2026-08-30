# Verification — `agent-heartbeat`

Run 2026-08-30/31 on the dev machine, against the **installed copy** (v1.36
bundle replaced by the branch build; SMAppService cannot register from
`build.noindex`).

## Unit gate

`1117 tests, 0 failures`. New: `AgentEvidenceTests` (10),
`AgentHeartbeatWiringTests` (4), `AgentLivenessCopyTests` (8),
`AgentLivenessTwoWitnessTests` (18), plus the existing liveness table rewritten
to the two-witness shape with its inputs untouched.

## Live, before installing — the write path

Run with **Deck open**, which is safe here for the reason the whole feature
exists: the host app does not write this file.

| Check | Result |
|---|---|
| Full role writes the heartbeat | `{"writtenAt":809814137.748352}` |
| The stored date is the 2001 reference date | decodes to `2026-08-30 20:22:17 UTC` ✅ (as pinned) |
| **Fast role does not touch it** | mtime **unchanged** across a `DECK_AGENT_ROLE=processes` run |
| A second full run advances it | `1788121337 → 1788121353` |

Unchanged mtime is the tell, not unchanged content — the standing rule for
telling "left alone" from "rewritten identically".

## Live — the upgrade case (C2), the one that could discredit the feature

Preconditions were **real, not synthesized**: a v1.36 install that had been
running for hours.

```
agentAtLogin:        true
agentsRegisteredAt:  2026-08-30 11:31:32 UTC  (8.9 hours old — grace long spent)
processes.json:      11 seconds old            (fast agent demonstrably alive)
agent-heartbeat.json: absent                   (no build before this one wrote one)
```

That is exactly the input triple that, without the guard, resolves to
"Widget data has stopped refreshing" on a healthy machine. With the guard —
`.never` from the data witness while the process witness is healthy is
ambiguous, not damning — it resolves to `.healthy`.

## Live — under real launchd

Heartbeat written on the installed agent's own schedule:

```
23:55:17 → 23:56:25 → 23:57:33
```

**~68s per tick, not 60s** — `StartInterval` plus the tick's own duration. Worth
recording: it is the measurement that sizes the 240s threshold, which absorbs
3.5 real ticks rather than the 4.0 the arithmetic suggests.

Also confirmed: replacing the app bundle did **not** take the jobs down here
(`runs = 439`, `last exit code = 0`, heartbeat written 25s later). The identifier
and version were unchanged, which is the difference from the rename case.

## Live — the fault this feature exists for

`launchctl bootout gui/$(id -u)/com.deck.agent` at 23:57:52, fast agent left
alone:

```
t+30s   heartbeat=23:57:33   processes=23:58:08
t+120s  heartbeat=23:57:33   processes=23:59:49
t+300s  heartbeat=23:57:33   processes=00:02:50
```

The blind spot, reproduced exactly: **the 60s agent is dead, the fast agent is
writing every ~35s, and LiveBox keeps updating in front of the user.** Before
this feature Deck said nothing at all here. The heartbeat crossed the 240s limit
at 00:01:33.

**A relaunch of Deck did not reset the verdict** (checked at 00:04:35, heartbeat
still 23:57:33). That is the design working: a bootout leaves the registration
`.enabled`, so nothing re-registers and the grace clock is not restamped — and
the ambiguity rule does not apply to a heartbeat that *exists* and went stale.
It is also why the guard was moved out of the clock: a clock-based guard would
have been reset by exactly this relaunch.

## Not verified here, and honestly so

**The rendered sentence in the General tab.** The wording is pure and unit-pinned
(`AgentLivenessCopy`, 8 tests), and the verdict feeding it is unit-pinned and
now measured live — but nobody has yet *seen* the notice draw. Two attempts
failed for environment reasons, not product ones: `screencapture -R` on a
two-display setup (3440×1440 + 3024×1964 Retina) captured the wrong display, and
System Events reported Deck's window count flipping between 1 and 0 across
consecutive queries.

Left for a human glance, which is also the repair: **open Deck → General**, read
the notice, press **Restart agents**.

`launchctl kickstart -k gui/$(id -u)/com.deck.agent` cannot do it —
`Could not find service`, consistent with the existing note that `BundleProgram`
resolves only inside the SMAppService context. The button is the recovery.

## Still to run

- The mirror (bootout the fast agent alone → the process-agent wording) and both
  together.
- The corrupt-file wording, with Deck quit: `echo "{" > processes.json`.
- Re-add each widget from the gallery.
