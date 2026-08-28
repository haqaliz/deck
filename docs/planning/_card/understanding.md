# Understanding — bundle identifier rename

## What the work is really asking

Move Deck off `com.deck.*` (reverse-DNS for an unowned domain) to an owned
prefix. The rename itself is a find-and-replace; the work is **everything the
old identifier is silently the key to**: the widget extension's sandbox
container, the placed widgets on the user's desktop, two TCC grants, and the
`SMAppService` registrations.

## Affected files (verified by grep, not assumed)

**Identity itself**
- `native/project.yml:3` — `bundleIdPrefix: com.deck`
- `native/project.yml:42` — DeckApp `com.deck.app`
- `native/project.yml:79` — DeckWidgets `com.deck.app.widgets`
- `native/project.yml:107` — DeckAgent `CFBundleIdentifier: com.deck.agent`
- `native/project.yml:141` — DeckSharedTests `com.deck.sharedtests`

**Keys derived from it**
- `native/Shared/DeckSettings.swift:181` — container path
  `Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck`.
  This is the *only* place; all 13 snapshot stores go through
  `DeckSettings.containerDirectory` (`AtomicFile.swift:15` creates it with
  `withIntermediateDirectories: true`).
- `native/Shared/DeckKeychain.swift:41` — `defaultService = "com.deck.app"`
- `native/DeckApp/AgentService.swift:35-38` — two `SMAppService` plist names +
  labels; the plists themselves are
  `native/DeckApp/LaunchAgents/com.deck.agent{,.processes}.plist`, whose
  filenames are hardcoded in the copy step at `project.yml:28-29`
- `native/DeckApp/DeckApp.swift:491` — `legacyCleanup()` boots out the two
  labels and deletes `~/Library/LaunchAgents/<label>.plist`
- `native/DeckAgent/main.swift:25` — OSLog subsystem `com.deck.agent`

**Docs / scripts / distribution**
- `scripts/container-repair.sh:38`, `scripts/demo-data.sh:22,28-34`,
  `scripts/soak.sh:30,76-96`, `scripts/lsclean.sh:11,49`
- `homebrew/deck.rb:52-77` — `launchctl` uninstall, `quit:`, and the `zap`
  paths (and the mirror in the `haqaliz/homebrew-deck` tap)
- `README.md:125,149,255,258,286,348,362,386-389`
- `.github/ISSUE_TEMPLATE/bug_report.md:30-36`
- `docs/planning/notarization/runbook.md:220,245`

## The one thing that is *not* affected (and shouldn't be touched)

**The keychain does not have to move.** The service string `com.deck.app` is
just a string — Deck uses the legacy login keychain with no access groups, and
`docs/planning/keychain-tokens/probe.md` measured that item access is *not*
bound to the reading binary's identity at all (a separately-signed bare tool,
an ad-hoc copy, and `/usr/bin/security` all read items the app wrote, with no
prompt, and `SecItemAdd` ignored an explicit `SecAccess`). So a renamed,
re-signed Deck keeps reading the five tokens under the old service with no
migration. Renaming the service for tidiness buys nothing and risks stranding
tokens — `DeckSecret`'s own doc comment says raw values are "stable on disk"
for exactly this reason. **Recommend: leave the keychain service alone**, and
if the cosmetics matter, do it as a separate read-old/write-new migration.

## The real risk: the container

A new extension id means a new container. `settings.json` and all 13 snapshots
live in the old one. Two hard constraints:

1. **The old container must not be deleted.** `rm -rf` cannot remove the
   SIP-protected `.com.apple.containermanagerd.metadata.plist` (confirmed
   present, 29.7K, mode 644 on this machine), so containermanagerd keeps
   believing it is provisioned and never rebuilds the skeleton — every widget
   then renders blank forever (`scripts/container-repair.sh`, CLAUDE.md trap).
   `eraseDeckData()` (`DeckApp.swift:574`) already models the right shape:
   delete the *contents*, never the directory.
2. **Open question — who provisions the new container, and when?** The
   unsandboxed app writes settings via `AtomicFile`, which will happily
   `mkdir -p` a container path that containermanagerd has never provisioned.
   Whether a hand-made skeleton is adopted or poisons provisioning is exactly
   the failure mode `container-repair.sh` exists for, and it is **not answered
   anywhere in the repo**. This wants a live probe before the plan is written.

## Sequencing conflict found in the repo (not in the brief)

`docs/planning/notarization/runbook.md:238-249` — **Step 6, "Ride the same
release with the other install-invalidating changes"** — explicitly lists the
bundle identifier rename as something to ship *with* the Developer ID switch,
on the grounds that notarization already forces every user to re-grant
permissions and "anything else with the same cost should ship in the same
version rather than inflicting a second round".

The two remaining items in that list have both since shipped standalone
(keychain in v1.30, SMAppService in v1.33), so the precedent is mixed. But the
rename is the one item in the list that genuinely carries the same user cost as
notarization, which makes this a real decision rather than a formality:

- **Ship now, standalone** — users pay re-add + re-grant twice (now, and again
  at notarization). Cheapest while the user base is small; unblocks the M7 item
  that is not gated on the $99 program.
- **Prepare now, ship with notarization** — one disruption, but the code sits
  on a branch for an unknown period and the M7 checkbox stays open.
- **Buy the program first** — collapses the question, but is a purchase
  decision, not an engineering one.

**This is the first interview question.** The second is the new prefix itself,
which nothing in the repo decides.

## Shell invariants checked

Nothing here touches the widget faces, the two data paths, the 60s cadence, or
the settings-in-the-app-only rule. The version bump the brief calls for is
required by the WidgetKit descriptor cache (CLAUDE.md), and is needed anyway
because the extension id changes.
