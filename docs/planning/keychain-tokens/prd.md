# PRD — Keychain for Deck's API credentials

**Slug:** `keychain-tokens` · **Type:** feat · **Branch:** `feat/keychain-tokens/aliz`
**Date:** 2026-08-26 · **Probe:** `probe.md` · **Dig:** `understanding.md`

## 1. The ask, in one sentence

Deck's five API credentials stop living in cleartext inside `settings.json` and
live in the login keychain instead, with no change to anything a widget renders.

## 2. What this actually delivers — and what it does not

The probe (`probe.md`, finding 3) measured this before the PRD was written, and
it narrows the claim:

- **Delivered:** the tokens leave a plaintext JSON file. That file is inside the
  widget container, is copied by Time Machine and any folder backup, and is the
  thing CLAUDE.md tells you to back up before wiping the container. After this
  change it holds no secrets at all.
- **Not delivered:** protection from other processes running as the same user.
  An ad-hoc-signed binary and `/usr/bin/security` both read a probe item with no
  prompt, and an explicitly restrictive ACL did not change that.

**Wording rule (binding on README, ROADMAP and any UI text):** say the tokens
are no longer stored in a readable file. Never say other apps cannot read them.
`ROADMAP.md` M7 currently calls 0600 "the interim measure" — the replacement
line must not overclaim.

## 3. User-visible spec

Deck has no widget face here. The two surfaces are the settings window and the
failure line a widget already draws.

### Settings window — five `SecureField`s, unchanged in appearance

`DeckApp.swift:735` (OpenBox), `:1156` / `:1174` (PRBox GitHub / Azure),
`:1209` (ShipBox), `:1343` (TaskBox). Same labels, same positions, same
placeholder behaviour. A user who never opens the file notices nothing.

**Commit on edit, not on keystroke** (user decision). Today
`DeckApp.swift:151` saves the whole settings struct on every change, so binding
a keychain write to that would write a partial token per character. Each field
holds its value in local `@State` and commits to the keychain on submit or when
focus leaves. One keychain write per edit.

The existing `FetchStatusCaption` under each field keeps working: its `clearOn`
key already includes the token (`:1216`, `:1164`, `:1181`, `:1353`, `:741`), so
editing a token still clears a stale failure caption.

### Widget faces — one new failure line

A locked login keychain would otherwise blank four widgets at once with no
explanation. It gets its **own** `FetchOutcome` (user decision), not a reuse of
`notConfigured` — telling someone to paste a token they already pasted is the
ShipBox C1 mistake, recorded in `ROADMAP.md` M6.

- New case: `FetchOutcome.credentialsUnavailable`.
- `FetchStatusCopy.line` (face, short): "Can't read saved credentials" for the
  five token-bearing sources; `nil` for `weather`, `calbox`, `marketbox`, which
  have no credentials and cannot reach this state.
- `FetchStatusCopy.hint` (settings, full sentence): "Deck couldn't read the
  saved token from your keychain — unlock your login keychain and it will
  retry." Both switches are exhaustive, so the compiler enumerates the work.

### General tab — uninstall removes the credentials too

"Erase Deck data" deletes the five keychain items along with the container
contents (user decision). `eraseDeckData`'s own doc comment
(`DeckApp.swift:487-493`) already promises it removes "the saved tokens"; after
this change that sentence is only true if the keychain items go too.

## 4. Data source and mechanism

**Legacy (file-based) login keychain, `SecItemAdd` / `SecItemCopyMatching` /
`SecItemUpdate` / `SecItemDelete`, generic-password class.** One item per
credential:

| Item | `kSecAttrService` | `kSecAttrAccount` |
|---|---|---|
| OpenBox | `com.deck.app` | `openbox.token` |
| ShipBox | `com.deck.app` | `shipbox.token` |
| TaskBox | `com.deck.app` | `taskbox.token` |
| PRBox GitHub | `com.deck.app` | `prbox.github.token` |
| PRBox Azure | `com.deck.app` | `prbox.azure.token` |

**The data-protection keychain and access groups are not an option.** Writing to
it without `keychain-access-groups` returns `-34018`; signing either binary
*with* that entitlement gets the process SIGKILLed at launch, because there is no
provisioning profile to authorise it and a `type: tool` has nowhere to embed one
(`probe.md`, finding 2). This is settled — do not re-litigate it without a new
signing story.

**No prompt, and none expected.** The bare tool read the bundled app's item
inside a launchd job with UI suppressed (`probe.md`, finding 1). The card's
blocking risk does not exist.

### Cadence

Unchanged. The agent reads the keychain once per 60s tick, in the same place it
reads `settings.json` today (`DeckAgent/main.swift:44`). No new timer, no change
to any snapshot or widget timeline.

### Failure behaviour

A keychain read that fails leaves the field empty and records
`credentialsUnavailable` for that source. The snapshot on disk is untouched, so
the widget keeps rendering its last data with its timestamp — the behaviour the
agent-fetch-status work already established for ShipBox/WeatherBox/OpenBox.

## 5. Design: hydrate, don't re-plumb

Loaders take whole settings structs and read `.token` off them
(`HostGitHubLoader`, `Shared/ShipBoxSnapshot.swift:275`). So:

1. `DeckSettings.load()` is unchanged.
2. A new host-side **hydrate** step fills the five fields from the keychain. The
   app and the agent call it; **the widget extension never does.**
3. `DeckSettings.save()` encodes a **scrubbed copy** — the five fields blanked.

**Hydrate returns a result per key, never a bare `String` (critique C1).**
`found(String)` / `absent` / `failed(OSStatus)`, and the host keeps the set of
failed keys. This is load-bearing: every configured-check in the codebase is
`token.isEmpty` or `isUsable`, evaluated *before* the fetch
(`DeckApp.swift:168`, `:255`, `:276`, `:307`, `:335`; `DeckAgent/main.swift:50`,
`:133`, `:164`, `:214`, `:234`). Hand those an empty string on a keychain
failure and they record `.notConfigured` — the ShipBox C1 mistake, and
`credentialsUnavailable` would never fire. Each gate therefore gains one line
ahead of its existing logic: *this key failed → record
`.credentialsUnavailable`, skip the fetch.* Nothing below that line changes.

**Hydrate never blanks a field (critique C2).** A keychain value wins when
present; when the keychain has no value, whatever `load()` decoded from the file
**survives untouched**. Before migration the file still holds the real tokens,
and that is what keeps a Deck upgraded-but-never-opened working — `DeckAgent`
never writes `settings.json` (only `DeckApp.swift:152` does), so it can read a
not-yet-migrated file for as long as it takes the user to open the app.

This leaves every loader signature, every `isUsable` check and every existing
test untouched.

**`Codable` stays symmetric.** The scrub happens at the file-write boundary in
`save()`, never in `encode(to:)`. `DecodeTests` asserts tokens round-trip
through encode/decode (`:477`, `:504`, `:509`, `:644-646`) and those assertions
must keep passing unmodified — they are the tolerant-decode regression pins.

**The wrapper lives in `Shared/` and must be inert.** `Shared` compiles into all
four targets including the sandboxed extension (`project.yml:53-78`), exactly as
`HostGitHubLoader` already does. No top-level work, no keychain call on any path
a widget takes.

### Migration — one way, on first launch of the new build

The host app, at launch, for each of the five fields that `settings.json` holds
a non-empty value for: **write to the keychain → read it back to confirm → only
then blank the field and save.** Idempotent; a second run finds nothing to move.
`tightenPermissions()` (`:136`) is the precedent for a cheap once-at-launch
fixup.

**The order is the safety property (critique C4).** Scrub-then-write loses the
token outright if the keychain write fails. On any failure the file is left
exactly as it was and the migration simply retries at the next launch.

**Accepted consequence:** downgrading to an older Deck afterwards shows four
widgets as "not configured" until the tokens are re-pasted. The file no longer
holds them and an old build cannot read the keychain. This is what one-way
means; it is not worth a compatibility shim for a single-user app.

## 6. Shell fit

Nothing here touches a widget face, a snapshot schema, the 60s cadence, the
container layout, or the extension's entitlements.

- **No version bump required by the descriptor-cache rule** — no widget is
  added. (A release still bumps the version as normal.)
- **No new entitlements on any target.** Adding one is precisely what kills the
  binaries.
- `Security.framework` links into all four targets via `Shared`. Harmless for
  the sandboxed extension, which never calls it.

## 7. Non-goals

- Not process isolation. See §2 — it is not achievable as Deck is signed.
- Not the data-protection keychain, access groups, or any entitlement change.
- Not iCloud keychain sync, and not a master-password prompt.
- No change to what any widget draws when things are working.
- Not a re-plumb of loader signatures to take tokens as parameters.
- Not touching the other five M7 launch items.

## 8. Test strategy (TDD)

Pure logic goes in `DeckSharedTests`; the keychain itself is I/O and is verified
by hand.

**Tested (XCTest):**
- `save()` writes a file whose five token fields are empty, while the in-memory
  struct still holds them.
- The scrub does not disturb any other field — round-trip a fully populated
  `DeckSettings` and assert equality everywhere except the five.
- `encode`/`decode` symmetry is untouched: the existing `DecodeTests` assertions
  pass unmodified.
- Migration is idempotent and only moves non-empty values, and leaves the file
  untouched when the confirming read-back fails.
- **The hydrate-result → `FetchOutcome` mapping** (critique C6, where C1 lives):
  a pure function over `found` / `absent` / `failed`, tested across the five
  token-bearing sources.
- `FetchStatusCopy.line` / `.hint` return `nil` for `credentialsUnavailable` on
  the three credential-free sources and a string for the other five.

**Verified by hand (recorded in the plan):**
- App writes a token → `settings.json` contains no secret → agent tick produces
  a fresh snapshot → widget renders.
- Erase Deck data removes all five keychain items.

## 9. Open questions — all resolved

| # | Question | Resolution |
|---|---|---|
| A1 | Worth doing given no process isolation? | Yes; frame it honestly (§2). *User decision.* |
| A2 | Keychain write cadence | On commit / focus loss (§3). *User decision.* |
| A3 | Locked keychain surface | Its own `FetchOutcome` (§3). *User decision.* |
| A4 | Downgrade after migration | Accepted: re-paste (§5). *Assumption, stated.* |
| A5 | Uninstall deletes items? | Yes (§3). *User decision.* |

## 10. Risks

- 🟡 **A locked login keychain was never tested.** Testing it would have left
  the user with unlock prompts across their other apps that I could not undo
  (`probe.md`). The `credentialsUnavailable` path is therefore designed but
  unproven. Flag it as such at merge; do not claim it is verified.
- 🟡 **Adding a `FetchOutcome` case changes a `Codable` rawValue enum.** A
  status file written by the new build and read by an older one would fail to
  decode that entry. **Resolved by the critique (C5):** give `FetchOutcome` a
  tolerant `init(from:)` mapping an unknown rawValue to `.unreachable`, which is
  the rule `FetchStatus.swift:140-142` already states for unrecognised errors.
- 🟡 **Erase is best-effort and silent (C7).** The five `SecItemDelete` calls
  report nothing, matching the existing `try?` sweep over the container. Erase
  is not a guarantee and should not be described as one.
- 🟡 **A missed hydrate site fails silently** — a token would read as empty and
  the widget would say "not configured" while the credential is safely stored.
  There are exactly two call sites (app, agent); the plan pins both.
