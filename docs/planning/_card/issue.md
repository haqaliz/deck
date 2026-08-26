# feat/credentials — Credentials tab (typed account manager)

## Inline brief (from the user, 2026-08-26)

> In the app I want another tab below General called **Credentials**, and users
> must control the accounts w/ types from there (github, azure, opencode, ...).
> So based on that users can have 2 opencode accounts and whenever they decide,
> switch to another account.

## Reading

Today Deck stores exactly five credentials, each welded to one widget:

| `DeckSecret` | keychain account | owning widget | companion fields (settings.json) |
|---|---|---|---|
| `openbox.token`      | OpenBox   | opencode remote | `openbox.serverURL` |
| `shipbox.token`      | ShipBox   | GitHub          | `shipbox.repos`, `repoMode`, `maxRepoCount` |
| `taskbox.token`      | TaskBox   | Azure DevOps    | `taskbox.organization`, `taskbox.project` |
| `prbox.github.token` | PRBox     | GitHub          | `prbox.github.enabled`, `.scope` |
| `prbox.azure.token`  | PRBox     | Azure DevOps    | `prbox.azure.enabled`, `.organization`, `.project` |

There is no concept of an *account*: a credential is a property of a widget, one
per widget, and the same GitHub token must be pasted twice (ShipBox + PRBox).
The ask is to invert that — credentials become first-class, typed, named,
many-per-type records that widgets **reference**.

## Scope signals
- New sidebar row directly under General.
- Typed accounts: github, azure, opencode (the three credentialed backends Deck
  actually has).
- Multiple accounts per type, with a switch.
