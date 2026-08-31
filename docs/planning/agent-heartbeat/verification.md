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

## Live — the notice, rendered

Captured from the running app by `CGWindowID` (see the harness note below).
Three of the four `.down` shapes were produced against real agent faults:

**60s agent down, fast agent alive** — the case this feature exists for:

> ⚠ Widget data has stopped refreshing. Deck's data agent is registered but macOS
> is not running it. LiveBox is still updating. Last refresh: 21 minutes ago.
> **Restart agents**

**Fast agent down, 60s agent alive** — the mirror:

> ⚠ LiveBox's process rows have stopped refreshing. Deck's process agent is
> registered but macOS is not running it. Other widget data is still updating.
> Last refresh: 2 minutes ago.  **Restart agents**

**Corrupt witness** (`printf '{' > processes.json`, fast agent down) — D3 at its
only user-visible point:

> …Other widget data is still updating. **The last refresh could not be read.**

Not "No refresh has been recorded", which is what the pre-split code would have
said about a file something had plainly written.

In every case the "Refresh in background" toggle stayed **on** — Deck reports the
state, it does not rewrite the user's choice — and `.healthy` drew nothing at
all, before and after.

**The repair works, twice.** Pressing **Restart agents** took `com.deck.agent`
from absent to `state = running, runs = 1`, with the heartbeat advancing within
seconds and the notice gone at the next 60s evaluation. The corrupted
`processes.json` healed itself on the fast agent's next tick (valid JSON, 10
rows) — which is the argument for not giving corruption its own repair UI.

**Both-down was not captured**, and the attempt is worth recording because of
what it found rather than what it showed. With both agents booted out the notice
correctly rendered the *data-agent* wording — because the fast agent had come
back on its own (`runs = 35`, `processes.json` written 8s earlier, the corruption
already overwritten). So the state at capture time really was "60s down, fast
healthy", and the notice was right about it. Both-down is the pre-existing case
with unchanged wording and is unit-pinned; it was not worth further live effort.

## Two observations that are not about this feature

1. **A booted-out fast agent came back without a login.** `agentsRegisteredAt`
   was restamped at 00:26:39 with nothing pressed, which means something called
   `register()`. The likeliest mechanism, unproven: Deck's window was created
   and destroyed repeatedly during the capture attempts, and a window creation
   fires `onAppear` → `reconcileAgents()`, which registers an agent it finds
   `.notFound`. That would also make the recovery *automatic* in a way
   CLAUDE.md's "recovery is a toggle-off/on cycle or the next login" does not
   describe. Recorded as an observation, not a conclusion.
2. **Deck runs windowless once its window is closed, and `open -a Deck` does not
   bring it back** — `applicationShouldHandleReopen` returns `flag`, which is
   `false` with no visible windows. Only killing and relaunching produced a
   window. Unrelated to this work; noted because it cost most of the time in
   this run.

## Harness notes for the next agent doing a GUI check

- **`screencapture -R x,y,w,h` captures the wrong display on a multi-display
  setup** (here 3440×1440 + 3024×1964 Retina). It silently returns *something*,
  which is worse than failing. Use `screencapture -l <CGWindowID>`, and get the
  id from `CGWindowListCopyWindowInfo` — there is no CLI for it, but a six-line
  `swift` script run directly works and PyObjC/Quartz is not installed.
- **Re-read the window's bounds immediately before every synthetic click.**
  Deck's window moved between displays mid-run (`X: 866` → `X: 1724`), and a
  stale origin sends the click into whatever is underneath — twice it landed in
  another app's window.
- **System Events' `count of windows` is unreliable here**, flipping between 1
  and 0 across consecutive queries while `CGWindowListCopyWindowInfo` was
  consistent. Selecting a sidebar row worked (`set selected of row 1 ... to
  true`); enumerating `entire contents` for text mostly returned nothing.

## Still to run

- Re-add each widget from the gallery. Low risk here — the widget extension's own
  sources are untouched by this work (`Shared` gained types no widget reads) —
  but it is the standing rule.
