# PRD critique — `credentials`

Pressure-test of `prd.md`, 2026-08-26. Nine findings; five change the design.

## 🔴 Red

### R1 — The widget extension reads two fields this PRD moves. Both break silently.

`grep` over `DeckWidgets/` finds exactly two settings reads that this change
invalidates, and neither fails loudly:

- `OpenBoxWidget.swift:101` — `let isRemote = !(openboxSettings.serverURL ?? "").isEmpty`.
  `serverURL` moves onto the opencode account (D2), so this reads empty forever
  and OpenBox renders **permanently in local-DB mode** no matter which remote
  account is picked.
- `PRBoxWidget.swift:79-80` — `githubEnabled: settings.github.enabled`,
  `azureEnabled: settings.azure.enabled`. D6 deletes those toggles, so both read
  `false` forever and PRBox renders as **both providers off**.

**Fix.** Accounts minus their tokens *are* in `settings.json`, so the sandboxed
extension can resolve them. Add a non-secret resolver usable from the extension:

```swift
extension DeckSettings {
    func account(for slot: CredentialSlot) -> CredentialAccount?   // token blank in the extension
}
```

then `isRemote = account(for: .openbox)?.serverURL.isEmpty == false`, and
`githubEnabled = prbox.github.accountID != nil`. Both are covered by the test in
§10.4 plus a build-and-add pass over the two widgets.

### R2 — Migration would silently re-enable a PRBox provider the user turned off.

`prbox.github.enabled` / `prbox.azure.enabled` default to **false**, and a user
can have a token stored on a provider they deliberately switched off. D5 creates
an account from every non-empty token and pre-selects it; D6 makes "selected"
mean "on". Net effect on upgrade: a disabled provider starts fetching, and PRBox
starts showing a second stream of rows the user had removed.

**Fix.** Migration creates the account either way (never lose a token) but sets
`accountID` **only when the provider was enabled**. A disabled provider migrates
to an account that exists in the Credentials tab, marked `Unused`, with the
picker on `None`. One extra migration test: `enabled == false` → account created,
`accountID == nil`.

### R3 — `DeckSettings.CodingKeys` is hand-written; a forgotten case encodes nothing.

`DeckSettings` deliberately does **not** use a synthesized decoder (it carries a
second key set for legacy `homebox`). Adding `credentials` to the struct without
adding it to `CodingKeys` compiles, decodes as absent, and **never encodes** —
so every account silently vanishes at the next save, which is also the next
keystroke, because `onChange(of: settings)` saves on every mutation. The failure
is total and looks like "the tab doesn't work".

**Fix.** Add `credentials` to `CodingKeys` **and** to the explicit
`init(from:)`, both with `decodeIfPresent`. Pin with a round-trip test that
encodes a settings value holding two accounts and decodes it back equal
(tokens excluded — see R4).

### R4 — `scrubbedOfSecrets()` is written against five fixed fields.

It blanks `openbox.token`, `shipbox.token`, `taskbox.token` and PRBox's two.
With N accounts it must iterate `credentials.accounts` and blank each `token`.
Miss it and Deck writes **live tokens into `settings.json`** — the exact
regression the keychain work existed to remove.

**Fix.** Rewrite as a loop over the accounts (keep the five legacy blanks while
the legacy fallback lives). Pin with a test that encodes a settings value
containing a sentinel token string and asserts the sentinel does not appear
anywhere in the encoded bytes.

### R5 — `unavailableSecrets` is `Set<DeckSecret>`; nothing in the PRD retypes it.

`ContentView.unavailableSecrets` and `DeckAgent`'s `settings.hydrateFromKeychain()`
return `Set<DeckSecret>`, and both are compared per widget to decide
`.credentialsUnavailable` vs `.notConfigured` — the distinction the ROADMAP calls
out as the ShipBox C1 mistake. Accounts are dynamic, so `DeckSecret` cannot
express them.

**Fix.** `hydrate` returns `Set<String>` (failed account ids). Each call site
maps slot → account id → membership. `FetchStatus.source(for: DeckSecret)`
becomes `CredentialSlot.source`, and `DeckSecret` survives as **migration-only**
code with a comment saying so. Existing `FetchStatusCredentialsTests` are
re-pointed at slots.

## 🟡 Amber

### A1 — `SecretField` is welded to `DeckSecret`.

It calls `DeckKeychain.write(secret, value:)` on blur. The account editor needs
the same focus/commit/hydrate behaviour keyed by account id.

**Fix.** Generalise to take a `write: (String) -> OSStatus` closure (or an
`AccountSecretField` sibling). Keep the commit semantics identical — commit on
blur and on submit, never on keystroke — because the settings file is written on
every `settings` change and a per-keystroke keychain write is both wasteful and
racy.

### A2 — `FetchStatusCaption(clearOn:)` keys off the token string.

Today: `clearOn: "\(serverURL)\u{0}\(token)"`, so a stale failure chip clears
when the user fixes the credential. Tokens leave the widget tabs (D3), so the key
must change or the chip goes stale forever.

**Fix.** `clearOn` becomes the account id plus the account's non-secret fields
plus `verifiedAt` — changing the account, editing its server URL, or re-verifying
all clear the chip, which is exactly the set of user actions that could fix it.

### A3 — Two accounts of one kind may share a label; the picker becomes a coin flip.

Nothing forbids two GitHub accounts both called "work".

**Fix.** Don't enforce uniqueness (renaming under a constraint is miserable).
Show a subtitle in every picker row and account row: the org for Azure, the host
for opencode, the verified login for GitHub, falling back to the id's first six
characters. Cheap, and it makes D5's collision suffixes cosmetic rather than
load-bearing.

### A4 — Don't let PRBox's fetch trust the cached Azure identity GUID.

The PRD says Verify caches `azureIdentityID` and hints PRBox could use it.
CLAUDE.md records what a wrong identity does: Azure answers **200 with every
active PR in the project**, and nothing in the response says the filter was
ignored. A GUID cached against a token that has since been replaced, or an org
that has been re-typed, would render the whole team's work as the user's own.

**Fix.** In this change the cached GUID is **display only**. `HostAzurePRLoader`
keeps resolving identity live per fetch and keeps failing closed. Revisit as its
own change with its own invalidation rules.

## Non-findings, recorded so they aren't re-litigated

- **`isUsable` is agent-only.** `grep` confirms `isAnyProviderUsable` / `isUsable`
  are read in `DeckAgent/main.swift` only — the agent hydrates from the keychain,
  so a token-based check is sound there and needs no extension-safe rewrite
  beyond the accountID swap.
- **No widget is added**, so the WidgetKit descriptor-cache trap and the Swift
  Charts trap are both out of scope.
- **OpenBox local vs remote gets *clearer*, not murkier**: `None` = local DB,
  an account with a server URL = remote. Worth saying in the tab's caption.
