# Settings schema migration — inline brief

Source: `deck-next` handoff (2026-08-12), pick: `settings-schema-migration`.

Harden the remaining settings structs (`OpenBoxSettings`, `NetBoxSettings`,
`BatBoxSettings`, `GitBoxSettings`, `DevBoxSettings`) against missing-key
decode resets: `DeckSettings.load()` falls back to all-defaults when decoding
throws (DeckSettings.swift:61-64) and Swift's synthesized `Decodable` throws
on a missing non-optional key — so every new settings field silently wipes
all user settings for anyone with an older `settings.json`. The latent bug
shipped with DevBox (48e386a) and was flagged as a follow-up in PR #7.

## Caveats to resolve in the PRD

- **Preserve decode semantics**: values present in existing `settings.json`
  must decode identically; only missing keys fall back to defaults. Verify
  against the user's real `settings.json` (which now carries
  `showPerCoreCores`).
- **TDD**: decode logic tested in a scratch SwiftPM package first (mirror
  structs; SwiftUI/AppKit imports are fine on macOS), then ported into
  `native/Shared/DeckSettings.swift`.

## Constraints from the pick

- Shell untouched in behavior: settings persistence path, container, widget
  data paths unchanged.
- Mark M4's "settings schema migration" checkbox (ROADMAP.md:51) when done.
- Port the `LiveBoxSettings` `decodeIfPresent` custom `init(from:)` pattern
  (PR #7, `DeckSettings.swift`) to each of the five structs.
