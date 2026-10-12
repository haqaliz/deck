# Understanding — credentials-legacy-fallback

## What the work is really asking

Remove the **fetch-time legacy credential fallback** — the pre-accounts
compatibility shim that lets `DeckAgent` (and the widget extension) fetch with a
token still sitting in `settings.json`, for a Deck that was upgraded from ≤v1.29
but never opened. The ROADMAP records it as a one-release courtesy, overdue
since v1.30 shipped (`ROADMAP.md:971-972`).

## The brief is internally inconsistent — this is the finding

The `deck-next` handoff said to *delete `legacyCredential(for:)` and drop the
welded settings fields*. The dig shows that is **unsafe**: both one-way
migrations read those very things.

The pre-accounts layer is two chained migrations plus a fetch-time fallback:

1. `DeckSecretsMigration.migrate` (`DeckKeychain.swift:184`) — moves the welded
   `settings.json` fields into the legacy keychain items (`DeckSecret`), then
   blanks the fields. Reads `settings.secretValue(secret)`.
2. `CredentialsMigration.migrate` (`CredentialsMigration.swift:199`) — moves the
   fields into `CredentialAccount`s, blanks the fields, deletes the legacy
   keychain items. Reads `settings.legacyCredential(for: slot)` (line 215).
3. The **fallback** — `credential(for:)` consults `legacyCredential(for:)` when
   no account is selected (`CredentialsMigration.swift:39-41`).

`legacyCredential(for:)` is used by **both** the migration (line 215) and the
fetch-time fallback (line 40). Deleting it breaks migration #2. Dropping the
welded fields breaks both migrations. So the correct scope is: **remove the
fetch-time reads, keep the migrations and the fields they consume.**

## Affected files and symbols

### Remove (fetch-time fallback)

| Site | What |
|---|---|
| `Shared/CredentialsMigration.swift:39-41` | the `legacyCredential` tail of `credential(for:)` |
| `Shared/CredentialsMigration.swift:113` | `gate(_:unavailable:)`'s `legacyCredential(...).token.isEmpty` test |
| `Shared/CredentialsMigration.swift:144-153` | `gate(_:unavailableAccounts:unavailableLegacySecrets:)` overload |
| `Shared/CredentialsMigration.swift:165-167` | `openBoxUsesRemoteServer` legacy branch |
| `Shared/CredentialsMigration.swift:172-183` | `providerIsOn(_:legacyEnabled:)` + `prBoxGitHubIsOn`/`prBoxAzureIsOn` |
| `DeckAgent/main.swift:86,88-89` | `hydrateFromKeychain()` + the legacy gate overload |
| `DeckApp/DeckApp.swift:249,837,845-846` | `unavailableSecrets` state + legacy gate overload |
| `Shared/FetchStatus.swift:52-63` | `DeckSecret.fetchSource` — **already dead in production**, only tests call it |
| `Shared/CredentialAccount.swift:306-316` | `CredentialSlot.legacySecret` if the only remaining caller is `CredentialsMigration` (line 250/252) — **still used by the migration, keep** |

### Keep (migrations + their inputs)

- `DeckSecret`, `DeckKeychain.{read,write,delete,readAll}` (legacy items)
- `DeckSecretsMigration`, `CredentialsMigration`
- `DeckSettings.{setSecret,secretValue,hydrate,hydrateFromKeychain}`
- `legacyCredential(for:)` — the migration's input
- The welded fields on `OpenBoxSettings` (`token`,`serverURL`),
  `ShipBoxSettings` (`token`), `TaskBoxSettings`
  (`token`,`organization`,`project`), `PRGitHubSettings`
  (`token`,`enabled`), `PRAzureSettings`
  (`token`,`enabled`,`organization`,`project`) — decode inputs for the migration
- `DeckSettings.scrubbedOfSecrets`'s five-field blanking (`DeckSettings.swift:243-247`)
- `DeckApp.adoptKeychainSecrets` (`DeckApp.swift:824-841`) — the *only* place
  `hydrateFromKeychain` still runs between the two migrations

### Tests to update / delete

- `CredentialsWidgetReadsTests.swift` — the legacy-fallback cases (lines 55-57,
  140-145) become "no account → local / provider off".
- `CredentialsWiringTests.swift:230-239` — the `DeckSecret.fetchSource` parity
  block goes with the extension.
- `CredentialGateTests.swift:148,157` — drop the `unavailableLegacySecrets:`
  argument.
- `FetchStatusCredentialsTests.swift` — pins the removed `DeckSecret.fetchSource`.
- `DecodeTests.swift` — OpenBox `serverURL` decode still valid (field kept).
- `DeckSecretsMigrationTests.swift`, `DeckSettingsSecretsTests.swift`,
  `CredentialsMigrationTests.swift` — **unchanged**; the migrations stay.

## The one user-visible change

A Deck upgraded from ≤v1.29 that **never opens the app** now reads its
credential widgets as *off / unconfigured* instead of fetching with the
pre-accounts token. A ≤v1.29 Deck that **does** open migrates exactly as today
(both migrations run). On a migrated install nothing changes — the fields are
already blank, so the fallback returned empty anyway.

## Shell invariants checked (CLAUDE.md)

- The widget extension has **no keychain access**: `openBoxUsesRemoteServer` /
  `prBoxGitHubIsOn` / `prBoxAzureIsOn` turn only on non-secret fields
  (`account.serverURL`, account presence). After removal they read accounts
  only — still token-free. ✅
- "A migration that moves a field must clear the old copy": both migrations
  still clear; nothing removed here weakens that. ✅
- `grep -rn "\.enabled\|serverURL" native/DeckWidgets/` must stay clean — after
  removal the extension reads `openBoxUsesRemoteServer`/`prBox*IsOn` only. ✅

## Open questions

1. **Scope depth.** (A) remove the fetch-time fallback only, keep both
   migrations and the fields [recommended, matches the ROADMAP]; (B) also rip
   out `DeckSecretsMigration` + the welded fields + `DeckSecret`, accepting that
   a ≤v1.30 → current upgrade loses tokens. The dig favours (A).
2. Whether to also delete the already-dead `DeckSecret.fetchSource` (and its
   tests) in the same pass, or leave it. It is production-dead today.
