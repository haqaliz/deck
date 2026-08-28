# Probe — bundle identifier rename

Live measurements taken before the migration was written, per the PRD's R4/R5.
Machine: macOS 15 (Darwin 25.5.0), Deck v1.35 installed from a Release build.

**One-way on this machine by design.** Every distinct bundle id leaves a
container whose `.com.apple.containermanagerd.metadata.plist` is SIP-protected
and cannot be removed, so the probe uses exactly one id — the real
`io.github.haqaliz.deck` — and the artefact left behind is the container the
product will actually use.

---

## Phase 1 — Baseline (2026-08-28 23:36 +0330)

### Gate: Deck must not be running

```
$ pgrep -lf "MacOS/Deck$"
96422 /Applications/Deck.app/Contents/MacOS/Deck     ← WAS running
$ osascript -e 'quit app "Deck"' && pgrep -lf "MacOS/Deck$"
(nothing)                                            ← gate satisfied
```

A running Deck holds settings in memory and pumps several snapshots itself, so
every observation below would otherwise be untrustworthy (CLAUDE.md).

### Backup

`settings.json` (6.3 KB, mode 0600, 16 top-level keys, **4 credential accounts**:
opencode, github, azure, opencode; `agentAtLogin: true`) copied to the session
scratchpad. This file is the only irreplaceable thing in the container.

### 1. Container root

```
$ ls -la ~/Library/Containers/com.deck.app.widgets/
700  Data/
644  .com.apple.containermanagerd.metadata.plist   29.7K
```

The SIP-protected plist is present and is 29.7 KB — this is the file that makes
`rm -rf` on a container unrecoverable.

### 2. Snapshot inventory (20 files)

All 13 snapshots + 7 `fetch-*.json` statuses + `settings.json`. Freshest write
`Aug 28 23:35:19`, i.e. ~47s before the baseline was taken, on the documented
60s cadence. `processes.json` is older (17:51:28) and `opencode.json` /
`fetch-opencodeRemote.json` older still (18:12:14) — expected: opencode is
dormant on this machine (no `serverURL` on either account).

`settings.json` last written 22:49:12 — by the app, not the agent.

### 3. Rendered timelines — 15 directories

```
BatBox CalBox ClipBox ClockBox DevBox GitBox HomeBox LiveBox
MarketBox NetBox OpenBox PRBox ShipBox TaskBox WeatherBox
```

Fourteen shipping widgets plus a stale **`HomeBoxWidget/`** left over from the
WeatherBox/ClockBox split. Noted, not touched — but it confirms chronod's
per-widget timeline cache survives a widget being renamed out of existence,
which is the same cache the flip invalidates wholesale.

### 4. Extension registration

```
$ pluginkit -m -i com.deck.app.widgets
+    com.deck.app.widgets(1.35)
```

### 5. launchd — the agents are NOT in the gui domain's service list

```
$ launchctl list | grep -i deck
(nothing)
$ launchctl print gui/502 | grep -i deck
        "com.deck.agent"           => enabled
        "com.deck.agent.processes" => enabled
$ launchctl print gui/502/com.deck.agent
Bad request. Could not find service "com.deck.agent" in domain for user gui: 502
```

**Finding, and a correction to this repo's own docs.** Both labels appear only
in the domain's *enabled/disabled* table, not as resolvable services — yet the
snapshots are being written on cadence. SMAppService does not bootstrap its jobs
into `gui/<uid>` under their plist label the way the old hand-written
LaunchAgents did.

This matters beyond the probe: **`README.md:362` tells users to check
`launchctl list | grep com.deck.agent`, and `.github/ISSUE_TEMPLATE/bug_report.md:31`
asks a bug reporter to paste that same command's output.** On a healthy
SMAppService install it prints nothing, so the documented health check reports
failure on a working machine. Wrong since v1.33. Fix belongs in Phase 9's docs
pass, and the replacement check is `sfltool dumpbtm` or the snapshot mtimes.

### 6. BTM records (`sfltool dumpbtm`)

```
#12  Name: Deck           Type: app (0x2)
     Disposition: [disabled, allowed, not notified] (0x2)
     Identifier: 2.com.deck.app
     URL: file:///Applications/Deck.app/
     Bundle Identifier: com.deck.app

#13  Name: DeckAgent      Type: agent (0x8)
     Disposition: [enabled, allowed, not notified] (0x3)
     Identifier: 8.com.deck.agent
     URL: Contents/Library/LaunchAgents/com.deck.agent.plist
     Executable Path: Contents/MacOS/DeckAgent
     Generation: 18
     Parent Identifier: 2.com.deck.app

#14  Name: DeckAgent      Type: agent (0x8)
     Disposition: [enabled, allowed, not notified] (0x3)
     Identifier: 8.com.deck.agent.processes
     URL: Contents/Library/LaunchAgents/com.deck.agent.processes.plist
     Executable Path: Contents/MacOS/DeckAgent
     Generation: 18
     Parent Identifier: 2.com.deck.app
```

Three things worth recording:

- **Both agent records store *relative* paths** (`Contents/…`) resolved through
  `Parent Identifier: 2.com.deck.app` → `file:///Applications/Deck.app/`. This
  is direct evidence for the PRD's **R3**: replacing the bundle at that path
  leaves both records valid and pointing at whatever binary now sits there. The
  old label really can execute the new agent.
- The **app** record is `[disabled, allowed]` — Deck itself is not a login item;
  only the two agents are. So the app is *not* guaranteed to run before the
  agent after an upgrade, which is R3's premise.
- `Generation: 18` on both agents — the registration has been rewritten 18
  times, consistent with the SMAppService toggle cycles in v1.33/v1.34.

### Baseline verdict

Healthy install, agents live, one stale `HomeBoxWidget` timeline, and one
documentation bug found for free. Phase 2 may proceed.

---

## Phase 1 addendum — the machine was already broken, and Deck could not tell

The baseline gate turned up a live fault that blocks Phase 3 and is a bug in its
own right.

### Both agents are registered, enabled, allowed — and not running

`gitbox.json` had not moved in 113s against a 60s cadence, so the mtimes were
watched directly with the app quit:

```
23:38:08  gitbox=23:35:18  processes=17:51:28
23:38:53  gitbox=23:35:18  processes=17:51:28
23:39:38  gitbox=23:35:18  processes=17:51:28
```

Nothing written in 4+ minutes. The 23:35:18–19 cluster in the baseline was the
**app** flushing on quit, not the agent. `processes.json` was last written at
**17:51:28 — 5h 45m earlier**.

The unified log is no help (`log show --predicate 'subsystem == "com.deck.agent"'`
returns **0 lines** — the empty-log caveat in CLAUDE.md, confirmed here).

### `processes.json` is the correct liveness probe

Since v1.30 the fast agent is the **single writer** of `processes.json` — the
host app and the full agent were deliberately removed as writers. So its mtime
distinguishes "an agent ran" from "the app ran" with no ambiguity. Every other
snapshot is written by both and cannot tell them apart. Relaunching Deck proved
the point:

```
23:40:44  processes=17:51:28
23:41:24  processes=17:51:28   gitbox=23:40:26   ← app wrote gitbox, agent wrote nothing
```

### Relaunching does not revive them — as documented

CLAUDE.md predicts exactly this: booting out a *registered* agent takes the job
down until the next login or a toggle-off/on cycle, because the registration
record survives, `status` stays `.enabled`, and neither the app's reconcile nor
smd reloads it. Confirmed. Manual recovery is also blocked:

```
$ launchctl bootstrap gui/502 /Applications/Deck.app/Contents/Library/LaunchAgents/com.deck.agent.plist
Bootstrap failed: 5: Input/output error
```

`BundleProgram` only resolves inside the SMAppService context, so the plists
cannot be bootstrapped by hand.

### Why v1.34's reporting does not catch it

v1.34 reports a Login Items veto, which is BTM `[enabled, **disallowed**]` →
`SMAppService.status == .requiresApproval`. **This machine is
`[enabled, allowed]` → `.enabled`.** `AgentReconcilePolicy` sees intent `true`
and state `.enabled` and correctly does nothing; `Agent.register()` also guards
on `status != .enabled`. So Deck's General tab shows "Refresh in background" on,
no notice, and nothing has run for nearly six hours.

**`SMAppService.status` answers "is there a registration record", not "is the job
loaded".** Those came apart here, and Deck has no check for the difference.

### Suggested follow-up (not this unit of work)

Deck already has the ground truth on disk. A liveness check — `processes.json`
older than a few multiples of `processRefreshInterval` while `agentAtLogin` is
on — would turn six silent hours into one notice in the General tab, next to the
veto notice v1.34 added. Worth a ROADMAP entry; it is the third distinct way the
agents can be down (never registered / user-vetoed / registered-but-unloaded)
and the only one Deck cannot currently see.

### Blocking status for the probe

Phase 3 measures what a **live** old agent does when the bundle beneath it is
replaced (R3). With both agents down that measurement is vacuous, so the agents
must be revived first — which needs the in-app toggle off→on, or a login.
