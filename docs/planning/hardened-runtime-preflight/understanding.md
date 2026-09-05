# Understanding — hardened-runtime pre-flight

Written 2026-09-06, before the PRD. Everything below is measured on this
machine unless it says otherwise.

## What the work is really asking

Notarization (`ROADMAP.md` M7) changes **four things at once**: the signing
identity (Apple Development → Developer ID), the hardened runtime flag, the CI
build flags, and — by decision — the bundle identifier rides the same release.
Three of those four are individually capable of breaking Deck silently, and the
release they share is the one whose rollback is documented as **not symmetric**
(two BTM records claiming one URL, both jobs `EX_CONFIG`).

This unit of work pulls **one** of those variables forward and lands it under
the identity Deck already has, so the paid day changes the certificate and
nothing else. It is not "prepare for notarization"; it is "spend the hardened
runtime risk now, while a rollback is `cp -R` of a previous build".

## Baseline (measured, installed copy, v1.40)

```
/Applications/Deck.app                      flags=0x0(none)   entitlements: NONE
  Contents/PlugIns/DeckWidgets.appex        flags=0x0(none)   app-sandbox only
  Contents/MacOS/DeckAgent                  flags=0x0(none)   com.apple.application-identifier
Authority=Apple Development: haqaliz@aol.com (YJ32Z93LB5), Team K6X49DG8VF
No Contents/embedded.provisionprofile
Both agents alive: agent-heartbeat.json 00:36:32, processes.json 00:37:55 (now 00:38:13)
```

`flags=0x0(none)` on all three is exactly what this work changes to
`flags=0x10000(runtime)`. It is also the check that proves it landed on all
three rather than on the ones that were easy.

Two baseline details worth keeping:

- **The app bundle carries no entitlements whatsoever** — `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`
  plus no entitlements file means hardened runtime lands in its strictest form
  (library validation on, no exceptions). That is the correct posture for Deck
  and also the one with the least margin, so it must be measured rather than
  assumed.
- **DeckAgent does carry one** (`com.apple.application-identifier`), injected by
  automatic signing rather than by the base-entitlements switch. Noted so a
  future reader does not conclude the switch is leaking.

## Affected files

| File | Change |
|---|---|
| `native/project.yml:51` | `ENABLE_HARDENED_RUNTIME: NO` → `YES` (DeckApp) |
| `native/project.yml:88` | `ENABLE_HARDENED_RUNTIME: NO` → `YES` (DeckWidgets) |
| `native/project.yml` ~:123 | key **absent** on DeckAgent → add `YES` |
| `native/SharedTests/…` | new drift guard, modelled on `DeckBundleTests` |
| `docs/planning/notarization/runbook.md` | Step 2 loses the half this work did |
| `ROADMAP.md` | M7 entry + the stale `--no-quarantine` claim |

`DeckSharedTests` is deliberately excluded — the runbook names three shipping
targets, and a test bundle is not notarized.

## Why the risk is low but not zero, per surface

- **Library validation.** Deck loads no third-party dylibs; `-lsqlite3` is the
  system copy and the widget extension is loaded by the system's extension
  host, not by Deck. Low.
- **`@_silgen_name("IOPSCopyPowerSourcesByType")`**
  (`native/DeckWidgets/Loaders/BatteryMetrics.swift:18`) is a link-time symbol
  against Apple-signed IOKit, not a `dlopen` of anything, so hardened runtime
  has no opinion about it. Private API is an *App Store review* matter, not a
  notarization one (runbook, Step 2). Still the codebase's only SPI, still
  worth a measurement, and the measurement must happen **inside the sandboxed
  extension** — the CLI answer proves nothing.
- **Subprocesses** (`ps`, `git`, `docker`, `launchctl` — `Shared/ProcessSnapshot.swift`,
  `GitBoxSnapshot.swift`, `DevBoxSnapshot.swift`, `DeckApp/DeckApp.swift`).
  Hardened runtime restricts what can be injected *into* a process, not what it
  may spawn. Low.
- **TCC.** The calendar grant and the "access data from other apps" grant are
  keyed on the code requirement (team + identifier), which does not change
  here — only the CDHash does. Expected to survive; **this is the highest-value
  measurement in the whole slice**, because the notarization release *will*
  reset them and it matters to know which change is responsible.
- **SMAppService.** Untouched by the flag, but every install replaces the
  bundle, which takes the running jobs down without reloading them (CLAUDE.md).
  Any verification must therefore relaunch and re-check the two witnesses
  rather than reading a frozen mtime as a failure.

## Ambiguities to settle in the PRD

1. **Ship it, or only measure it?** A flag proven and then reverted has to be
   proven again on the paid day, and re-introduces the "two variables at once"
   problem this work exists to remove. Recommendation: ship it in the next
   release.
2. **The CI flag drop is not free, and probably does not belong here.** The
   brief carried "drop `-allowProvisioningDeviceRegistration`" from the runbook,
   but the runbook drops it *as part of the Developer ID switch*. Today the
   signed release build runs on a fresh `macos-latest` runner under **automatic
   Apple Development signing**, and that flag is what lets xcodebuild register
   the runner and mint a profile. Removing it while the identity is unchanged
   risks breaking the release job for no gain in this slice. Recommendation:
   leave it, and note it in the runbook as Step 2's remaining half.
3. **Debug as well as Release?** Putting the key in `settings.base` covers both.
   Uniform is simpler and means the thing developers run is the thing users get;
   Debug additionally keeps `get-task-allow`, which coexists with hardened
   runtime (that is how Xcode debugs hardened apps).
4. **How much of the verification is mine and how much is the user's?** Adding
   widgets from the gallery and confirming all three sizes is a human action;
   codesign flags, agent witnesses, `pmset -g accps` versus the rendered BatBox
   section, and the AMFI log are mine.
5. **What is the falsifiable pass mark?** Proposed: all three binaries report
   `runtime`, both agent witnesses advance after the install, BatBox still lists
   an accessory, CalBox still renders events without a new TCC prompt, DevBox
   still lists ports and containers, and `log stream --predicate 'sender ==
   "AMFI"'` is silent across a full 60s tick.

## Shell invariants this must not break

None of the widget shell is touched. The two CLAUDE.md rules that *govern the
verification* rather than the change are: build only into `native/build.noindex`
and run `scripts/lsclean.sh` after every release build; and never `rm -rf` the
widget container — reinstall by replacing the app bundle only.
