# Understanding — keychain-tokens

## What the work is really asking

Take the five API credentials out of cleartext `settings.json` and keep them in
the login keychain, without changing what any widget renders.

The five fields (`native/Shared/DeckSettings.swift`):

| Field | Line | Used by |
|---|---|---|
| `OpenBoxSettings.token` | 256 | OpenBox remote mode |
| `ShipBoxSettings.token` | 504 | ShipBox (GitHub) |
| `TaskBoxSettings.token` | 600 | TaskBox (Azure DevOps PAT) |
| `PRGitHubSettings.token` | 744 | PRBox, GitHub half |
| `PRAzureSettings.token` | 772 | PRBox, Azure half |

`ROADMAP.md` M7 says "three tokens"; it predates PRBox shipping two of its own.

## The shape of the code, and why it makes this cheap

**No widget face reads a token.** Every `.token` reference outside
`DeckSettings.swift` and the tests is in `DeckApp/DeckApp.swift`,
`DeckAgent/main.swift`, or `HostGitHubLoader` (`Shared/ShipBoxSnapshot.swift:275`)
— all host-side. The sandboxed extension needs no keychain access at all, which
removes the hardest part of the problem before it starts.

**Loaders take whole settings structs, not tokens.** `HostGitHubLoader.fetch`
reads `settings.token` off the struct it is handed. So the cheapest design is a
**hydrate step**, not new signatures: the app and the agent call
`DeckSettings.load()` and then fill the five fields from the keychain. Nothing
downstream changes — not the loaders, not the fetch-status wiring, not the
`isUsable` checks, not the tests.

**Scrub at the file boundary, never in `Codable`.** `DecodeTests` asserts that
tokens round-trip through `encode`/`decode` (`:477`, `:504`, `:509`, `:644-646`),
and the tolerant-decode regression tests pin the container's behaviour. So
`save()` must encode a scrubbed *copy*; `encode(to:)` stays symmetric.

## Affected files

- `Shared/DeckSettings.swift` — `save()` (:145) scrubs; a hydrate entry point.
- New `Shared/` file for the keychain wrapper. Note `Shared` compiles into
  **all four targets** including the sandboxed extension (`project.yml:53-78`),
  so the wrapper must be inert unless called — the same arrangement
  `HostGitHubLoader` already has.
- `DeckApp/DeckApp.swift` — five `SecureField`s (:735, :1156, :1174, :1209,
  :1343) and the refresh pumps that read tokens (:168, :263, :281, :307, :335,
  :1326).
- `DeckAgent/main.swift` — the five read sites (:50, :133, :164, :214, :234).

## What the probe settled (see `probe.md`)

1. The card's blocking risk is **not real**: the bare tool reads the bundled
   app's item under launchd, no prompt, UI suppressed.
2. The presumed fix is **worse than unnecessary — it is fatal**: a
   `keychain-access-groups` entitlement SIGKILLs both binaries at launch (no
   provisioning profile, and a `type: tool` has nowhere to embed one).
3. The keychain gives **confidentiality at rest, not process isolation**: an
   ad-hoc-signed copy and `/usr/bin/security` both read the value with no
   prompt, even against an explicitly restrictive ACL.

## Ambiguities for the interview

- **A1 — the honest value claim.** Given finding 3, is the goal still worth it?
  (It takes secrets out of a file that is backed up, synced and sanitised by
  `scripts/demo-data.sh`.) The README/ROADMAP wording must not promise
  protection from other local processes.
- **A2 — write cadence.** `DeckApp.swift:151` saves on *every* `settings`
  change, so a token would be written to the keychain on every keystroke.
  Debounce, or write on commit?
- **A3 — a locked keychain.** Untested and untestable safely here. Should a
  failed keychain read be its own fetch outcome, or reuse "not configured"?
  (Reusing it would repeat the ShipBox C1 mistake: sending a user to the wrong
  field.)
- **A4 — migration direction.** One-way (copy in, scrub the file) is what the
  card asks. What happens to someone who downgrades Deck afterwards — silent
  "not configured" on four widgets?
- **A5 — the uninstall button.** General tab "erase the data" (`ROADMAP.md` M7)
  deletes the container. Should it now also delete the keychain items?

## Shell invariants checked

Nothing here touches a widget face, a snapshot schema, the 60s cadence, the
container layout, or the extension's entitlements. No version bump is required
by the WidgetKit descriptor-cache rule (no widget is added). `Shared` compiling
into the sandboxed extension is the only shell constraint that binds.
