# PRD — Remove the legacy per-slot credential fallback

**Slug:** `credentials-legacy-fallback` · **Branch:** `chore/credentials-legacy-fallback/aliz` · **Date:** 2026-10-12 · **Type:** chore

## 1. The ask

> Remove the legacy per-slot credential fallback — the one-release courtesy for
> a Deck upgraded to the accounts model but never opened, overdue since v1.30
> shipped (`ROADMAP.md:971-972`).

### Correction to the handed-off brief (locked with the user)

The `deck-next` brief said *"delete `DeckSettings.legacyCredential(for:)` and
drop the welded token/connection fields from the four widget settings structs"*.
The dig found that **unsafe**: the two one-way migrations consume exactly those
things.

- `CredentialsMigration.migrate` reads `settings.legacyCredential(for: slot)`
  (`CredentialsMigration.swift:215`) to build accounts.
- `DeckSecretsMigration.migrate` reads `settings.secretValue(secret)`
  (`DeckKeychain.swift:191`) to move fields into the keychain.

`legacyCredential(for:)` is shared by the migration **and** the fetch-time
fallback. Deleting it breaks the ≤v1.29 → current upgrade. Therefore:

| # | Decision |
|---|---|
| D1 | **Remove the fetch-time fallback only.** Keep both migrations, `DeckSecret`, and the welded fields they consume. |
| D2 | **Keep `legacyCredential(for:)`** — it is the migration's input, not just the fallback's. |
| D3 | **Delete the already-dead `DeckSecret.fetchSource`** (`FetchStatus.swift:52-63`) and the tests that pin it. |

## 2. What "the fallback" is, precisely

`credential(for: slot)` today resolves in this order
(`CredentialsMigration.swift:28-42`):

1. A selected **account** wins.
2. A **dangling** selection (deleted/wrong-kind account) → not configured.
3. **No selection at all** → consult the pre-accounts `settings.json` fields via
   `legacyCredential(for:)`.

Step 3 is the fallback. It exists because `DeckAgent` reads settings and never
writes them, so it can run for weeks on a file the migrations have not touched —
without step 3, upgrading and never opening Deck would silently unconfigure four
widgets. It was always meant to expire one release after the accounts model
shipped. It did not.

After this chore, step 3 is gone: **no account → not configured**.

## 3. User-visible behaviour change

| Scenario | Before | After |
|---|---|---|
| Migrated install (accounts, fields blank) | fetch with account | **unchanged** — fetch with account |
| ≤v1.29 Deck, **opens** the app | both migrations run, tokens become accounts | **unchanged** |
| ≤v1.29 Deck, **never opened**, agent runs | agent fetches with the `settings.json` token | **credential widgets read as off/unconfigured until Deck is opened** |

The third row is the entire behaviour change, and it is the courtesy expiring by
design. Nothing on a migrated install changes: the fields are already blank, so
the old fallback returned empty and `credential(for:)` returned `nil` anyway.

The widget-extension reads (`openBoxUsesRemoteServer`, `prBoxGitHubIsOn`,
`prBoxAzureIsOn`) lose their legacy branches too: an unmigrated file now renders
OpenBox as **local** and PRBox providers **off**, which is the same "off" the
gate reports — no crash, no wrong face, no log.

## 4. Exact removal set

### 4.1 `Shared/CredentialsMigration.swift`

- `credential(for:)` — delete the tail (lines 39-41), leaving an explicit
  `return nil` (the `if let account` block returns on its own; Swift needs the
  fall-through covered). The doc comment loses its "Only a slot with no
  selection at all consults the legacy field" sentence and its dangling-id
  paragraph stays.
- `legacyCredential(for:)` — **keep**, but its doc comment ("The pre-accounts
  shape, for a Deck that was upgraded but never opened") is now wrong: it is the
  migrations' input. Reword to say so.
- `gate(_:unavailable:)` — line 113's `legacyCredential(...).token.isEmpty` test
  collapses to `accountID(for: slot) == nil ? .off : .notConfigured`.
- `gate(_:unavailableAccounts:unavailableLegacySecrets:)` (lines 144-153) —
  **delete the overload**; every caller moves to `gate(_:unavailable:)`.
- `openBoxUsesRemoteServer` (lines 162-168) — drop the legacy branch; no account
  → local.
- `prBoxGitHubIsOn` / `prBoxAzureIsOn` / `providerIsOn` (lines 172-183) — drop
  the `legacyEnabled:` parameter and the legacy branch; presence of an account
  *is* "on".

### 4.2 `Shared/FetchStatus.swift`

- Delete `extension DeckSecret { var fetchSource … }` (lines 52-63). Production
  callers: none (the agent records `slot.source`, a `CredentialSlot`).

### 4.3 `DeckAgent/main.swift`

- Delete `let unavailableLegacy = settings.hydrateFromKeychain()` (line 86).
- Change the gate call (lines 87-90) to
  `settings.gate($0, unavailable: unavailableAccounts)`.

### 4.4 `DeckApp/DeckApp.swift`

- Delete `@State private var unavailableSecrets: Set<DeckSecret>` (line 249).
- In `adoptKeychainSecrets` (lines 824-841): **keep** `_ = migrated.hydrateFromKeychain()`
  (line 830) — it is the bridge between the two migrations. Delete the
  `unavailableSecrets = …` assignment (line 837) and the `gate(_:)` helper's
  legacy argument (lines 844-847), which becomes
  `settings.gate(slot, unavailable: unavailableAccounts)`.

### 4.5 Kept, deliberately

`DeckSecret`; `DeckKeychain.{read,write,delete,readAll}` (legacy items);
`DeckSecretsMigration`; `CredentialsMigration`; `DeckSettings.{setSecret,
secretValue,hydrate,hydrateFromKeychain}`; `legacyCredential(for:)`;
`CredentialSlot.legacySecret`; the welded fields (`OpenBoxSettings.token` /
`.serverURL`, `ShipBoxSettings.token`, `TaskBoxSettings.token` /
`.organization` / `.project`, `PRGitHubSettings.token` / `.enabled`,
`PRAzureSettings.token` / `.enabled` / `.organization` / `.project`);
`scrubbedOfSecrets`'s five-field blanking.

## 5. Tests

The fallback is pinned by name in more places than a first pass suggests. The
exact set:

| File / test | Change |
|---|---|
| `CredentialsMigrationTests.testAnUnmigratedSettingsStillResolvesEverySlotFromTheLegacyFields` (≈274-289, under a "one-release fallback" MARK) | **Delete** — it asserts exactly the behaviour D1 removes. |
| `CredentialsMigrationTests` `testClearingASlotAfterMigrationResurrectsNothing` / `…DeletedAccountDoesNotFallBack…` / `…ResolvedAccountWinsOverTheLegacyField` | Still pass (they assert account-wins / dangling-does-not-revive / blanked-after-migration). Reword the names/comments that say "legacy field"; keep the assertions. |
| `CredentialsMigrationTests.testAnEmptyTokenIsNotAUsableCredential` | Unchanged. |
| `CredentialGateTests.testAnUnmigratedSlotStillFetches` (≈129-133) | **Invert**: `s.shipbox.token = "ghp"` with no account now yields `.off`, not `.fetch`. This is the D1 pin. |
| `CredentialGateTests.testAnUnreadableLegacyItemIsUnavailableToo` (≈145-152) | **Delete** — the overload it calls is gone. |
| `CredentialGateTests.testALegacyFailureIsIgnoredOnceTheSlotHasAnAccount` (≈154-161) | Delete (or rewrite without the argument; it now duplicates the account-wins test). |
| `CredentialsWidgetReadsTests.testOpenBoxHonoursTheLegacyServerURLBeforeMigration` (≈52-58) | **Invert**: a set `openbox.serverURL` with no account now reads **local**. |
| `CredentialsWidgetReadsTests.testAProviderHonoursTheLegacyEnabledFlagBeforeMigration` (≈93-98) | **Invert**: `prbox.github.enabled = true` with no account now reads **off**. |
| `CredentialsWidgetReadsTests` migration tests (≈180-200) | Unchanged — `CredentialsMigration` survives. |
| `CredentialsWidgetReadsTests.testMigrationLeavesAnUnmigratedSlotsFieldsAlone` (≈175-195) | **Found in implementation, not the plan.** Renamed `testAFailedMigrationKeepsTheFieldsButTheyAreNotAFetchPath`: the fields are still preserved for the retry, but `credential(for:)` now returns nil. |
| `CredentialsWidgetReadsTests.testMigrationClearsThePRBoxEnabledFlagItRepresentedAsASelection` (≈162-173) | Comment reworded; assertion unchanged (the migration still clears the field). |
| `CredentialsWiringTests` `DeckSecret.fetchSource` parity block (≈230-239) | **Delete** with the extension. |
| `FetchStatusCredentialsTests.swift` | **Delete whole file** — it exists only to pin `DeckSecret.fetchSource`. |
| `DecodeTests.testProviderIsOnlyUsableWhenItHasAnAccountWithCredentials` (≈790-816) | Unchanged (starts from an empty `DeckSettings()`, no legacy field). |
| `DeckSecretsMigrationTests.swift`, `DeckSettingsSecretsTests.swift`, `DeckKeychainTests.swift`, remaining `DecodeTests` OpenBox `serverURL` cases | **Unchanged** — migrations and fields survive. |

## 6. Shell fit / invariants

- The widget extension keeps **no keychain access**: the three extension-read
  predicates turn on account presence and `account.serverURL` only — never a
  token. `grep -rn "\.enabled\|serverURL" native/DeckWidgets/` stays clean.
- "A migration that moves a field must clear the old copy" still holds — both
  migrations are untouched.
- No snapshot schema, no `FetchSource`, no settings key changes.

## 7. Non-goals

- **Not** removing `DeckSecretsMigration`, `CredentialsMigration`, `DeckSecret`,
  or the welded fields (that would strand a ≤v1.30 upgrade — decided against,
  D1).
- **Not** changing the account model, the gate's three answers, or any loader.
- **Not** a version bump beyond the routine release bump (no new widget).

## 8. Open questions

None outstanding — scope (D1/D2/D3) was settled with the user before writing.
