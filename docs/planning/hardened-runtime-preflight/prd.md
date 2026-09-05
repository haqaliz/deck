# PRD — Hardened-runtime pre-flight

**Slug:** `hardened-runtime-preflight` · **Type:** feat · **Branch:** `feat/hardened-runtime-preflight/aliz`
**Written:** 2026-09-06 · **Precedes:** `docs/planning/notarization/runbook.md` Step 2

## The ask, in one sentence

Turn on `ENABLE_HARDENED_RUNTIME` for the three shipping targets under the
signing identity Deck already has, ship it, and prove on a real install that
nothing broke — so the day the $99 program is bought, the release changes the
certificate and only the certificate.

## Why this is a unit of work and not a one-line diff

Notarization changes four things in one release: the signing identity, the
hardened runtime flag, the CI build flags, and (by decision) the bundle
identifier. That release resets every user's TCC grants and forces every user to
re-add their widgets, and its rollback is documented as **not symmetric** — two
BTM records claiming one URL, both agents refusing to spawn with `EX_CONFIG`,
repaired only by replacing the bundle and pressing **Restart agents** (ROADMAP
M7; `docs/planning/agent-liveness/verification.md`).

Debugging a hardened-runtime fault *inside* that release means debugging it
with three other variables moving. Debugging it now means `cp -R` of the
previous build.

The runbook already anticipates this. Step 2 says, of hardened runtime:
"Nothing Deck does should need an exception, **but confirm rather than assume**."
This is that confirmation, moved to a day when it is cheap.

## Baseline (measured 2026-09-06, installed v1.40)

```
/Applications/Deck.app                flags=0x0(none)   entitlements: none at all
  …/PlugIns/DeckWidgets.appex         flags=0x0(none)   com.apple.security.app-sandbox
  …/MacOS/DeckAgent                   flags=0x0(none)   com.apple.application-identifier
Authority=Apple Development: haqaliz@aol.com (YJ32Z93LB5) · Team K6X49DG8VF
No Contents/embedded.provisionprofile
agent-heartbeat.json 00:36:32 · processes.json 00:37:55 · now 00:38:13 — both agents alive
```

`native/project.yml` says `ENABLE_HARDENED_RUNTIME: NO` for DeckApp (`:51`) and
DeckWidgets (`:88`), and **says nothing at all for DeckAgent** — which is one of
the two failure modes the runbook names for a first `Invalid` notarization ("a
target that missed `ENABLE_HARDENED_RUNTIME`"). Absent and `NO` look different
in the file and identical in the product, which is precisely why the fix needs a
drift guard and not just an edit.

## What changes

### Build inputs

| Target | Now | After |
|---|---|---|
| DeckApp | `ENABLE_HARDENED_RUNTIME: NO` | `YES` |
| DeckWidgets | `ENABLE_HARDENED_RUNTIME: NO` | `YES` |
| DeckAgent | *(key absent)* | `YES` |
| DeckSharedTests | *(key absent)* | *(unchanged — a test bundle is not notarized)* |

The key goes in `settings.base`, so it covers Debug and Release alike: what a
developer runs should be what a user gets, and `get-task-allow` coexists with
hardened runtime (that is how Xcode debugs a hardened app). `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`
stays exactly where it is, under `configs: Release:`.

Deck therefore gets hardened runtime **in its strictest form** — library
validation on, zero exception entitlements on the app, one sandbox entitlement
on the extension. That is the right posture and also the one with the least
margin, so it is measured rather than assumed.

### A drift guard, because absence is invisible

A new `HardenedRuntimeTests` in `DeckSharedTests`, modelled on the existing
`DeckBundleTests` (which already reads `native/project.yml` through `#filePath`
and fails the suite when a build input drifts from what the code believes).

It must fail for the DeckAgent shape specifically — a target that declares the
key nowhere — because that is the shape that shipped today and the shape a
future target will arrive in. Asserting "the file contains `ENABLE_HARDENED_RUNTIME: YES`"
would have passed on the broken tree the moment one target was fixed, so the
guard is per target, not per file.

### Documentation

- `docs/planning/notarization/runbook.md` — Step 2 keeps the identity switch and
  loses the runtime half, pointing here for what was already proven; its
  "Hardened runtime: what to watch" list gains the measured answers.
- `ROADMAP.md` — the M7 notarization entry records that the runtime flag is
  already live, and the stale Homebrew claim that "`--no-quarantine` is what
  spares users the `xattr` dance" goes: Homebrew removed that flag, `README.md:92`
  and `homebrew/deck.rb:13` already say so, and the ROADMAP is the last copy
  telling a reader to use an uncommand.
- `CLAUDE.md` — a signing note only if something is actually measured worth
  keeping. No finding, no note.

## What does not change

- **The signing identity.** Still `Apple Development`. This work has nothing to
  say about Gatekeeper, quarantine, or the 2027-08-09 expiry cliff; those need
  the paid program and the runbook already covers them.
- **`-allowProvisioningDeviceRegistration` in CI.** The runbook drops it as part
  of the Developer ID switch. On a fresh `macos-latest` runner under automatic
  Apple Development signing it is what lets xcodebuild register the runner, so
  removing it now risks the release job for no gain in this slice. It stays, and
  the runbook keeps it as Step 2's remaining half.
- **The bundle identifier.** Prepared, dormant, rides notarization by decision.
- **Any widget, face, setting, snapshot or loader.** No user-visible surface
  changes at all — which is the point, and also what makes "nothing broke" the
  entire specification.

## Non-goals

- Not notarization, not stapling, not `notarytool`, not Sparkle.
- Not a second-Mac verification (the other unchecked M7 item; needs hardware).
- Not hardening beyond the flag — no new entitlements, no exceptions, no
  `com.apple.security.cs.*` anything. If one turns out to be needed, that is a
  finding to report, not a thing to quietly add.

## There is no face

Deck's PRDs describe a front face and a back face. This one has neither: no
widget, no settings control, no snapshot, no cadence. The user-visible spec is
**that every existing face keeps working**, and the deliverable is the evidence.

## Acceptance criteria — the pass mark, stated so it can fail

Against the copy installed in `/Applications` (never `build.noindex`, which
cannot register with SMAppService):

1. **All three binaries report the flag.** `codesign -dvvv` shows
   `flags=0x10000(runtime)` for `Deck.app`, `DeckWidgets.appex` and `DeckAgent`.
   Zero of three or two of three is a failure, not a partial pass.
2. **The extension still registers.** `pluginkit -m -i com.deck.app.widgets`.
3. **All fourteen widgets render**, re-added from the gallery, at all three
   sizes. (User action; everything else here is mine.)
4. **Both agents write.** `processes.json` and `agent-heartbeat.json` mtimes
   advance after the install — checked *after* a relaunch, because replacing the
   bundle takes the running jobs down without reloading them (CLAUDE.md).
5. **The SPI survives inside the sandbox.** BatBox's accessory section matches
   `pmset -g accps`. The extension is the only place this counts; a CLI answer
   proves nothing about `@_silgen_name` under a sandboxed, hardened extension.
6. **Subprocesses still run.** DevBox lists TCP ports and Docker containers,
   GitBox shows commits — i.e. `ps`, `docker` and `git` all spawned.
7. **TCC grants survive.** CalBox still renders events and no new permission
   prompt appears. This is the highest-value measurement in the slice: the
   notarization release *will* reset these, and knowing the runtime flag alone
   does not is what separates the two causes.
8. **AMFI is silent.** `log stream --predicate 'sender == "AMFI"'` records
   nothing across a full 60s agent tick.
9. **The suite is green**, including the new drift guard, and the guard is shown
   failing on the pre-change tree before it is shown passing on the post-change
   one.

## Failure policy

If a criterion fails, the finding is written down before anything is fixed, and
the fix is chosen in the open: an exception entitlement is a **last** resort and
is a reportable outcome, because "Deck needs a hardened-runtime exception" is
exactly the kind of fact the runbook was written to surface early. Reverting the
flag and shipping without it is a legitimate outcome too — the value of this
work is the answer, not the flag.

## Risk register

| Surface | Risk | Basis |
|---|---|---|
| Library validation | Low | No third-party dylibs; `-lsqlite3` is the system copy; the appex is loaded by the system's extension host, not by Deck |
| `@_silgen_name` IOKit SPI | Low | A link-time symbol against Apple-signed IOKit, not a `dlopen`. Private API is an App Store review matter, not a notarization one (runbook Step 2) |
| Subprocess spawn (`ps`/`git`/`docker`/`launchctl`) | Low | Hardened runtime restricts injection *into* a process, not what it spawns |
| TCC grants | Low, high consequence | Keyed on the code requirement (team + identifier), which is unchanged; only the CDHash moves |
| SMAppService jobs | Not a risk of the flag, but of every install | Replacing the bundle takes the jobs down without reloading them; verification must relaunch before reading a witness |

## Open questions — none

Three were put to the user on 2026-09-06 and answered: ship it enabled rather
than measure-and-revert; leave the CI flag alone and note it in the runbook;
verify with the full install ritual on this Mac. All three are folded in above.

---

# Self-critique (2026-09-06)

Two red, six amber. Every fix is folded into the amendments below the list, and
the sections above are amended to match.

## 🔴 Red

**R1 — Two of the nine criteria could pass against a binary this work never
built.** The verification renders widgets and reads snapshots, and both of those
can be served by the *previous* extension. CLAUDE.md records that WidgetKit
caches the widget descriptor set per extension version and that a stale
LaunchServices registration makes it resolve the wrong bundle entirely. Nothing
in the PRD bumped the version or pinned the identity of the thing under test, so
"BatBox still lists an accessory" was not evidence about the hardened build.
**Fix:** the release carries a version bump (1.40 → 1.41 in all three targets),
`scripts/lsclean.sh` runs after the build as CLAUDE.md requires, and the runtime
flag is read from the **installed** binary before any behavioural criterion is
believed — `flags=0x0` there means the install did not take and everything after
it is void.

**R2 — "AMFI is silent" cannot fail on this machine.** CLAUDE.md records, from
the Swift Charts investigation, that the unified log can be *entirely empty*
here — the documented `log show` check was unusable for exactly that reason. A
criterion that reports success when logging is broken is not a criterion.
**Fix:** AMFI becomes supporting evidence, not load-bearing, and it is only
admissible after a positive control shows the stream is alive in the same
window (any predicate that must produce output — e.g. the agent's own
`subsystem == "com.deck.agent"` across a tick). The load-bearing evidence is
behavioural: the SPI answers, the subprocesses ran, the witnesses advanced.

## 🟡 Amber

**A1 — "all fourteen widgets at three sizes" is 42 checks and will not be done.**
A verification nobody completes is worse than a smaller one that is.
**Fix:** the gallery must *enumerate* all fourteen (one check, and the exact
symptom the Charts trap produces when it fails), and five widgets are actually
re-added, chosen because each covers a distinct risk surface: **BatBox** (the
`@_silgen_name` SPI inside the sandbox), **DevBox** (`docker` + port scan
subprocesses), **CalBox** (the TCC grant), **LiveBox** (the self-sampled mach
path, the one that renders without any agent), **GitBox** (the agent-pumped
snapshot path). One size each, plus one large face to catch a size-specific
layout crash.

**A2 — The drift guard as described would rot.** "Assert the file contains
`ENABLE_HARDENED_RUNTIME: YES`" passes as soon as *one* target has it, which is
the bug that shipped. Worse, a hardcoded list of three target names cannot catch
the next target somebody adds.
**Fix:** the guard enumerates the targets out of `project.yml` itself and
requires the key to be `YES` for every target except `DeckSharedTests`, which it
names as the single explicit exemption. A new target fails the suite until
someone decides which side it is on. It must be demonstrated failing against all
three broken shapes — `NO`, key absent, and a fourth target added without the
key.

**A3 — The TCC and subprocess criteria can be satisfied by stale snapshots.** A
face showing calendar events proves the *snapshot* has events, not that the
agent re-read the calendar under the new signature; CLAUDE.md is explicit that a
dead agent is invisible while Deck is open, because the host app pumps every
snapshot except `processes.json`.
**Fix:** the witnesses are checked **first** and the snapshot **mtimes** are
what count, not their contents — the same rule the liveness work landed on. No
face is admitted as evidence until `agent-heartbeat.json` and `processes.json`
have both advanced past the install.

**A4 — The PRD claims rollback is "`cp -R` of the previous build" while nothing
preserved that build.** The baseline and the hardened build share one
`derivedDataPath`, so the first hardened build destroys the thing rollback
depends on.
**Fix:** done before this critique was written — the v1.40 Release build was
made and copied aside (`CDHash=155a9e3e…`, `flags=0x0(none)`) so a revert is a
copy and a relaunch, not a rebuild from a stashed diff.

**A5 — Shipping this means the CI job can silently drop the flag later.** The
unit guard covers `project.yml` drift; it does not cover a build that produces
an unhardened binary anyway (an override, a toolchain change, a target added to
the scheme). The repo has already been burned once by a green run publishing an
artifact nobody opened — the HFS+ DMG.
**Fix:** the release job asserts on the built product before packaging —
`codesign -dvvv` on the app, the appex and the agent, failing the job unless all
three report `runtime`. Same lesson, same shape as the `hdiutil verify` gate.

**A6 — "`get-task-allow` coexists with hardened runtime" is stated as fact with
no measurement behind it.** It is true, and it is also exactly the kind of
inherited belief this repo's docs make a point of not asserting.
**Fix:** either a Debug build is made and launched as part of the work, or the
sentence is downgraded to what it is — the reason the key goes in `settings.base`
rather than an assurance — and the measured claim is confined to Release.

**A7 — The runbook edit could leave Step 2 self-contradictory.** Step 2 currently
switches identity *and* runtime in one block, with one gate that greps for both
`Authority=Developer ID` and `flags=.*runtime`. Removing half a step and leaving
its gate intact is how a runbook starts lying.
**Fix:** Step 2 keeps the combined gate (it stays correct — the flag will be on),
but its instruction block loses `ENABLE_HARDENED_RUNTIME` and gains a line
saying it is already live and pointing at this folder's verification record.

**A8 — Nothing said what happens to the version number if the work is
abandoned.** With A4's rollback path, a reverted flag would leave a 1.41 that is
identical to 1.40.
**Fix:** the version bump lands in the *same commit* as the flag, so reverting
that commit reverts both.

## Amendments to the spec above

1. **Version:** 1.40 → **1.41** in all three targets, in the same commit as the
   flag.
2. **Acceptance criterion 1 is a gate, not a criterion:** read the flag off the
   installed binary first; if it is not `runtime` on all three, stop — nothing
   after it means anything.
3. **Criterion 3 becomes:** the gallery enumerates fourteen widgets, and BatBox,
   DevBox, CalBox, LiveBox and GitBox are re-added and render (one large among
   them).
4. **Criterion 4 moves ahead of 5–7** and is worded on mtimes: both witnesses
   advance after a post-install relaunch, before any face is read as evidence.
5. **Criterion 8 (AMFI) becomes supporting evidence** and requires a positive
   control on the log stream before its silence is admissible.
6. **New criterion 10:** the release workflow fails if the built app, appex or
   agent lacks the `runtime` flag.
7. **The drift guard enumerates targets from `project.yml`**, exempts only
   `DeckSharedTests` by name, and is demonstrated failing on three broken shapes.
8. **Rollback is named:** `$SCRATCH/baseline-Deck.app` (v1.40, `flags=0x0`),
   preserved 2026-09-06 before the first hardened build.
