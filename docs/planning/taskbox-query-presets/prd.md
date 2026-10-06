# PRD — TaskBox: query presets and team context

Status: draft for review, 2026-10-07. Inputs: `issue.md`,
`understanding.md`, `probe.md` (live org, teams + `@CurrentIteration`).

## 1. Ask

Make TaskBox's custom WIQL practical to use: a **presets menu** for the Query
field (assigned / created / current sprint), and a **team context** so
`@CurrentIteration` can resolve against a chosen team instead of each project's
default team (`taskbox-custom-wiql/prd.md` Q4 and §7 non-goals; ROADMAP.md:939).

## 2. Decisions (interview 2026-10-07, all recommendations accepted)

| # | Question | Decision |
|---|---|---|
| Q1 | Team-context scope | **Single-project team picker.** Offered only when the account has exactly one project — the same gate the sprint chip uses (`AzureDevOpsLoader.swift:484`). Multi-project accounts keep today's default-team behavior; per-project team mapping is a recorded follow-up |
| Q2 | Preset behavior | **Complete conditions that replace the draft** (like today's "Start from default"), each carrying the open-state exclusion. Still never applied — Apply stays the only writer |
| Q3 | Bad-team 500 | **Classify 500-with-a-message as `queryRejected`** along with 400; a 500 without a message and 502/503/504 keep the classifier's existing `.unreachable` ("Can't reach Azure DevOps") so an outage is never blamed on the query |

## 3. User-visible spec

### Settings → TaskBox tab → Query section

- **Presets menu** — a `Menu("Presets")` in the button row, three items, each
  **replacing the draft** (not applying it; the existing
  `.onChange(of: draft) { testLine = nil }` clears a stale Test line):
  - **Assigned to me** — byte-identical to `WiqlClause.builtInCondition`:
    `[System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed', 'Removed', 'Done')`.
    Pinned by a unit test so the two can never drift.
  - **Created by me** — `[System.CreatedBy] = @Me AND [System.State] NOT IN ('Closed', 'Removed', 'Done')`.
  - **Current sprint** — `[System.IterationPath] = @CurrentIteration` +
    the open-state exclusion; with a team chosen, the macro carries the
    literal: `@CurrentIteration('[ForesightManifold]\ForesightManifold Team')`
    (name, not id; brackets required — probe P17/P19).
  - **"Start from default" folds into the menu** (its job is "Assigned to
    me"); one control, not two ways to paste the same text. Clearing the field
    and pressing Apply is unchanged as the way back to the built-in filter.
- **Team row** — a `Picker("Team")` under the Query field, shown **only when
  the selected account resolves to exactly one project**:
  - Entries: "Default team" (empty string — today's behavior) + the project's
    teams, loaded host-side on appear and on account change
    (`_apis/projects/{project}/teams`, probe F1-F3; one call, never on the
    agent tick, never per keystroke).
  - If the listing fails, the stored team stays selectable and a caption names
    the failure; the control must not silently drop the stored value.
  - The picker writes `TaskBoxSettings.team` immediately (like other pickers)
    and triggers one host refresh via the existing `onApply`.
  - Multi-project account → the row is hidden; a stored team is kept but has
    no effect (the chip and the preset are both gated).
- **Captions** — one line when a team is set: the current-sprint preset names
  this project and team, so changing the account's project afterwards leaves
  the applied text naming the old project (a stale literal silently matches 0
  — probe P20; Test prints its 0).

### Front face

Unchanged layout and wording. The sprint chip now follows the picked team
(same current iteration endpoint, one team segment in the URL, probe F5) and
keeps its existing exactly-one-project gate.

## 4. Data path

- **Presets** — no data path. Pure text into the existing draft; the agent,
  snapshot and extension are untouched.
- **Team** — `TaskBoxSettings.team: String = ""`.

  ```swift
  // HostAzureDevOpsLoader.fetch gains a parameter, defaulted for the agent's call sites
  static func fetch(organization:projects:token:condition:team: = "")
  ```

  The team is used in exactly one place: `currentSprint` builds
  `{projectBase}/{percent-encoded team}/_apis/work/teamsettings/iterations?$timeframe=current`
  when the team is non-empty **and** `targets.count == 1`; otherwise today's
  URL. Same one request. The WIQL call is not rewritten — the team segment
  reaches WIQL only through the preset text the user applied (WYSIWYG).
- **Teams listing** — `HostAzureTeamsLoader.list(organization:token:project:)`
  beside `HostAzureProjectsLoader` (`AzureDevOpsLoader.swift:687`), same shape:
  host-app only, one busy-window call.
- **No snapshot change.** No new `FetchOutcome`. The extension reads nothing
  new (`TaskBoxWidget` keeps reading count/legend/colours; the query reaches
  the face only as `isCustomQuery`).

### 4.1 Pure API (new `native/Shared/WiqlPreset.swift`)

```swift
enum WiqlPreset: CaseIterable {
    case assignedToMe, createdByMe, currentSprint
    var title: String
    /// `team` is nil unless a single-project account has a team chosen.
    func condition(team: WiqlTeamContext?) -> String
}

struct WiqlTeamContext: Equatable {
    var project: String
    var team: String
    /// `'[Project]\Team'` with `'` escaped as `''` inside the literal.
    var literal: String
}
```

Every preset must pass `WiqlClause.validate` and compose through
`WiqlClause.query(for:)` unchanged — unit-pinned.

## 5. Failure behaviour

- **500 from WIQL** — `WiqlResponse.interpret` maps `400`, and `500` carrying
  a parseable `message`, to `.queryRejected(message)`; a 500 without a message
  and all of 502/503/504 stay `serverError` → the classifier's existing
  `.unreachable` ("Can't reach Azure DevOps"). Fixtures: the
  probe's P18 (`VS402612: …`) and P19 (`… is not of the form '[project]\team'`)
  bodies. Both `Test` (message verbatim) and the face chip ("Check the query")
  inherit this through the existing paths.
- **Teams listing fails** — the picker keeps the stored value, shows the
  failure in a caption; Apply/Test remain usable.
- **Stale literal** — a project/team renamed after Apply is a valid WIQL
  literal that matches nothing (P20) or a 500 (P18 if the format breaks): Test
  prints 0 / the message; the chip says "Check the query". No auto-rewrite of
  user text.
- **Multi-project account** — hidden team row, unchanged fetch, unchanged chip
  gate.

## 6. Shell fit

- `WiqlPreset.swift` is new → `xcodegen generate` before the tests count.
- `TaskBoxSettings` gains `team`, decoded with `decodeIfPresent` in its custom
  `init(from:)`; `encode(to:)` is synthesized (checked — unlike
  `ShipBoxSettings`, this struct has no hand-written encoder to extend).
- The extension must not read `team`; the CLAUDE.md "extension reads settings"
  trap does not apply because nothing moves.
- `fetch`'s new parameter is threaded at both call sites (`DeckAgent/main.swift:232`,
  `DeckApp.swift:430`) from settings.
- The Team row's gate must match the fetch gate (`targets.count == 1`, i.e. the
  resolved credential's projects — not the legacy `organization`/`project`
  fields, which stay fallback-only).

## 7. Non-goals

- **Per-project team mapping** (the honest way to support teams across
  multiple projects; probe P20 is why one literal cannot).
- `@TeamAreas` — not probed, no consumer.
- Macro substitution or condition rewriting at fetch time; the user's text is
  what runs.
- Validating the applied literal against the live team list per tick.
- Presets applying themselves; syntax highlighting/autocomplete (prior PRD
  non-goals stand).

## 8. Verification

- **Unit** (`DeckSharedTests`): every `WiqlPreset` validates and composes with
  the project clause outside; "Assigned to me" == `WiqlClause.builtInCondition`;
  literal builder escaping (space, `''`); `WiqlPreset` titles covered;
  `WiqlResponse` 400/500-with-message/500-without/502 fixtures; teams parser
  (sorted, empty, malformed); `TaskBoxSettings` tolerant decode of `team`.
- **Live** (Deck quit; drive `DeckAgent` directly): with a team set on the
  single-project account, the chip still reads `Sprint 63` (probe F5); Test
  with the current-sprint preset shows 30; a bogus literal shows the VS402612
  message; `[System.Id] > 0` still comes back capped; snapshot mtime unchanged
  after a rejected Test.
- **Settings**: presets replace the draft and never apply; Team row appears
  only for the single-project account; switching the account changes the row.
- **Build + install**, re-add TaskBox from the gallery, all three sizes render.

## 9. Open questions

None blocking.

## 10. Self-critique (2026-10-07)

### 🔴 Red

None. No shell invariant is touched (no face change, no new snapshot, no
extension read), and the data path is the proven one.

### 🟡 Amber, with fixes

1. **A 500 outage can be mislabelled "Check the query".** The Q3 rule reads any
   WIQL 500 that carries a JSON `message` as a rejected query; a genuine Azure
   outage returning that shape would nudge the user to their condition. Fix:
   keep the guard narrow (exactly 500 + parseable message; a message-less 500
   and 502/503/504 keep `.unreachable`), state the residual risk in the code
   comment, and pin the
   three shapes as fixtures. The last good snapshot stands throughout, so the
   blast radius is one chip line.
2. **The applied preset can go stale silently.** It embeds the project and
   team; changing the account's project afterwards leaves a literal that
   matches 0 elsewhere (P20). Fix: the caption in §3 states it; Test prints 0;
   the preset menu always rebuilds from the *current* account when used. No
   auto-rewrite (that would edit the user's text).
3. **Removing "Start from default" is user-visible churn.** It is redundant
   once "Assigned to me" exists in the menu. Fix: keep the menu item text
   identical to the built-in and pin it by test so the promise is exact; the
   empty-field-and-Apply route is unchanged.
4. **Team picker lifecycle.** The teams fetch is a new host-only call; if it
   runs on every keystroke or on the agent tick it recreates the MarketBox
   rate-budget shape. Fix: `.task(id:)` on the resolved account, one call,
   cache in view state; never in `refreshTaskBox`.
5. **`fetch`'s gate must be the resolved targets, not the raw settings.** The
   legacy per-slot fallback can still drive a fetch with no account; the team
   segment must never apply there. Fix: compute the team inside `fetch` after
   `AzureTargets.normalise` (count == 1) and in the view from the resolved
   credential; unit-pin the gate.
