# Flip runbook — `com.deck.*` → `io.github.haqaliz.deck*`

**Status: prepared, not applied.** Everything in `docs/planning/bundle-identifier/`
except this file has shipped; the identifiers themselves are unchanged. By the
sequencing decision of 2026-08-28 the flip rides the **notarization release**
(`docs/planning/notarization/runbook.md` Step 6) so users pay one round of
re-adding widgets and re-granting TCC rather than two.

Run this top to bottom in one release. Do not land it piecemeal.

## Prerequisite — ship the liveness check first

Not optional, and not part of this change. The flip puts **every** user into the
state where the BTM record is `[enabled, allowed]` and no launchd job exists,
because the new agents are registered only when the renamed app first launches.
`SMAppService.status` answers "is there a registration record", not "is the job
loaded" (measured: `probe.md`, Phase 1 and the restore), so Deck currently shows
"Refresh in background" on while nothing runs — for six hours on the dev machine
before anyone noticed.

Ship the check — `processes.json` staleness against `processRefreshInterval`
while `agentAtLogin` is on, reported in General next to the Login Items notice —
**before** this runbook, or the rename silently stops background refresh for the
entire user base.

## What is already done (do not redo)

- `DeckBundle` (`native/Shared/DeckBundle.swift`) is the single Swift source,
  with `Legacy` constants that are **permanent**.
- Every Swift call site reads it; no `com.deck` literal remains outside it.
- `scripts/lib/ids.sh` is the shell source; all four scripts source it.
- `ContainerMigration` carries `settings.json` across, runs from both the app
  and `DeckAgent`, is idempotent, never overwrites, and never touches the old
  container. Dormant today (`skipped(.sameContainer)`).
- `didShowRenameNotice` + the General-tab notice.
- `DeckBundleTests` pins the Swift constants against `project.yml`, the
  generated `DeckAgent/Info.plist`, both LaunchAgent plist filenames and Labels,
  and `scripts/lib/ids.sh`. **Drift fails the suite** — verified by drifting each
  half deliberately.
- `Embed LaunchAgents` clears its destination before copying, so a build cannot
  ship two generations of plists.

## Step 1 — Flip the constants

1. `native/Shared/DeckBundle.swift`: `appID` → `io.github.haqaliz.deck`,
   `agentLabel` → `io.github.haqaliz.deck.agent`. `widgetsID` and
   `fastAgentLabel` derive. **Leave `Legacy` exactly as it is** — the suite
   catches you if you don't, which is the one mistake most likely to be made
   here (it was made once during development, by a careless `sed -g`).
2. `scripts/lib/ids.sh`: the same two values.
3. `native/project.yml`:
   - `bundleIdPrefix: io.github.haqaliz`
   - DeckApp `PRODUCT_BUNDLE_IDENTIFIER: io.github.haqaliz.deck`
   - DeckWidgets `PRODUCT_BUNDLE_IDENTIFIER: io.github.haqaliz.deck.widgets`
   - DeckAgent `CFBundleIdentifier: io.github.haqaliz.deck.agent` **and an
     explicit `PRODUCT_BUNDLE_IDENTIFIER` set to the same value.** Without it
     xcodegen synthesises `<prefix>.DeckAgent` from `bundleIdPrefix` — measured
     in the pre-flip project as `com.deck.DeckAgent`, present twice in
     `project.pbxproj`. The `__info_plist` section wins for the signed identity,
     so it is inert today, but it is a second identifier waiting to be read by
     mistake.
   - `DeckSharedTests` → `io.github.haqaliz.deck.sharedtests`
   - the two plist filenames in the `Embed LaunchAgents` copy step
   - bump `CFBundleShortVersionString` **and** `CFBundleVersion` on all three
     targets
4. `git mv` both plists in `native/DeckApp/LaunchAgents/` and update their
   `Label` strings.
5. `xcodegen generate` and **commit the regenerated `Info.plist`s** — all three
   are tracked, and `DeckAgent/Info.plist` carries the identifier literally.

## Step 2 — Keep the old plists for exactly one release

Add `com.deck.agent.plist` and `com.deck.agent.processes.plist` back alongside
the new pair, and have the app call `SMAppService.agent(plistName:)` on the old
names and `unregister()` them at launch.

**Why.** The rename orphans the two old BTM records, and they are *re-parented
to the new app* rather than deleted — Login Items ends up showing four DeckAgent
rows under Deck, two of which can never run (`spawn failed`, `78: EX_CONFIG`).
They cannot be removed any other way: `launchctl bootout` fails with
`No such process`, and `SMAppService.agent(plistName:)` resolves plists **inside
the current bundle**, so without shipping the old names there is no handle.

**What it achieves, precisely.** `unregister()` flips a record to
`[disabled, allowed]` and bumps its generation; **it does not delete it**
(measured). So this converts two lying records into two honest ones. Nothing
short of `sfltool resetbtm` — which wipes every login item for every app —
removes them. Do not promise users they disappear.

Drop both plists and the unregister call in the *next* release. The
`Embed LaunchAgents` clear-first fix is what makes that drop actually take
effect.

## Step 3 — Docs and distribution

- `README.md` — `pluginkit -m -i …` (:125), the container path (:286), the
  LaunchServices explanation (:348), the agent labels (:149, :255, :258), and
  the manual uninstall block (:386-389).
- **`README.md:362` and `.github/ISSUE_TEMPLATE/bug_report.md:31` are wrong
  today, independently of the rename.** Both tell users to run
  `launchctl list | grep com.deck.agent`, which prints **nothing** on a healthy
  SMAppService install — the jobs are not bootstrapped into `gui/<uid>` under
  their plist label. Wrong since v1.33. Replace with `sfltool dumpbtm` or a
  `processes.json` freshness check rather than translating the broken command.
- `homebrew/deck.rb` — `quit:`, the two `launchctl` labels, and `zap` must list
  **both** containers so an uninstall after the flip also clears the old one.
  Mirror to the `haqaliz/homebrew-deck` tap.
- `docs/planning/notarization/runbook.md:220` and `:245` — tick Step 6.
- `ROADMAP.md` M7 — close the bundle identifier item.
- `CLAUDE.md` — record the probe's findings.
- `scripts/container-repair.sh:12,22` and `scripts/lsclean.sh:11` quote real log
  lines and a historical cause; update the examples, but they are comments, not
  behaviour.

## Step 4 — Verification gate (on the installed copy, not `build.noindex`)

Build **clean** — `rm -rf native/build.noindex` — because derived data can carry
plists and bundles from the previous identity.

- [ ] `codesign -dv` on `Deck.app`, `Contents/MacOS/DeckAgent` and
      `Contents/PlugIns/DeckWidgets.appex` each report the new `Identifier=`.
      This is the check the original plan lacked, and it is what TCC keys grants
      to.
- [ ] `Contents/Library/LaunchAgents/` holds exactly the intended plists (four
      during the one-release courtesy, two after).
- [ ] `pluginkit -m -i io.github.haqaliz.deck.widgets` lists the extension.
- [ ] `sfltool dumpbtm`: the two new agent records are `[enabled, allowed]`; the
      two old ones are `[disabled, allowed]`.
- [ ] `launchctl print gui/$(id -u)/io.github.haqaliz.deck.agent.processes`
      resolves as a service with `state = spawn scheduled` and
      `last exit code = 0`. **A BTM record alone is not evidence the job runs** —
      that conflation is the bug this whole document keeps circling.
- [ ] `processes.json` in the **new** container advances on cadence.
- [ ] `settings.json` is in the new container with the user's colours and
      accounts intact; the old container is **unchanged** (compare mtimes).
- [ ] The General tab shows the re-add notice once and it stays dismissed
      across a relaunch.
- [ ] All fourteen widgets re-add from the gallery and render at all three
      sizes. **Not covered by the probe** — the renamed build registered its
      extension but no widget was ever added, so rendering from a fresh
      container is still unobserved.
- [ ] `grep -rn "com\.deck" native/ scripts/ homebrew/ README.md` returns only
      `DeckBundle.Legacy`, `scripts/lib/ids.sh`'s legacy block, the one-release
      plists, and comments that deliberately quote history.
- [ ] `scripts/lsclean.sh` after the build, as always.

## Rollback

**There is no clean rollback, and users must be told so.** Reinstalling the old
bundle over the new one leaves BTM holding **two app records for the same URL**
(`2.com.deck.app` and `2.io.github.haqaliz.deck`, both
`file:///Applications/Deck.app/`), after which launchd refuses the
`BundleProgram` jobs with `78: EX_CONFIG` — measured. The in-app toggle,
`launchctl kickstart -k` and restarting `smd` all fail to repair it; only a
**logout/login** does. Going forward is fine; going back needs a login cycle,
and any rollback note must say so.
