# PRD — Bundle identifier rename

**Slug:** `bundle-identifier` · **Type:** feat · **Date:** 2026-08-28
**Source:** `docs/planning/_card/issue.md` · **Dig:** `docs/planning/_card/understanding.md`

## Ask

Move Deck off `com.deck.*` — reverse-DNS for a domain nobody owns — onto an
owned prefix, and carry existing installs across the container move that the
rename forces.

This is a **feature PRD, not a widget PRD**: no face, no settings tab, no data
source. The widget-specific checklist in `deck-prd` is answered once, here — the
work touches no widget face, neither data path, and no shell invariant. What it
touches is identity, and identity is the key to four things the user can see:
the sandbox container, the placed widgets, two TCC grants, and the Login Items
registrations.

## Decisions taken with the user (2026-08-28)

1. **New prefix: `io.github.haqaliz.deck`.** Backed by the GitHub account that
   already hosts the repo and the Homebrew tap, so it is a namespace actually
   controlled rather than merely unclaimed. No domain purchase. The three ids
   become:

   | target | old | new |
   |---|---|---|
   | DeckApp | `com.deck.app` | `io.github.haqaliz.deck` |
   | DeckWidgets | `com.deck.app.widgets` | `io.github.haqaliz.deck.widgets` |
   | DeckAgent | `com.deck.agent` | `io.github.haqaliz.deck.agent` |
   | (fast agent label) | `com.deck.agent.processes` | `io.github.haqaliz.deck.agent.processes` |
   | DeckSharedTests | `com.deck.sharedtests` | `io.github.haqaliz.deck.sharedtests` |

   Note the app drops the `.app` suffix: `com.deck.app` only had one because
   `com.deck` was the prefix. `io.github.haqaliz.deck` is the product.

2. **Build now, flip at notarization.** `docs/planning/notarization/runbook.md:238`
   (Step 6) argues the rename should ride the Developer ID switch, because that
   already forces every user to re-add widgets and re-grant TCC and a second
   round is pure waste. Accepted. So this work ships **dormant**: everything —
   the single source of truth, the migration, the tests, the docs plan — merges
   now, and the notarization release flips the constant.

3. **The keychain service does not move.** `DeckKeychain.defaultService` stays
   `"com.deck.app"`. It is a plain string, not an OS-enforced key: Deck uses the
   legacy login keychain with no access groups, and
   `docs/planning/keychain-tokens/probe.md` measured that item access is not
   bound to the reading binary at all — a separately-signed tool, an ad-hoc
   copy and `/usr/bin/security` all read the app's items without a prompt, and
   `SecItemAdd` ignored an explicit `SecAccess`. A renamed, re-signed Deck
   therefore keeps reading all five tokens with no migration at all. Renaming it
   buys tidiness and risks stranding a token — the exact failure `DeckSecret`'s
   "stable on disk" comment warns about. **Cosmetics are not worth a migration
   that can silently cost a credential.**

## Scope

### A. One source of truth for identity

No Swift file, plist filename, script or doc may hold the identifier as a
literal after this work — except the **legacy** ids, which become permanent
constants because the migration must keep naming the old container forever.

- New `native/Shared/DeckBundle.swift`: `current` ids (app / widgets / agent /
  fast-agent label, OSLog subsystem) and `legacy` ids.
- `DeckSettings.containerDirectory` derives from `DeckBundle.widgetsID`.
- `AgentService` derives plist names and labels from `DeckBundle`.
- `DeckAgent`'s OSLog subsystem derives from `DeckBundle`.
- `native/project.yml` holds the prefix once (`bundleIdPrefix`), with the three
  `PRODUCT_BUNDLE_IDENTIFIER`s written in terms of it.
- Scripts source one `scripts/lib/ids.sh`.

The flip at notarization is then: change `DeckBundle.current`, change
`bundleIdPrefix`, rename the two LaunchAgent plist files, run the docs pass.

### B. Container migration (the actual risk)

On first launch of a renamed Deck, the host app must carry the old container's
state into the new one.

- **Migrate `settings.json` only.** Every other file under
  `Application Support/Deck` is a snapshot the agent rebuilds within one 60s
  tick — `{opencode,processes,gitbox,clipbox,taskbox,calbox,prbox,devbox,
  marketbox,shipbox,weather}.json`, the `fetch-*.json` statuses, and
  `opencode-cursor.json` (whose loss costs one full resync and nothing else).
  Copying eleven files that expire in a minute is work that can fail; copying
  the one irreplaceable file is not.
- **Copy, never move.** The old file stays where it is.
- **Never delete the old container directory.** `rm -rf` cannot remove the
  SIP-protected `.com.apple.containermanagerd.metadata.plist` (confirmed
  present on this machine, 29.7K), and its survival makes containermanagerd
  believe the container is still provisioned, so the skeleton is never rebuilt
  and every widget renders blank forever — the CLAUDE.md trap that
  `scripts/container-repair.sh` exists to undo. `eraseDeckData()`
  (`DeckApp.swift:574`) already models the correct shape: delete contents,
  leave the directory.
- **Run once, idempotently, and never overwrite.** If the new container already
  has a `settings.json`, the migration does nothing — a second run must not
  clobber settings the user has since changed.
- **A missing old container is a success, not an error** (fresh install).

### C. Tell the user their widgets need re-adding

The rename orphans every placed widget: WidgetKit keys them
`com.deck.app::com.deck.app.widgets:<Kind>`, so after the flip the desktop
shows fourteen widgets that will never render again. Deck must say so once —
a dismissible notice in the General tab ("Deck's identifier changed. Remove and
re-add your widgets from the Widget Center") shown only when the migration
actually ran. Silence here reads as the blank-widget bug.

### D. Old registrations and old agents

Before registering under the new labels, the old `com.deck.agent` /
`com.deck.agent.processes` jobs must be taken down, or two agents pump the same
snapshots on different cadences. `DeckApp.legacyCleanup()` already boots out
those two labels by name and deletes their `~/Library/LaunchAgents` plists; it
extends naturally to also cover the SMAppService-era registration. **See open
question O2 — whether the old BTM record can be unregistered at all from a
differently-identified bundle is not established.**

### E. Docs, scripts, distribution

`README.md` (9 sites), `.github/ISSUE_TEMPLATE/bug_report.md`, the four
`scripts/*.sh`, `homebrew/deck.rb` (`launchctl` uninstall, `quit:`, `zap`
paths) and its mirror in the `haqaliz/homebrew-deck` tap, and
`docs/planning/notarization/runbook.md:220,245`. The cask's `zap` must list
**both** containers so an uninstall after the flip cleans up the old one too.

## Non-goals

- Renaming the keychain service (decision 3).
- Migrating snapshots (they regenerate; scope B).
- Notarization, the Developer ID certificate, or the expiry cliff — separate
  M7 items with their own runbook. This work only agrees to ride with them.
- Preserving placed widgets across the rename. Not possible; scope C is the
  mitigation.
- Preserving the TCC grants. Not possible — they are keyed to identifier plus
  signature; the user re-approves `ps` access and calendar access once.

## Failure behaviour

| Condition | Behaviour |
|---|---|
| Old container absent (fresh install) | No-op, no notice, no log noise |
| Old `settings.json` absent but container present | No-op |
| New `settings.json` already present | No-op — never overwrite |
| Copy fails (permissions, I/O) | Deck starts on defaults, logs to OSLog, and the notice says settings could not be carried over and where the old file is |
| Old agents cannot be booted out | Registration still proceeds; worst case is a stale job that dies at next login |

## Verification

- `DeckSharedTests` cover the migration decision as pure policy (should-copy /
  should-skip, given the four states above) — the repo's established pattern
  (`AgentReconcilePolicy`, `RemoteOpenCodeSync`).
- `grep -rn "com\.deck" native/ scripts/ homebrew/ README.md` returns only the
  documented legacy constants after the flip.
- Post-flip manual gate, on the installed copy: `pluginkit -m -i
  io.github.haqaliz.deck.widgets` registers; both agents appear in Login Items
  under the new labels; the old labels are gone from `launchctl list`;
  `settings.json` exists in the new container with the user's colours intact;
  all fourteen widgets re-add and render at all three sizes.
- `scripts/lsclean.sh` after the build, as always.

## Open questions

- **O1 — Who provisions the new container, and is a hand-made one adopted?**
  `AtomicFile` will `mkdir -p` a container path containermanagerd has never
  provisioned. Whether that skeleton is adopted or *poisons* provisioning is
  precisely the failure `container-repair.sh` exists for, and is answered
  nowhere in this repo. If the app must wait for the extension's first run,
  the migration cannot be a launch-time one-shot — it becomes a check on every
  launch until the container exists. **Needs a live probe before the plan.**
- **O2 — Can the old SMAppService registration be unregistered after the
  rename?** `SMAppService.agent(plistName:)` resolves against the *current*
  main bundle, so a renamed Deck may have no handle on the record the old
  bundle created. If not, `launchctl bootout` takes the job down but the BTM
  record may linger in Login Items as an orphan. Measurable with
  `sfltool dumpbtm`, the tool the SMAppService work already used.
- **O3 — Does the migration belong in DeckAgent too?** The agent can run before
  the app is ever opened (it is registered at login). If it starts first after
  an upgrade it will read the *new*, empty container and write snapshots there
  while `settings.json` is still only in the old one — one tick of default
  settings. Cheap fix: the agent runs the same idempotent copy. Confirm rather
  than assume the app always wins the race.

---

# Self-critique (2026-08-28)

Five 🔴 and four 🟡. Three of the reds change the design; one kills a promise
the PRD made and one makes a "cheap" probe expensive.

## 🔴 R1 — Scope A's promise is unachievable as written: Swift cannot read the build setting

Scope A says "no Swift file may hold the identifier as a literal". There is no
mechanism for that. `PRODUCT_BUNDLE_IDENTIFIER` is a build setting; Swift has no
string-valued compile flag (`-D` defines a *condition*, not a value), and the
one runtime source, `Bundle.main.bundleIdentifier`, is wrong for the two callers
that matter: the **host app** needs the *extension's* id (a different bundle),
and **DeckAgent** is a `type: tool` whose identity lives in a
`__TEXT,__info_plist` section, where `Bundle.main` behaviour is unverified.

**Fix:** downgrade the promise to what is actually enforceable — one Swift
literal in `DeckBundle`, plus a `DeckSharedTests` case that reads the built
app's `Info.plist` (available to the test bundle) and **asserts the literal
matches**, so the two sources of truth cannot drift silently. That is the same
shape as the repo's other "stable on disk" invariants. Say so plainly rather
than claiming a single source that does not exist.

## 🔴 R2 — DeckAgent already has *two* identifiers, and the PRD's table names only one

Measured on the baseline build: `project.yml` sets DeckAgent's
`CFBundleIdentifier: com.deck.agent` in `info.properties` but **no**
`PRODUCT_BUNDLE_IDENTIFIER`, so xcodegen's `options.bundleIdPrefix` synthesises
one — `PRODUCT_BUNDLE_IDENTIFIER = com.deck.DeckAgent` appears twice in the
generated `project.pbxproj`. The `__info_plist` section wins for the *signed*
identity (`codesign -dv` reports `Identifier=com.deck.agent`), so the synthesised
one is dead weight today — but it is exactly the sort of second identifier that
a later change reads by mistake, and `bundleIdPrefix` is what generates it.

**Fix:** the flip must set DeckAgent's `PRODUCT_BUNDLE_IDENTIFIER` explicitly to
match its `CFBundleIdentifier`, killing the synthesised value. Add
`codesign -dv | grep Identifier=` on all three binaries to the verification
gate — the PRD currently verifies `pluginkit` but never checks what the agent
was actually *signed* as, which is what TCC keys the grant to.

## 🔴 R3 — The old agent will run the new binary before the app ever migrates

O3 is filed as a maybe; it is close to certain. `BundleProgram` is relative to
the bundle, and the flip replaces `/Applications/Deck.app` in place. The old BTM
record therefore still points at that path and launches the **new** DeckAgent
under the **old** label. That binary computes the *new* container path, finds no
`settings.json`, and writes a full set of snapshots from `DeckSettings()`
defaults — losing nothing, but rendering fourteen widgets wrong (default
colours, default counts, no accounts) until the user next opens Deck.

**Fix:** promote O3 to a requirement. The idempotent copy lives in `Shared` and
runs at the top of **both** `DeckAgent.main` and the app's launch, not just the
app's. This also makes the migration robust to the user never opening Deck.

## 🔴 R4 — Probing O1 is not free: every probe leaves a container that cannot be deleted

The PRD asks for a live probe of container provisioning without saying what a
probe costs. It costs a permanent artefact: a container directory whose
`.com.apple.containermanagerd.metadata.plist` is SIP-protected and undeletable,
which is the whole premise of the CLAUDE.md trap. Probing "a throwaway id" three
times leaves three undeletable containers on the dev machine, and a second
installed Deck also means a second set of Login Items and a second agent pumping
snapshots.

**Fix:** constrain the probe before it is run — **one** id, and make it the real
`io.github.haqaliz.deck`, so the artefact left behind is the container the
product will actually use. Uninstall the widgets from the desktop first, quit
Deck (`pgrep -lf "MacOS/Deck$"` — a running Deck overwrites what you are
inspecting, per CLAUDE.md), and unregister the probe build's agents afterwards.
Accept up front that the probe is a one-way step on this machine.

## 🔴 R5 — "Build now, flip later" ships a migration that has never run

The chosen sequencing merges the migration dormant and flips it in a release
that may be months away. Dormant code with no execution path is code that is
verified only by its unit tests — and the parts most likely to be wrong here are
exactly the parts unit tests cannot reach (does containermanagerd adopt the new
container, does the old BTM record survive, does `Bundle.main` work in a tool).

**Fix:** the probe in R4 is not optional and not deferrable to the flip. Run it
in *this* unit of work, on a real renamed build, and record the answers in
`docs/planning/bundle-identifier/probe.md` — the repo's established pattern
(`keychain-tokens/probe.md`, `azure-multi-project`, `shipbox-multi-repo` all
probed before the PRD was trusted). A dormant migration backed by a live probe
is fine; one backed by nothing is a bet.

## 🟡 A1 — The interim release is unspecified

The PRD never says what ships between now and the flip. State it: the
source-of-truth refactor, the migration code and the tests ride the next release
**invisibly** — no version-string implication, no user-facing change, no README
change (the docs pass belongs to the flip, since the docs must keep describing
the ids that are actually live).

## 🟡 A2 — Version policy at the flip is not stated

CLAUDE.md requires a version bump for a new widget because the descriptor set is
cached per extension version. A new extension *identifier* is arguably a new
extension with no cache at all — but "arguably" is not a plan. Bump both
`CFBundleShortVersionString` and `CFBundleVersion` at the flip anyway; it costs
nothing and the failure it prevents is silent.

## 🟡 A3 — The generated Info.plists are tracked, and the flip must regenerate them

`native/{DeckApp,DeckWidgets,DeckAgent}/Info.plist` are checked in as xcodegen
output (see `85ababf`, "regenerate Info.plists for v1.32"). The flip changes
DeckAgent's `CFBundleIdentifier` inside one of them, so the commit must include
the regenerated files or the built agent keeps the old identity.

## 🟡 A4 — The notice in scope C has no dismissal state

"Dismissible notice shown only when the migration ran" needs somewhere to record
that it was dismissed. Put a `didShowRenameNotice` bool in `DeckSettings`
(tolerantly decoded, defaults false) — and note it must be written to the *new*
container, or the notice returns on every launch.
