# credentials-legacy-fallback (inline brief)

Source: `dbf chore credentials-legacy-fallback`, handed off by `deck-next` (2026-10-12).

## Brief

Remove the legacy per-slot credential fallback now that the one-release courtesy
is long overdue. The repo is v1.52; the fallback was written as a single-release
courtesy for a Deck upgraded to the accounts model but never opened, and the
ROADMAP has carried it open since v1.30 shipped (`ROADMAP.md:971-972`).

Delete `DeckSettings.legacyCredential(for:)` and its call site in
`credential(for:)`, drop the welded token/connection fields from the four widget
settings structs, and reduce `DeckSecret` to the one-way migration path only.
Clear the old copies as part of the removal — a migration that leaves a dead
field behind lets the pre-migration fallback keep answering (see the CLAUDE.md
trap). Tighten the existing legacy-parity tests to pin the new behaviour and
confirm `settings.json` no longer round-trips the dead fields.

Respect the shell invariants: the widget extension has **no keychain access at
all**, so anything the extension reads must stay answerable from `settings.json`
without a token; and any migration that moves a field must clear the old copy.

## Why this and not something else

- Open **M8** item, explicitly *"the one-release courtesy from the credentials
  entry, overdue since v1.30 shipped"* (`ROADMAP.md:971-972`); the repo is at
  v1.52.
- Pure shell-reuse cleanup with a proven data path and no new source: the
  fallback is consulted only when `accountID(for: slot) == nil`
  (`CredentialsMigration.swift:39-41`).
- Fully local and already unit-pinned (`CredentialsWidgetReadsTests`,
  `CredentialsWiringTests`, `DeckSecretsMigrationTests`), so the first slice is
  unambiguous.

## Caveat (from the recommender)

This touches the exact seam the ROADMAP warns about — a migration that moves a
field must clear the old copy, or the pre-migration fallback keeps answering
from a dead field (`CLAUDE.md`). Removal must delete the legacy fields, not
merely stop reading them, or a future migration re-introduces the
silently-wrong face. Nothing here is gated on M9.
