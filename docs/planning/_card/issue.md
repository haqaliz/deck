# Brief — bundle identifier rename

**Type:** feat · **Slug:** `bundle-identifier` · **Source:** inline brief (deck-next pick, 2026-08-28)

Rename Deck's bundle identifiers off `com.deck.*` — a reverse-DNS prefix for a
domain nobody owns — to an owned prefix, before launch.

`ROADMAP.md:402` records the ordering constraint: changing it after launch forces
every user to re-add their widgets and re-grant TCC, "so it has to happen before."
Deck is already public — the Homebrew tap `haqaliz/homebrew-deck` is pinned to a
released v1.35 DMG — so the blast radius widens with every release.

## Where the identifier is load-bearing

Seven places, found by `grep -rn "com\.deck"`:

1. `native/project.yml:3` — `bundleIdPrefix: com.deck`
2. `native/project.yml:42,79,107` — `PRODUCT_BUNDLE_IDENTIFIER` for DeckApp
   (`com.deck.app`), DeckWidgets (`com.deck.app.widgets`), and DeckAgent's
   `CFBundleIdentifier` (`com.deck.agent`); plus `com.deck.sharedtests` at :141
3. `native/Shared/DeckKeychain.swift:41` — `defaultService = "com.deck.app"`
   (the service the five migrated tokens live under)
4. `native/Shared/DeckSettings.swift:181` — the container path
   `Library/Containers/com.deck.app.widgets/Data/…`, where `settings.json` and
   every snapshot live
5. `native/DeckApp/AgentService.swift:35-38` — the two `SMAppService` plist names
   and labels (`com.deck.agent`, `com.deck.agent.processes`), plus
   `DeckApp.swift:491` and the LaunchAgent plists copied by the build phase
   (`project.yml:28-29`)
6. `native/DeckAgent/main.swift:25` — the OSLog subsystem `com.deck.agent`
7. `scripts/{container-repair,demo-data,lsclean,soak}.sh` and
   `homebrew/deck.rb:52-77` — uninstall/zap stanzas and repair paths

## Why this is a data migration, not a rename

The widget container moves. `settings.json`, the snapshots, and the consumers of
the five keychain tokens all live under the old identifier. The migration must
carry `settings.json` and the keychain items over **before** the old container is
orphaned, and must **leave the old container in place** rather than delete it —
`rm -rf` on a container cannot remove the SIP-protected metadata plist, which
leaves containermanagerd believing it is still provisioned and renders every
widget blank (CLAUDE.md trap).

## Known costs, assumed unavoidable

- Both TCC grants reset (the `ps` "data from other apps" prompt and
  `NSCalendarsFullAccessUsageDescription`) — they are keyed to signature + id.
- All fourteen widgets must be re-added from the gallery.
- A version bump is required so the widget descriptor cache invalidates.

## Open question for the PRD

What the new prefix should be.
