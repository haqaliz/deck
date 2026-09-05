# Verification — hardened runtime under the existing identity

**Run:** 2026-09-06, 01:02–01:10, on the dev Mac (macOS 26.6 / Darwin 25.5.0, Xcode 26.6).
**Build under test:** v1.41, `ENABLE_HARDENED_RUNTIME: YES` on DeckApp,
DeckWidgets and DeckAgent, still signed `Apple Development: haqaliz@aol.com`,
team `K6X49DG8VF`.
**Rollback held throughout:** `baseline-Deck.app` (v1.40, `flags=0x0(none)`,
`CDHash=155a9e3e…`), built and set aside before the first hardened build.

Everything below was measured against the copy installed in `/Applications`.
Negative and ambiguous results are kept as they came.

---

## Gate — the thing under test is the thing installed

| Binary | Flags | |
|---|---|---|
| `Deck.app` | `flags=0x10000(runtime)` | ✅ |
| `Deck.app/Contents/PlugIns/DeckWidgets.appex` | `flags=0x10000(runtime)` | ✅ |
| `Deck.app/Contents/MacOS/DeckAgent` | `flags=0x10000(runtime)` | ✅ |

`CFBundleShortVersionString` = **1.41**.
`codesign --verify --deep --strict` → *valid on disk*, *satisfies its Designated Requirement*.
`pluginkit -m -i com.deck.app.widgets` → **`com.deck.app.widgets(1.41)`** — the
new version is what is registered, so nothing below is measuring the previous
extension (critique R1).

**Entitlements are unchanged by the flag**, which was the thing to check on a
codebase that carries almost none: the app still has **no entitlements at all**,
the extension only `com.apple.security.app-sandbox`, the agent only
`com.apple.application-identifier`. No `com.apple.security.cs.*` exception was
needed, so Deck runs hardened in its strictest form, library validation
included.

## The app launches, twice

Launch → 6s → still running (pid 89734). Quit → relaunch → still running (pid
90352). No crash reports for `Deck` or `chronod` in the window. The
quit/relaunch is not ceremony: replacing the bundle takes the running agents
down without reloading them, so a witness read before a relaunch proves nothing.

## Both agents run under hardened runtime

| Witness | Before install | After |
|---|---|---|
| `agent-heartbeat.json` (60s agent's single writer) | 01:02:46 | **01:04:07** ✅ |
| `processes.json` (fast agent's single writer) | 01:03:04 | **01:05:07** ✅ |

Checked before any face was read (critique A3). All 21 files in the container
were rewritten between 01:05 and 01:06.

From the agent's own log — which is also the positive control for the AMFI check
below:

```
01:07:50.440  DeckAgent[97054]  written processes snapshot
01:07:50.675  DeckAgent[95841]  written marketbox snapshot (5 rows)
01:07:50.675  DeckAgent[95841]  full refresh done in 33.38s
01:08:00.494  DeckAgent[97479]  skipped processes snapshot (throttled)
```

## Subprocesses still spawn from a hardened agent

The sandbox-blocked data path is the one that would break loudest, and it is
intact:

| Evidence | Reading | Proves |
|---|---|---|
| `processes.json` | 10 rows (`NotificationCent`, `WindowServer`, …) | `ps` |
| `devbox.json` | 9 listening ports (e.g. `4321 Python`) | the port scan |
| `devbox.json` | `dockerState = noContainers`, 0 containers | **`docker` ran** — and `docker ps` independently reports 0 containers, so the empty list is the truth, not a failed spawn. The snapshot distinguishes the two states, which is why this is evidence rather than a shrug |
| `gitbox.json` | today 8, streak 15, 91 repos | `git log` |

## TCC survived the re-signature

`calbox.json` holds **6 real events** from `aliz@foresightanalytics.ca`, written
at 01:06:07, with `fetch-calbox.json` = `{"outcome":"ok"}`. **No permission
prompt appeared.** So the calendar grant — and the "access data from other apps"
grant the process list needs — both survived a changed CDHash under an unchanged
code requirement.

This is the most useful single fact in the run: the notarization release *will*
reset these grants, and now it is known that the runtime flag is not what does
it.

> Recorded because it was tried: `calbox.json` has an `events` array, not
> `today`/`tomorrow` keys. A first read against the wrong key names printed
> "0 today, 0 tomorrow" and looked exactly like a revoked grant. Reading
> `TCC.db` directly is not available as a cross-check either — *authorization
> denied* without Full Disk Access. The agent's own `fetch-*.json` verdict is
> the check that works.

## The sandboxed extension runs and renders

chronod launches the hardened extension as its own process and schedules
timelines against it:

```
01:08:48.697 chronod  Update … {definition:com.deck.app.widgets[extension][client]}:88937
01:08:48.697 chronod  [com.deck.app::com.deck.app.widgets:LiveBoxWidget] Scheduled …
```

All **fourteen** current widget kinds appear in chronod's traffic: BatBox,
CalBox, ClipBox, ClockBox, DevBox, GitBox, LiveBox, MarketBox, NetBox, OpenBox,
PRBox, ShipBox, TaskBox, WeatherBox.

### Reload failures: pre-existing, not caused by this

chronod reports a mix of succeeded and failed reloads. Rather than guess, the
same count was taken from the log's own history for the **unhardened v1.40**
that was running an hour earlier:

| Window | Build | failed | succeeded | failure rate |
|---|---|---|---|---|
| 00:50–01:03 | v1.40, `flags=0x0` | 309 | 2430 | **11.3%** |
| 01:04:30 → | v1.41, hardened | 111 | 890 | **11.1%** |

Unchanged. The failures are two pre-existing classes, neither related to signing:

- **`CHSErrorDomain 1100 "No matching descriptor was found"` for
  `HomeBoxWidget`** — 132 of them. HomeBox was split into WeatherBox and
  ClockBox; chronod still holds archived timelines for a widget kind the
  extension no longer declares. Harmless log noise, worth cleaning up
  separately.
- **`CHSErrorDomain 1103 "Intent configuration is required but was not
  provided."`** — 3, on non-HomeBox kinds.

## AMFI said nothing, and the check earns the right to say so

The critique (R2) flagged that "AMFI is silent" is worthless on a machine whose
log may be empty, so silence was only admitted after a positive control:

| Query (`--last 10m --info --debug`) | Result |
|---|---|
| everything, last 2m | 158,607 lines — the log is alive |
| `subsystem == "com.deck.agent"` | agent ticks present (above) — **control passes** |
| `sender == "AMFI"` | **0 lines** |
| Deck + `denied` / `invalid signature` / `library validation` | 0 (one self-match: the `log` command echoing its own predicate) |

> Worth keeping: without `--info --debug` **all four** queries return nothing,
> including the control. A first pass read that as a dead log and nearly filed
> AMFI silence as inadmissible. The agent's OSLog lines are `info` level;
> `log show` omits those by default.

## The rendered faces — confirmed by the user, 2026-09-06

Automated evidence cannot see a rendered face, so these were checked by eye on
the desktop against the hardened v1.41 install and reported back as working:

- [x] The Widget Center gallery **enumerates fourteen** Deck widgets.
- [x] **BatBox** — the accessory section renders, matching `pmset -g accps`
      taken at 01:07 (internal 80%, MX Master 3S 45%). This is the
      `@_silgen_name` `IOPSCopyPowerSourcesByType` SPI running inside a
      sandboxed **and now hardened** extension, which is the only place the
      binding's survival can be established; a CLI answer proves nothing about
      it.
- [x] **DevBox**, **CalBox**, **LiveBox**, **GitBox** re-added and rendering —
      covering the subprocess path, the TCC path, the self-sampled mach path
      (the one face that renders with no agent at all) and the agent-pumped
      snapshot path.

Stated at its real strength: this is a human confirmation that the faces look
right, not an instrumented pixel check. It is the same standard every Deck
widget has shipped under.

## The gate ran on a runner, not only on this Mac

CI, run 33994504529 on the PR branch — **success**, every step, with the signing
secrets present so the signed build path actually executed:

```
Verify hardened runtime
  ok   Deck.app                                     flags=0x10000(runtime)
  ok   Deck.app/Contents/PlugIns/DeckWidgets.appex  flags=0x10000(runtime)
  ok   Deck.app/Contents/MacOS/DeckAgent            flags=0x10000(runtime)
```

This settles something the local runs could not: a fresh `macos-latest` runner
signs **and hardens** all three targets under automatic Apple Development
signing with no change to the provisioning flags. The release job therefore
needs nothing further before the identity switch — which is also why
`-allowProvisioningDeviceRegistration` was left alone rather than removed on
spec.

## Verdict

Every criterion in the PRD passed. Hardened runtime costs Deck nothing measurable under its existing identity: no
entitlement exception, no AMFI event, no change in chronod's reload behaviour,
no lost TCC grant, and every subprocess path intact. The notarization release
can now change the certificate and only the certificate.
