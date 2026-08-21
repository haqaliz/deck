# TaskBox — Phase 2 understanding

## What the work is really asking

A tenth widget, `TaskBox`, in the **agent-pumped** data path (path 2): the
widget sandbox has no network entitlement, so `DeckAgent` fetches Azure DevOps
work items every 60s and writes `taskbox.json` into the container. The widget
renders the snapshot. This is line-for-line the **ShipBox** shape — static
token, host loader, `FetchStatus` error path, settings tab — with two
differences:

1. Azure DevOps needs **two** HTTP calls (WIQL POST → ids, then a batch GET/POST
   for fields), not one.
2. The snapshot must be **provider-agnostic** (`TaskItem` with a `provider`
   field), so PRBox/Jira/Reminders can reuse it later without a migration.

## Affected files (all new unless noted)

| File | Change |
|---|---|
| `native/Shared/TaskBoxSnapshot.swift` | new — `TaskBoxSnapshot`, `TaskItem`, `TaskProvider`, `TaskBoxSnapshotStore`, `HostAzureDevOpsLoader`, `WorkItemParser`, `TaskFormatting` |
| `native/Shared/DeckSettings.swift` | +`var taskbox = TaskBoxSettings()` on `DeckSettings`; new `TaskBoxSettings` with tolerant `init(from:)` |
| `native/Shared/FetchStatus.swift` | +`case taskbox` on `FetchSource`; +arms in `FetchStatusCopy.line`/`.hint`; +arm in `FetchClassifier.outcome(for:)` for the new error type |
| `native/DeckWidgets/TaskBoxWidget.swift` | new — entry, provider, widget, views |
| `native/DeckWidgets/DeckWidgets.swift` | register `TaskBoxWidget()` in the bundle |
| `native/DeckAgent/main.swift` | new fetch block (guarded on org+project+token) |
| `native/DeckApp/DeckApp.swift` | `SettingsTab.taskbox` + `TaskBoxSettingsView` + `refreshTaskBox()` on open/save |
| `native/SharedTests/TaskBoxSnapshotTests.swift` | new — parser, formatting, tolerant decode |
| `README.md`, `ROADMAP.md` | register the widget; tick the M5 line |

`native/project.yml` needs **no** change (targets enumerate whole directories),
but `xcodegen generate` must still be re-run so the new files are compiled —
per CLAUDE.md, a new test file is otherwise silently not built and the suite
still reports success.

## Shell invariants — no conflict

Nothing here touches the panel shell. TaskBox is a WidgetKit widget like the
other nine: `.containerBackground(for: .widget) { Color.clear }`, rounded
system fonts, monospaced digits, colored-dot rows, 60s timeline, section
titles tracked 1pt. Settings live in the Deck app window only.

## Verified facts

- `FetchSource` is `enum … String, Codable, CaseIterable` — adding a case is
  additive and old builds tolerate unknown outcomes (`FetchStatus.init(from:)`
  falls back to `.ok`), but an **old build reading a new `source` string will
  fail to decode the whole `FetchStatus`** → renders no chip. Acceptable
  (matches the existing degradation), worth stating.
- `DeckSharedTests` target exists (`native/SharedTests`) with an established
  fixture-string idiom (`ShipBoxSnapshotTests.swift`). TDD lands here.
- Dev machine `az devops` defaults: org `https://dev.azure.com/Manifold`,
  project `Manifold`.

## ⚠️ Feasibility caveat (verified, unresolved)

**The Azure DevOps API could not be exercised from this machine.** `az boards
query` returns `TF400813: The user 'aaaaaaaa-…' is not authorized`, and the
`AZURE_TOKEN` in the environment is rejected with **HTTP 401** by
`POST /Manifold/Manifold/_apis/wit/wiql?api-version=7.1` under both Basic
(`:$TOKEN`) and Bearer. So the response shape below is from the documented
API contract, **not** from a live payload on this org.

Consequences to carry into the PRD:
1. The parser must be written defensively (every field optional, tolerant of
   missing `fields` entries) and covered by fixture tests, exactly as
   `RunParser` is.
2. **Slice 1 must ship a way to prove the fetch works** — the settings-tab
   `FetchStatusCaption` already does this (it names 401/403/404 as "check
   org/project/PAT"), so the first real PAT the user pastes is the live test.
3. A one-off `curl` verification with a real PAT should happen before the
   parser is finalised, to confirm which scheduling fields this org populates.

## Ambiguities → interview questions

- **"Due/overdue" has no universal Azure DevOps field.** `Microsoft.VSTS.
  Scheduling.DueDate` exists only on some work item types/processes and is
  frequently empty; `TargetDate` and the iteration path's end date are the
  alternatives. The ROADMAP headline ("due/overdue counts") may not be
  renderable against this org's data. **Blocking design question.**
- Which items: `AssignedTo = @Me` and which state exclusions (`Closed`,
  `Removed`, `Done`?); scoped to one project or the whole org?
- List ordering: due date, priority, or changed date.
- PAT storage: settings.json plaintext (ShipBox precedent) vs Keychain.
