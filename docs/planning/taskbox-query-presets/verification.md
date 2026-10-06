# Verification — taskbox-query-presets (2026-10-07)

Everything below was observed, except where marked **not observed**. The
installed copy at `/Applications/Deck.app` was this branch's Release build
(v1.47 + the feature), driven through the accessibility tree (`System Events`)
and by running `DeckAgent` directly with Deck quit.

## Test suite

- `DeckSharedTests`: **1399 tests, 0 failures** (baseline 1370; +14 `WiqlPreset`,
  +5 `AzureSprintRoute`, +4 `WiqlResponse` 500-shape, +2 `TaskBoxSettings.team`
  decode, +4 `AzureTeamsParser`).
- Release build of `DeckApp` (all three targets) succeeds.

## Settings UI (accessibility observations)

- Account row: `ForesightAnalytics · ForesightAnalytics / ForesightManifold`.
- The query draft loads the stored condition.
- **Presets menu** exposes exactly *Assigned to me | Created by me | Current
  sprint*. Choosing "Created by me" replaced the draft with
  `[System.CreatedBy] = @Me AND [System.State] NOT IN ('Closed', 'Removed', 'Done')`
  and **`settings.json` still held the old query** — a preset never applies.
- **Team picker** (account has one project) lists *Default team |
  ForesightManifold Team* — the live `_apis/projects/ForesightManifold/teams`
  call populated it. Selecting the team persisted it to
  `settings.taskbox.team`, and the refresh it triggers wrote a snapshot with
  **`sprint: "Sprint 63"`**, `fetch-taskbox.json`: `ok` (the team route).
- "Current sprint" with that team produced the literal
  `[System.IterationPath] = @CurrentIteration('[ForesightManifold]\ForesightManifold Team') AND [System.State] NOT IN ('Closed', 'Removed', 'Done')`;
  **Apply** wrote it to `settings.json`, the host refresh fetched `ok`, and the
  snapshot came back `totalCount: 24`, `isCustomQuery: true`, `sprint: "Sprint 63"`.

## Agent path (Deck quit, `DeckAgent` run directly)

- Bogus literal `@CurrentIteration('[ForesightManifold]\No Such Team')`:
  `fetch-taskbox.json` → **`queryRejected`** (the new 500 classification), and
  `taskbox.json` **mtime unchanged** (02:31:57) — the last good snapshot stood.
- `[System.Id] > 0`: snapshot `totalCount: 200`, `totalIsLowerBound: true`,
  fetch `ok` — the cap still applies to broad custom conditions.
- Settings were restored afterwards: query = the built-in condition, team = "".

## Not observed

- **The Test button's live message for the 500 shape.** The same server path was
  observed (the agent tick recorded `queryRejected`), and
  `WiqlResponseTests`/`WiqlTestSummaryTests` pin the message display, but the
  button itself was not clicked against a real 500: the settings window sits on
  another Space and kept invalidating its accessibility handle mid-script.
- **The Team row disappearing with two projects.** The gate is unit-pinned
  (`AzureSprintRoute.team(targetCount:)`) and the view applies the same
  `projects.count == 1` condition; changing the user's live account config just
  for the check was not done.
- **Re-adding TaskBox from the gallery.** No extension source, widget file or
  snapshot shape changed (the feature is settings + a host-side URL), so the
  descriptor cache and gallery are not in play; the check was skipped rather
  than inferred.
