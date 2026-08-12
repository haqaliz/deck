# Settings schema migration — PRD

## Ask

Make settings decoding tolerant of schema evolution so no future settings key
can wipe a user's settings. Five structs (`OpenBoxSettings`, `NetBoxSettings`,
`BatBoxSettings`, `GitBoxSettings`, `DevBoxSettings`) still use Swift's
synthesized `Decodable`, which throws on a missing non-optional key; with
`DeckSettings.load()`'s `?? DeckSettings()` fallback (DeckSettings.swift:61-64)
that resets **every** setting (colors, token, repo paths, counts) for any user
with an older `settings.json`. Slug: `settings-schema-migration`.

Source: `deck-next` handoff → `docs/planning/_card/issue.md`; follow-up flagged
in PR #7 and `docs/planning/livebox-per-core-cpu/plan_20260812.md`.

## User-visible spec

No UI changes at all. Behavior change is invisible unless it works: a user with
a pre-DevBox (or older) `settings.json` keeps their settings after updating
instead of silently resetting to defaults.

- Toggles, colors, counts, OpenBox token/URL, GitBox repo paths/scan depth all
  decode exactly as before when present in `settings.json`.
- Keys missing from `settings.json` (older schema) fall back to their existing
  defaults.
- `serverURL` (the only optional field, OpenBoxSettings) stays `nil` when
  missing or `null` in the file — remote mode auto-switch behavior unchanged.

## Data source

None — this is a pure Codable behavior fix in
`native/Shared/DeckSettings.swift`. The single decode entry point
(`DeckSettings.load()`, used by DeckApp, DeckAgent and all five widgets) is
shared, so one fix covers every consumer.

## Shell fit

- Touches only `native/Shared/DeckSettings.swift` (all consumer call sites
  unchanged).
- **Approach (empirically corrected): explicit `init(from:)` per struct** — the
  LiveBoxSettings pattern from PR #7, ported to the five structs. The
  originally proposed `@Default` property-wrapper approach was disproven by a
  compile-and-run probe: synthesized outer `Codable` throws `keyNotFound`
  before the wrapper's `init(from:)` is consulted, so wrappers cannot make
  missing keys decode tolerantly. Each struct gets `init() {}` + an
  `init(from:)` that decodes every key with `decodeIfPresent` and the existing
  defaults; synthesized `encode(to:)` and `Equatable` remain.
- `LiveBoxSettings` keeps its shipped explicit `init(from:)` — already safe,
  untouched (no risk for zero user benefit; unify later if ever touching that
  struct).
- **TDD**: the decoders are pure Codable logic → developed in a scratch SwiftPM
  package (`Sources/SettingsCore` + `Tests/SettingsCoreTests`, `swift test`),
  the DevBox/LiveBox precedent, then ported into `DeckSettings.swift` and the
  scratch package removed pre-merge. Scratch tests use mirror structs carrying
  the same field set; fixture JSON covers missing-key, full, and null cases.

## Non-goals

- No changes to `load()`'s behavior on a truly corrupt file (unreadable JSON
  still falls back to defaults — the M4 crash/robustness pass may log there
  later; ROADMAP.md:51).
- No migration of on-disk JSON (old files are never rewritten; they just decode
  tolerantly).
- No unification of `LiveBoxSettings`' explicit init with the wrappers.
- No changes to save path, container, or any widget/agent data path.

## Decisions (resolved in interview + empirical probe)

- Explicit `init(from:)` per struct (LiveBoxSettings precedent) — the
  property-wrapper alternative was disproven by a probe: synthesized outer
  Codable throws `keyNotFound` before a wrapper's `init(from:)` is consulted.
- Missing key → default; present key → exact value; type mismatch → still
  throws (unchanged semantics).

## Open questions

- None — fixture verification: the user's real `settings.json` (container
  path) is used locally as a regression fixture without being committed (it
  contains the OpenBox token).
