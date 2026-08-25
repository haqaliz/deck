# Card — Keychain for Deck's API credentials

**Type:** feat · **Slug:** `keychain-tokens` · **Branch:** `feat/keychain-tokens/aliz`

**Source:** inline brief, handed off by `deck-next` on 2026-08-25. No GitHub
issue — the id is a slug, not a number.

## Brief

Move Deck's API credentials out of cleartext `settings.json` into the login
keychain. There are five token fields, not the three `ROADMAP.md` M7 claims:
OpenBox, ShipBox, TaskBox, and PRBox's separate GitHub and Azure tokens
(`native/Shared/DeckSettings.swift:256`, `:504`, `:600`, `:744`, `:772`) — the
M7 entry predates PRBox shipping two.

Both `DeckApp` (writes, from the settings tabs) and `DeckAgent` (reads, every
60s under launchd) need access; the widget extension never touches them and
should keep seeing empty fields. Ship a one-way migration that copies each
existing value into the keychain and scrubs it from `settings.json`, without
breaking the tolerant-decode regression tests.

## The blocking risk to settle first

A keychain item's ACL is per-binary, and `Deck.app` and `DeckAgent` are
separately signed, so the agent will hit an access prompt it cannot answer
under launchd (or `errSecInteractionNotAllowed`) and four widgets go dark with
no fetch error that explains it. That likely needs a shared
`keychain-access-groups` entitlement under team `K6X49DG8VF` — and
`native/project.yml` has no entitlements file for any target today, with
`DeckAgent` being a `type: tool` with no bundle.

**Verify a successful agent-side read while running under launchd, not from a
terminal, before committing to the design.**

## Why this was picked (deck-next, 2026-08-25)

- The only `ROADMAP.md` M7 item that is fully unblocked: notarization and the
  expiry cliff need the paid program, "verify on a second Mac" needs a second
  Mac, Sparkle is "pointless before notarization", and the bundle-identifier
  rename plus the landing page wait on a launch-identity decision.
- Named by three independent planning docs: `ROADMAP.md` M7 (where 0600 on
  `settings.json` is explicitly "the interim measure"), TaskBox's open
  follow-ups ("Keychain storage for the PAT") and PRBox's ("Keychain for the
  two tokens").
- Pure shell reuse: no widget, no snapshot, no sampler, no new data source.
