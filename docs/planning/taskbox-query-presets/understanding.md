# Understanding — taskbox-query-presets (2026-10-07)

Inputs: `issue.md`, `../taskbox-query-presets/probe.md`, the
`taskbox-custom-wiql` PRD/plan, and the code below.

## What the work really asks

Two recorded follow-ups from custom WIQL (ROADMAP.md:939-941), sharing the
Query settings section:

1. **Presets** — quick conditions (`assigned / created / current sprint`) for the
   existing WHERE-condition field, which today is free text plus "Start from
   default".
2. **Team context for `@CurrentIteration`** — a team segment so the macro does
   not always resolve against each project's default team (probe P7).

## Current state, by file

- **Query UI** — `DeckApp.swift:2343-2392`. A `TextEditor` edits `draft`; only
  **Apply** writes `settings.query` (A1 in the prior PRD: the host's 60s timer
  and the agent must never run a half-typed condition). Validation runs as you
  type; Test runs one WIQL per project, one click at a time; "Start from
  default" replaces the draft with `WiqlClause.builtInCondition`.
- **Pure clause logic** — `WiqlClause.swift` (156 lines): `validate`,
  `query(for:)`, `isCustom`, `builtInCondition`. Composition owns the project
  clause and ORDER BY and wraps the user's text in `( … )`.
- **Loader** — `HostAzureDevOpsLoader.fetch` (`AzureDevOpsLoader.swift:436`)
  composes **one** query string for every project; `test` (`:518`) is the
  host-only one-shot; `currentSprint` (`:606`) hits the project base (default
  team) and the chip is gated on `targets.count == 1` (`:484`).
- **Settings** — `TaskBoxSettings` (`DeckSettings.swift:832-898`): custom
  `init(from:)` with `decodeIfPresent` per field; no hand-written
  `encode(to:)` (auto-synthesized — the CLAUDE.md `ShipBoxSettings` trap does
  not apply here, but adding a field must still decode tolerantly).
- **Widget** — `TaskBoxWidget.swift` reads only `taskCount`, `showLegend`,
  `showProject`, the lane mapping and colours; the query reaches the face only
  as `snapshot.isCustomQuery` wording. **No face change is anticipated.**
- **Tests** — `WiqlClauseTests.swift` (validation + composition, 142 lines),
  `AzureDevOpsParserTests.swift`, `DecodeTests.swift`.

## What the probe changed

- A team literal (`'[Project]\Team'`, name not id, brackets required) is valid
  only in its own project; in another project it is **200 with 0 ids** (P20).
  So a single team literal cannot serve a multi-project account honestly.
- A bad/malformed literal is a **500 with a readable message**, which today
  maps to `.badResponse`, not `.queryRejected` (P18/P19).
- Teams are listable with the current PAT (F1-F3), and the team sprint route
  works (F5).
- In this org the picker changes nothing today: one team per project
  (P16 = P17, F4 = F5).

## Ambiguities to settle in the interview

1. **Team scope and storage.** Recommended: a team picker in TaskBox settings,
   offered only when the account has exactly one project (mirrors the sprint
   chip rule); the "Current sprint" preset emits the literal when a team is
   chosen; the sprint chip follows the Team route. Multi-project accounts keep
   today's default-team behavior; per-project team mapping is a later slice.
2. **Preset model.** Replace the draft with a complete condition (like "Start
   from default"), or append a fragment joined by `AND`? Which conditions, and
   do they carry the open-state exclusion?
3. **The 500.** Map WIQL 500-with-a-message to `queryRejected` (with a guard
   for 502/503/504 outages), or surface the message only in Test?
4. **Multi-project limitation wording** — a recorded non-goal: a team literal in
   a multi-project account silently returns 0 elsewhere. Test prints its 0, but
   the face shows "No matches".

## Shell invariants (pre-check)

- The extension must not read the new field; the face keeps reading the
  snapshot. `query` stays where it is (the CLAUDE.md "extension reads
  settings" trap).
- `TaskBoxSettings` needs `decodeIfPresent` for the new field; no hand-written
  encode to miss.
- New source/test files need `xcodegen generate` or they silently do not
  compile.
- No new snapshot file, no new sampler; the agent path is untouched unless the
  chip route changes (one URL).
