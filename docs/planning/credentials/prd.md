# PRD — Credentials tab (typed account manager)

**Slug:** `credentials` · **Branch:** `feat/credentials/aliz` · **Date:** 2026-08-26

## 1. The ask

> Add a **Credentials** tab under General where the user manages *accounts* with
> types (github, azure, opencode). Multiple accounts per type; each widget picks
> which account it uses, so switching (e.g. between two opencode accounts) is a
> selection rather than a re-paste.

This inverts today's model. A credential is currently a **property of a widget**
— one token per widget slot, welded to a fixed `DeckSecret` case. It becomes a
**first-class record** that widgets reference by id.

### Decisions taken with the user (locked)

| # | Decision |
|---|---|
| D1 | **Per-widget picker, filtered by type.** No global "active account". Each widget's settings tab picks its credential from the accounts of the right kind. |
| D2 | **An account owns its connection identity** — Azure org + project + PAT; opencode server URL + token; GitHub token. Widget tabs keep only what they *display or query*. |
| D3 | **No inline token fields on widget tabs.** Picker + "Manage in Credentials…". One editing surface per secret. |
| D4 | **Manual Verify button per account** (never automatic). Probes the provider, shows the resolved identity, caches Azure's identity GUID. |
| D5 | **Migration auto-creates accounts from the five stored tokens, deduping identical ones**, and pre-selects them so nothing breaks on upgrade. |
| D6 | **The picker replaces PRBox's per-provider Enable toggle.** Account selected = provider on; `None` = off. |
| D7 | **Deleting an in-use account confirms, naming the widgets**, then drops them to "no account" → `notConfigured`. |

## 2. Today's five credentials

| `DeckSecret` | keychain account | widget slot | companion fields today |
|---|---|---|---|
| `openbox.token` | `openbox.token` | OpenBox | `openbox.serverURL` |
| `shipbox.token` | `shipbox.token` | ShipBox | `shipbox.repos`, `repoMode`, `maxRepoCount` |
| `taskbox.token` | `taskbox.token` | TaskBox | `taskbox.organization`, `taskbox.project` |
| `prbox.github.token` | `prbox.github.token` | PRBox·GitHub | `prbox.github.enabled`, `.scope` |
| `prbox.azure.token` | `prbox.azure.token` | PRBox·Azure | `prbox.azure.enabled`, `.organization`, `.project` |

The same GitHub token must be pasted twice (ShipBox + PRBox) and the same Azure
PAT twice (TaskBox + PRBox). That duplication is the concrete pain D5 removes.

## 3. Data model

```swift
enum CredentialKind: String, Codable, CaseIterable { case github, azure, opencode }

/// One stored account. The token is in-memory only — keychain-backed, scrubbed
/// before settings.json is written, exactly like the five fields it replaces.
struct CredentialAccount: Codable, Equatable, Identifiable {
    var id: String                 // opaque, stable, generated once (UUID string)
    var kind: CredentialKind
    var label: String              // user-facing, renamable, e.g. "work"
    var organization = ""          // azure only
    var project = ""               // azure only
    var serverURL = ""             // opencode only
    var token = ""                 // NEVER encoded to settings.json
    // Verification results — non-secret, cached in settings.json.
    var verifiedIdentity: String?  // "haqaliz" / "Ali Haqiqi"
    var azureIdentityID: String?   // connectionData GUID; PRBox needs it
    var verifiedAt: Date?
}

struct CredentialsSettings: Codable, Equatable { var accounts: [CredentialAccount] = [] }
```

**Slots** replace `DeckSecret` at the point of consumption:

```swift
enum CredentialSlot: String, CaseIterable {
    case openbox, shipbox, taskbox, prboxGitHub, prboxAzure
    var kind: CredentialKind    // opencode / github / azure / github / azure
    var source: FetchSource     // .opencodeRemote / .shipbox / .taskbox / .prboxGitHub / .prboxAzure
    var displayName: String     // "OpenBox", "ShipBox", … — used by D7's confirm dialog
}
```

Settings gains `credentials: CredentialsSettings` plus one `accountID: String?`
per slot (`openbox.accountID`, `shipbox.accountID`, `taskbox.accountID`,
`prbox.github.accountID`, `prbox.azure.accountID`).

Resolution is one function:

```swift
func account(for slot: CredentialSlot) -> CredentialAccount?
```

returning `nil` when the id is unset **or dangles** (account deleted behind it).
`nil` → `.notConfigured`, never an error.

### Keychain

One generic-password item per account, service `com.deck.app`, account name
`account.<id>.token`. Ids are generated once and never rewritten — the
CLAUDE.md rule that a rename strands the token applies unchanged. The legacy
five item names stay reserved and are read exactly once, by the migration.

## 4. Migration (one-way, idempotent, host-app only)

Runs at app launch, after the existing `DeckSecretsMigration` (settings.json →
legacy keychain), which stays as-is for users skipping a version.

1. Skip entirely if `credentials.accounts` is non-empty or any slot already has
   an `accountID`.
2. Read the five legacy secrets. For each **non-empty** one, build a candidate
   from the secret plus that widget's connection fields.
3. **Dedupe within a kind**: two candidates collapse only when *every* field
   matches (token, org, project, serverURL). A shared GitHub token becomes one
   account; two different PATs stay two.
4. For each surviving candidate: write `account.<id>.token` → **read back to
   confirm** → set the slot `accountID`(s) → only then delete the legacy
   keychain item. A failure at any step leaves everything untouched and retries
   at the next launch. This is the same ordering the keychain migration already
   proved out; it is why a keychain failure can never cost the only copy.
5. Save settings.

**Labels.** Azure → the organization (`"acme"`); opencode → the server host
(`"nuc"`); GitHub → `"GitHub"`. On a within-kind collision, suffix with the
widget: `"acme (PRBox)"`. All renamable afterwards.

**Agent compatibility.** `DeckAgent` never writes settings, so it can run for
weeks on a file that predates the migration. For one release, every slot
resolution falls back to the legacy `DeckSecret` value when `accountID` is nil
**and** `credentials.accounts` is empty. Without this, upgrading without opening
Deck silently unconfigures four widgets.

## 5. The Credentials tab

Sidebar: a `Credentials` row directly under `General`, above the `Widgets`
section (`key.fill`). Filtered out of the Widgets list the same way `General` is.

One `Form`, `.formStyle(.grouped)`, matching every other tab. A `Section` per
kind; each account is a `DisclosureGroup` — no sheet, no second window, the
640×500 frame is unchanged.

```
Credentials                                             [ + ]
─────────────────────────────────────────────────────────────
GitHub
  ▸ work            ✓ haqaliz · verified 12:04    ShipBox, PRBox
  ▾ personal        — not verified                Unused
        Name        [ personal                              ]
        Token       [ ••••••••••••••••                      ]
        [ Verify ]                            [ Delete… ]
  (empty state) No GitHub accounts. Add one to use ShipBox and PRBox.

Azure DevOps
  ▸ acme            ✓ Ali Haqiqi · verified 12:04  TaskBox
        Name / Organization / Project / PAT

opencode
  ▸ nuc             ✓ reachable · 42 sessions      OpenBox
        Name / Server URL / Token
```

- **`+`** is a menu: *Add GitHub* / *Add Azure DevOps* / *Add opencode*.
- Each row shows **verification state** and **who uses it** ("Unused" when nobody).
- **Verify** (D4) is manual, per account, and writes `verifiedIdentity`,
  `verifiedAt`, and for Azure `azureIdentityID`:
  - **github** — `GET https://api.github.com/user` → `login`; `X-OAuth-Scopes`
    header for the granted scopes. *(new probe, ~30 lines)*
  - **azure** — `_apis/connectionData?api-version=7.1-preview` → display name
    and id. **Reuses `HostAzurePRLoader.requireIdentity`**, which already exists
    precisely because Azure silently returns the whole project's PRs for an
    unparseable identity.
  - **opencode** — `RemoteOpenCodeLoader.load(serverURL:token:)`; success is the
    probe, and it reports the session count. No new endpoint knowledge.
  - Any edit to a token, org or server URL **clears** the cached verification —
    a stale GUID against a new token is worse than none.
- **Delete…** confirms with the using widgets named (D7), removes the keychain
  item, and leaves the dangling ids to resolve as `nil`.

## 6. Widget tab changes

| Tab | Removed | Added | Kept |
|---|---|---|---|
| OpenBox | Token, Server URL | `Account:` picker (opencode) | charts, models, tools, sessions |
| ShipBox | Token | `Account:` picker (github) | repo mode, repo list, counts, colors |
| TaskBox | Organization, Project, Token | `Account:` picker (azure) | legend, count, state mapping, colors |
| PRBox·GitHub | Enable toggle, Token | `Account:` picker (github) | Scope |
| PRBox·Azure | Enable toggle, Organization, Project, Token | `Account:` picker (azure) | — |

Every picker: `None` + the accounts of that kind, with a trailing
**"Manage in Credentials…"** that switches the sidebar selection (a closure
passed down from `ContentView`, which owns `selection`). When no account of the
kind exists the picker is disabled and reads "No accounts — add one in
Credentials".

The existing `FetchStatusCaption` stays on every one of these tabs unchanged.

## 7. Failure behaviour

| Situation | Result |
|---|---|
| Slot has no account | `.notConfigured` — today's behaviour, same copy |
| Slot points at a deleted account | `.notConfigured` (resolution returns nil) |
| Account exists, keychain read failed | `.credentialsUnavailable` for that slot's `FetchSource` — the existing locked-keychain path, now keyed by slot instead of `DeckSecret` |
| Account exists, token empty | `.notConfigured` |
| Azure account with no org/project | `.notConfigured` (matches today's guard) |
| Verify fails | Red caption on the account row only. Never changes a widget's stored status. |

## 8. Non-goals

- **No OAuth or device-flow sign-in.** Tokens are pasted, as today.
- **No new security properties.** The CLAUDE.md caveat stands verbatim: the
  keychain gives confidentiality at rest, not isolation from other local
  processes. The README wording does not change.
- **No new providers** (GitLab, Bitbucket). `CredentialKind` is extensible; it
  ships with three.
- **No sync** of accounts across machines, no export/import.
- **No widget face changes.** Nothing renders differently on the desktop except
  as a consequence of pointing a widget at a different account.
- **No per-account refresh cadence.** Everything stays on the 60s tick.
- **No credential sharing with the keyless widgets** (Weather, MarketBox) —
  they have no credentials and gain no tab entry.

## 9. Invariants at risk (CLAUDE.md)

- 🔴 **Tolerant decode.** `credentials` and every new `accountID` key must use
  `decodeIfPresent`. A throwing decode resets *every* setting via
  `DeckSettings.load()`'s `?? DeckSettings()`. Pinned by a regression test in
  `DecodeTests.swift`.
- 🔴 **`scrubbedOfSecrets()` must blank every account token**, not the five
  fixed fields. A missed account writes a live token into `settings.json`.
  Pinned by a test that round-trips an encoded file and greps for the value.
- 🟡 **No widget is added**, so the WidgetKit descriptor-cache trap does not
  apply and no version bump is needed for gallery reasons (one still ships with
  the release).
- 🟡 **No Swift Charts** anywhere near this work.
- 🟡 `xcodegen generate` must be re-run for the new source files, or they are
  silently not compiled and the suite still reports success.

## 10. Test plan (TDD targets — pure logic, `DeckSharedTests`)

1. `CredentialAccount` / `CredentialsSettings` tolerant decode (missing key,
   unknown kind, garbage) — never throws, never resets siblings.
2. `scrubbedOfSecrets()` blanks N account tokens; encoded JSON contains none.
3. `hydrate(from:)` per account: `.found` overwrites, `.absent`/`.failed` leave
   the decoded value, failures are reported per slot.
4. `account(for: slot)` — unset → nil; dangling id → nil; kind mismatch → nil.
5. Migration: five secrets → deduped accounts; identical GitHub tokens collapse;
   differing ones don't; write-fails and readback-fails leave state untouched
   and delete nothing; second run is a no-op.
6. Migration labels + collision suffixes.
7. Legacy fallback: unmigrated settings + legacy keychain items → every slot
   still resolves a token.
8. GitHub `/user` and Azure `connectionData` verify parsers, from fixtures.
9. Delete: which slots reference an account (drives D7's dialog copy).

UI (`DeckApp.swift`) is verified by build + a manual pass over the six tabs.

## 11. Open questions

- **Azure project on the account (D2·A)** means TaskBox on project *Manifold*
  and PRBox on project *Foresight* requires **two azure accounts sharing one
  PAT**. Chosen knowingly; flagged here because it is the one ergonomic cost of
  the simpler model, and it shows up the first time someone tries it.
- **Legacy keychain items are deleted after a confirmed readback.** The
  alternative — leaving them — means two copies of the same live token on disk
  with only one editable. Deleting is the choice; downgrade to a previous Deck
  build after migrating would find no tokens.
