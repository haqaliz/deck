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

### Attempted recovery — and why the settings file cannot do it

Three routes were tried to revive the agents without touching the UI.

**1. Accessibility API — Deck's window exposes no AX tree.** System Events sees
the process and the window (`AXFocusedWindow` → `window Deck`), but
`count of entire contents` is **0**, focused or not. The v1.33 notes record
hand-driven checks "through the accessibility API"; whatever that was, a plain
System Events traversal cannot reach this window's controls today.

**2. `launchctl bootstrap` of the bundle's plists — refused.**

```
$ launchctl bootstrap gui/502 /Applications/Deck.app/Contents/Library/LaunchAgents/com.deck.agent.plist
Bootstrap failed: 5: Input/output error
```

`BundleProgram` resolves only inside the SMAppService context.

**3. Toggling `agentAtLogin` in `settings.json` with Deck quit — a no-op by
design.** Set to `false`, Deck relaunched, and the value was **`true` again**
minutes later, with both records still `[enabled, allowed]` and `Generation`
18 → 20.

This is `AgentReconcilePolicy` behaving exactly as specified.
`DeckApp.reconcileAgents()` documents it: "a service the user disabled in
System Settings → Login Items stays off and flips the toggle off; one they
**enabled** there flips it back on." With intent `false` and state `.enabled`,
the policy reads the *registration* as the user's newer choice and adopts it —
so it re-adopts `true` and never unregisters.

**Consequence worth recording: `agentAtLogin` in `settings.json` is not a
usable off switch.** While the BTM record is `[enabled, allowed]`, the policy
will always adopt back to on. The only ways off are the in-app toggle (which
calls `unregister()` directly rather than going through reconcile) and System
Settings → Login Items. This is correct behaviour, but it means the file is
not a test seam — anything scripted against it silently gets the opposite
result.

### The jobs are not bootstrapped anywhere in launchd

`processes.json` did move once, at 23:50:37, after six hours frozen — then
stopped again for the next 3+ minutes despite a 5s `StartInterval`. That single
write was `RunAtLoad` firing when smd re-registered, not the schedule resuming.

`launchctl dumpstate` settles where the jobs are: both labels appear **only** in
the gui domain's enabled/disabled table, and nowhere as services.

```
$ launchctl print gui/502/com.deck.agent.processes
Could not find service "com.deck.agent.processes" in domain for user gui: 502
$ launchctl dumpstate | grep com.deck.agent
        "com.deck.agent"           => enabled
        "com.deck.agent.processes" => enabled     ← the enabled table, not a job
```

For contrast, the running app *is* a real job in that domain
(`application.com.deck.app.214258026.214258034`, PID 26427).

So the state is precisely: **BTM record present and allowed, launchd job absent.**
`SMAppService.status` reports `.enabled` from the former and knows nothing of
the latter, which is why Deck sees a healthy install. CLAUDE.md's recovery —
"the next login, or a toggle-off/on cycle" — stands, and route 3 above shows the
toggle cycle cannot be driven from outside the app.

**Blocking:** Phase 3 needs live agents and cannot get them non-interactively.

### Recovery confirmed — the in-app toggle works, and proves the blind spot

The user cycled **General → Refresh in background** off/on at 23:58.

```
23:58:02  processes.json written   ← first agent write in 6h 07m
23:58:27  processes.json written   ← 25s later: the 15s throttle on the 5s tick
BTM Generation: 20 → 34
```

Sustained, not a `RunAtLoad` blip — which is what distinguishes this from the
single 23:50:37 write earlier.

The launchd state before and after is the whole finding:

| | before the toggle | after |
|---|---|---|
| `launchctl print gui/502/com.deck.agent.processes` | `Could not find service` | full job description |
| `state` | — | `spawn scheduled` |
| `managed_by` | — | `com.apple.xpc.ServiceManagement` |
| `path` | — | `(submitted by smd.96162)` |
| BTM uuid | `100D7241-ED8C-401A-863E-5C966EB3B1E3` | **same uuid** |
| BTM disposition | `[enabled, allowed]` | `[enabled, allowed]` |

**The BTM record was identical throughout — same UUID, same disposition — while
the launchd job went from absent to scheduled.** That is the blind spot stated
as a measurement: `SMAppService.status` reads the left column and cannot see the
right one. Six hours of no background refresh, and every signal Deck consults
said healthy.

### A second thing this proves, for R3

```
gui/502/com.deck.agent.processes = {
    program identifier = Contents/MacOS/DeckAgent (mode: 2)
    parent bundle identifier = com.deck.app
    parent bundle version = 35
}
```

The job stores a **relative** program path resolved through the parent bundle
identifier, not an absolute path to a specific binary. This is the R3 mechanism
visible in launchd's own state, not inferred from the BTM dump: replace the
bundle at `/Applications/Deck.app` and this job runs whatever `Contents/MacOS/
DeckAgent` is now there — under the **old** label, with the **old** parent
bundle identifier recorded. Phase 3 can now measure what that does for real.

---

## Phase 2–3 — the renamed build (2026-08-29 00:01–00:10)

Built and installed `io.github.haqaliz.deck` v1.36 over `/Applications/Deck.app`.
The real v1.35 bundle was `ditto`'d to the scratchpad first (12 MB, signature
verified) so the restore would not depend on a rebuild.

### R2 — signing identity: fixed, and the second identifier is gone

```
Deck.app             Identifier=io.github.haqaliz.deck
DeckAgent            Identifier=io.github.haqaliz.deck.agent
DeckWidgets.appex    Identifier=io.github.haqaliz.deck.widgets
```

Giving DeckAgent an explicit `PRODUCT_BUNDLE_IDENTIFIER` removed the synthesised
`<prefix>.DeckAgent` entirely — the generated `project.pbxproj` now has eight
`PRODUCT_BUNDLE_IDENTIFIER` lines and **none** of them disagrees with its
target's `CFBundleIdentifier`. `codesign -dv` belongs in the flip's gate; it is
the only check that sees what TCC will key the grant to.

### O1 — ANSWERED: containermanagerd provisions the new container by itself

**The new container existed before the app was ever launched — and before it was
even installed.** It was created at 00:01:18, during the *build*, by the
`RegisterWithLaunchServices` phase (`lsregister`).

```
$ ls -la ~/Library/Containers/io.github.haqaliz.deck.widgets/
700  Data/
644  .com.apple.containermanagerd.metadata.plist   596B
$ find Data -maxdepth 2 -type d
./Documents  ./Library  ./Library/Application Scripts
./Library/Application Support  ./Library/Caches  ./Library/Images
./Library/Logs  ./Library/Preferences  ./Library/Saved Application State
./SystemData  ./tmp
```

That is the complete standard skeleton — the exact directory list
`scripts/container-repair.sh` recreates — plus the home symlinks (`Desktop`,
`Downloads`, `Movies`, `Music`, `Pictures`, `.CFUserTextEncoding`) and a real
metadata plist. A hand-made `mkdir -p` from `AtomicFile` produces none of that.

**Consequence for the migration:** the feared case does not arise. Registering
the bundle is enough; by the time the app runs after any normal install the
container is provisioned by the OS. The migration can write into it directly at
launch, and does **not** need to poll for the extension's first run. `AtomicFile`
creating `Library/Application Support/Deck` inside an already-provisioned
container is ordinary file I/O.

### R3 — REFUTED: the old job does not run the new binary; it fails to spawn

The PRD predicted the old label would execute the replaced binary and pollute
the new container with default-settings snapshots. It does not.

```
$ launchctl print gui/502/com.deck.agent.processes
    program identifier      = Contents/MacOS/DeckAgent (mode: 2)
    parent bundle identifier = com.deck.app        ← records the OLD identity
    parent bundle version    = 35
    last exit code          = 78: EX_CONFIG
    job state               = spawn failed
```

Both old jobs report `job state = spawn failed`, and `com.deck.agent.processes`
exits **78 / EX_CONFIG**. The job stores the parent bundle *identity*, not just
a path, so when the bundle at that path becomes `io.github.haqaliz.deck` v1.36
the mismatch is refused rather than resolved.

Measured consequences, both confirmed:

- The **old container stopped being written** the moment the bundle was
  replaced — `processes.json` frozen at 00:02:29 across three later checks.
- The **new container got no `Deck/` directory at all** until the app itself
  launched. The agent never ran.

So the migration does not need to live in `DeckAgent` *for R3's reason*. It is
still worth putting in `Shared` and calling from both, because the app is not
guaranteed to be first in general — but the specific default-settings
corruption R3 predicted cannot happen.

**The flip's real cost is the opposite one:** after the rename, background
refresh is **dead** until the user launches Deck and it registers the new
agents. Combined with the Phase 1 finding — Deck cannot see a registered-but-
unloaded agent — that is a window in which nothing runs and nothing says so.

### O2 — ANSWERED, and worse than expected: two permanent orphans

After launching the renamed Deck:

```
$ sfltool dumpbtm | grep -E "Identifier: [0-9]+\.(com\.deck|io\.github)"
    Identifier: 2.io.github.haqaliz.deck
    Identifier: 8.com.deck.agent                    ← dead
    Identifier: 8.com.deck.agent.processes          ← dead
    Identifier: 8.io.github.haqaliz.deck.agent      ← live
    Identifier: 8.io.github.haqaliz.deck.agent.processes
  4 Parent Identifier: 2.io.github.haqaliz.deck
```

Three findings:

1. **The old app record `2.com.deck.app` is gone entirely** (grep count: 0). BTM
   did not keep two app records; it replaced the one at that URL.
2. **The two dead agent records were re-parented to the new app** — all four now
   carry `Parent Identifier: 2.io.github.haqaliz.deck`, and the dead pair's
   `Generation` reset to 0. So Login Items shows **four** DeckAgent rows under
   Deck, two of which can never run.
3. **They cannot be removed.** `launchctl bootout` fails with
   `3: No such process` (they are not running), and the records survive it. The
   new app cannot `SMAppService.unregister()` them either: that call resolves a
   plist **inside the current bundle**, and the renamed bundle no longer ships
   `com.deck.agent.plist`.

**Design consequence for the flip — a concrete fix.** Ship the **old-named**
plists in the new bundle for exactly one release, alongside the new ones, purely
so the renamed app can construct `SMAppService.agent(plistName:
"com.deck.agent.plist")` and call `unregister()` on it. Drop them the release
after. This is the same one-release-courtesy shape as the existing
`legacyCleanup()` and is the only route that removes the records rather than
hiding them.

### Not verified

Whether a widget **renders** from the new container. The new extension registers
(`pluginkit -m -i io.github.haqaliz.deck.widgets` → `io.github.haqaliz.deck.widgets(1.36)`)
but shows without the `+` active marker, and no widget was added, so no timeline
was written and `Data/SystemData/com.apple.chrono/` does not exist. Given the
container carries the full, OS-provisioned skeleton, the `unsupportedEntryKey`
failure mode that motivated the question cannot arise — but rendering itself was
not observed, and the flip's manual gate must still do it.

### Old container: untouched throughout

`settings.json` 23:58:27, `gitbox.json` 00:02:12, `processes.json` 00:02:29 —
all unchanged after the swap, and 15 timeline directories intact. The renamed
Deck never read or wrote the old container, which is the behaviour the migration
will have to add deliberately.

### O2 correction — `unregister()` disables the record, it does not delete it

The user switched **Refresh in background** off in the renamed build before the
restore. The result corrects what was written above:

```
Disposition: [enabled,  allowed, not notified] (0x3)  8.com.deck.agent            ← dead, untouched
Disposition: [enabled,  allowed, not notified] (0x3)  8.com.deck.agent.processes  ← dead, untouched
Disposition: [disabled, allowed, notified]     (0xa)  8.io.github.haqaliz.deck.agent            Generation: 2
Disposition: [disabled, allowed, notified]     (0xa)  8.io.github.haqaliz.deck.agent.processes  Generation: 2
```

`SMAppService.unregister()` flips the record to **`[disabled, allowed]`** and
bumps its generation; **the BTM record itself persists**. So the "ship the
old-named plists for one release" fix does not *remove* the orphans either — it
converts them from `enabled`-but-unrunnable into `disabled`, which is the
honest state and is what Login Items should show. That is still worth doing
(an `enabled` record whose job fails with EX_CONFIG is a lie), but the flip
should not promise the records disappear. Nothing short of `sfltool resetbtm` —
which wipes every login item for every app — removes them.

## Restore (00:10–00:15)

`ditto` of the backed-up v1.35 bundle over `/Applications/Deck.app`:
`Identifier=com.deck.app`, `CFBundleShortVersionString 1.35`,
`codesign --verify --deep --strict` passes, `pluginkit` back to
`+    com.deck.app.widgets(1.35)`. `settings.json` in the old container is
untouched — 16 keys, 4 accounts, `agentAtLogin: true`. LaunchServices swept:
the renamed dev copy was `lsregister -u`'d and `scripts/lsclean.sh` re-registered
`/Applications`; zero `io.github.haqaliz.deck` bundles remain known to LS.

**`scripts/lsclean.sh` could not do this on its own** — it hardcodes
`com.deck`, so it cannot unregister a dev copy built under any other id. Phase 9's
`scripts/lib/ids.sh` must cover it, and during the flip release both ids need
sweeping.

### The round-trip reproduced the Phase 1 fault deliberately

After the restore, `com.deck.agent` and `com.deck.agent.processes` are
`[enabled, allowed]` with **no launchd job** and `processes.json` frozen — the
exact registered-but-unloaded state from Phase 1, arrived at through a bundle
swap rather than a mystery. `SMAppService.status` reports `.enabled`,
`AgentReconcilePolicy` correctly does nothing, and Deck shows a healthy toggle.

**This is the strongest argument for the liveness check** proposed in Phase 1:
the rename *will* put every user into this state, and without a check Deck will
tell them background refresh is on while nothing runs. The flip should not ship
before it.

## Rollback is not symmetric — and that is a probe artifact, not a flip risk

Restoring v1.35 over the renamed bundle left the machine in a state the forward
flip never produces. Recorded because it cost time and would cost it again.

**Forward (what users will experience) worked.** With the renamed build
installed, its own agents registered and ran:

```
gui/502/io.github.haqaliz.deck.agent.processes
    parent bundle identifier = io.github.haqaliz.deck
    parent bundle version    = 36
    last exit code           = 0
    job state                = exited          ← normal: runs and exits
```

**Backward did not.** After `ditto`-ing v1.35 back over the same path and a
user-driven off→on toggle, both `com.deck.agent*` jobs exist but refuse to
start — `runs = 15`, every one `78: EX_CONFIG`, `job state = spawn failed` —
while the binary itself is fine:

```
$ DECK_AGENT_ROLE=processes /Applications/Deck.app/Contents/MacOS/DeckAgent
exit=0        ← and processes.json was written
```

The cause is visible in BTM: **two app records now claim the same URL.**

```
Identifier: 2.io.github.haqaliz.deck   URL: file:///Applications/Deck.app/
Identifier: 2.com.deck.app             URL: file:///Applications/Deck.app/
```

Each with its own two agents correctly parented. During the forward step there
was only ever **one** app record for that URL — BTM had *replaced*
`2.com.deck.app` rather than adding alongside it. Restoring recreated it without
removing the first, and launchd will not spawn a `BundleProgram` job whose path
is claimed by an ambiguous registration.

Things that did **not** fix it: the in-app off→on toggle (it re-registered the
jobs — they went from absent to present — but they still fail to spawn),
`launchctl kickstart -k`, and `killall smd` (smd is not user-killable).
`sfltool resetbtm` would, but it wipes every login item for every app on the
machine. The documented reset — **the next login** — is the proportionate fix,
and CLAUDE.md already names it for this class of fault.

**Implication for the flip: none, in the forward direction.** The implication is
for *rollback*: if the flip has to be reverted, users who downgrade will land in
this state and a relaunch will not save them. If a rollback path is ever
promised, it has to say "log out and back in", because nothing the app can do
from inside repairs it.

### One measurement muddied

`processes.json` at 00:19:42 was written by a **hand-run** of the agent during
this diagnosis, not by launchd. Anyone reading mtimes on this machine after that
timestamp should discount it.

## Build hygiene: `Embed LaunchAgents` never removes stale plists

Found while verifying Phase 5. The post-build script in `project.yml:26-29` is
`mkdir -p` followed by two `cp`s — it never clears the destination. So an
**incremental** build across the rename leaves both generations in the bundle:

```
$ ls .../Release/Deck.app/Contents/Library/LaunchAgents/
com.deck.agent.plist                       ← current build
com.deck.agent.processes.plist             ← current build
io.github.haqaliz.deck.agent.plist         ← left by the probe build
io.github.haqaliz.deck.agent.processes.plist
```

Deleting the app bundle and rebuilding produces the correct two. The stale pair
is sealed into the signature like any other resource, so nothing complains.

**Why this is a trap for the flip specifically.** The O2 fix deliberately ships
the *old-named* plists for one release so the renamed app can `unregister()`
the orphaned records. If the build phase is also leaving them there by accident,
a passing test of that behaviour proves nothing — and the release *after*, which
is supposed to drop them, would keep shipping them from stale derived data.

**Fix for Phase 8/9:** make the script `rm -rf` the destination directory before
copying, so its contents are always exactly what `project.yml` names. Until
then, the flip must be built from a clean `build.noindex`.
