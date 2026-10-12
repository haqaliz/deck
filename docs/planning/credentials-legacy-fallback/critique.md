# Critique — credentials-legacy-fallback

Self-critique of `prd.md` against the shell invariants and the removal's blast
radius. Nothing red; four amber, all now folded into the PRD.

## 🔴 Red

None.

- No shell invariant is touched: the widget extension stays token-free
  (`openBoxUsesRemoteServer` / `prBoxGitHubIsOn` / `prBoxAzureIsOn` turn on
  account presence and `account.serverURL` only), the panel is untouched, and no
  snapshot schema or settings key changes.
- No data source is involved.

## 🟡 Amber (each fixed in the PRD)

1. **The handed-off brief was wrong, not merely incomplete.** It said to delete
   `legacyCredential(for:)` and drop the welded fields. Both migrations consume
   those (`CredentialsMigration.swift:215`, `DeckKeychain.swift:191`). *Fix:*
   scope is the fetch-time fallback only (D1/D2), stated at the top of the PRD.

2. **The test impact was understated.** A first pass named only the
   `fetchSource` parity block and two gate lines. The fallback is pinned by name
   in five more tests, including one whose entire purpose is the fallback
   (`CredentialsMigrationTests.testAnUnmigratedSettingsStillResolvesEverySlotFromTheLegacyFields`)
   and two `CredentialGateTests` that call the deleted overload. *Fix:* §5 now
   enumerates every affected test and whether it inverts, is deleted, or is
   unchanged. Without this the plan would have "kept the suite green" by not
   compiling the changed files (the xcodegen-new-file trap) or by leaving
   assertions that now encode the opposite of the truth.

3. **`credential(for:)` needs an explicit `return nil`.** Deleting lines 39-41
   leaves a non-void function with an uncovered fall-through; Swift requires the
   return. *Fix:* §4.1 states it.

4. **`legacyCredential(for:)`'s doc comment becomes a lie.** It says the fallback
   "goes inert once the migration runs"; after D1 it is migration-only. *Fix:*
   §4.1 requires the reword.

## Minor, deliberately not actioned

- `DeckSettings.hydrate(from:)` still returns `Set<DeckSecret>` and computes
  `failed`, but the app's bridge discards the result (`_ =`). It could become
  `Void`, but the migration-safety tests exercise the return, so leaving it is
  cheaper and safer than churning the signature.
- `CredentialSlot.legacySecret` keeps its name; it is still the migration's
  keychain-item lookup (`CredentialsMigration.swift:250,252`).
