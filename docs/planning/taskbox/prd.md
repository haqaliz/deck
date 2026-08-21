# TaskBox — PRD

**Slug:** `taskbox` · **Branch:** `feat/taskbox/aliz` · **Type:** feat
**Date:** 2026-08-22 · **Milestone:** M5 (widget slate)
**Brief:** `docs/planning/_card/issue.md` · **Dig:** `docs/planning/_card/understanding.md`

---

## 1. The ask, in one sentence

A tenth Deck widget that answers *"what's on my plate and what's late"* at a
glance, reading work items assigned to me from **Azure DevOps** through the
agent-pumped snapshot path, on a data model deliberately shaped so a second
provider drops in later without a migration.

## 2. User-visible spec

### Front face

Three regions, in the LiveBox/ShipBox visual language (rounded system fonts,
monospaced digits, colored-dot rows, section titles tracked 1pt).

**Header line** — scope on the left, urgency on the right:

```
Manifold / Manifold          3 overdue · 7 due ≤7d
```

- Left: `snapshot.scope` — `"{project}"`, or `"{org} / {project}"` when they
  differ. Read from the **snapshot**, not from settings: the header names what
  the data *is*, not what it *will be* after the next tick. (`ShipBox` does the
  same with `snapshot.repo`.) Truncates `.middle`, `lineLimit(1)`.
- Right: `TaskFormatting.countsLine` — `"3 overdue · 7 due ≤7d"`, where the
  window is interpolated from `soonWindowDays` (**not** a hardcoded 7).
  Parts are skipped when zero, so a clear plate reads just `"12 open"`. All-zero and
  no tasks → the empty state below instead.
- Then the fetch chip (`FetchChip.text`, `.tertiary`, 10pt) and, past 5
  minutes, `· HH:mm` — identical to ShipBox's `headerLine`. On
  `.systemSmall`, the chip wins and the counts line is dropped (ShipBox
  precedent: a small face has room for one hint, not two).

**Totals row** (`.systemLarge` only, below a `Divider`) — the ShipBox
`totalsRow` shape, one dot per bucket:

```
● OVERDUE 3   ● TODAY 1   ● SOON 4   ● LATER 6
```

**Task list** — section title `TASKS`, then up to `taskCount` rows:

```
● Fix export filter                          -2d
● Device Health align                        -1d
● Loss Reports slow                        today
● Auth0 role mapping                         +3d
● Migration rollback                          +5d
● Spike: BlueBox sensors                        —
```

- Dot color = due bucket (see §4).
- Title: `System.Title`, 11pt medium, `lineLimit(1)`, `.tail`.
- Trailing: relative day, monospaced digits, 11pt semibold. `.primary` when
  overdue or today, `.secondary` otherwise (ShipBox uses the same
  emphasis-on-bad rule for failures).
- Undated rows show `—`.

**Per family**

| Family | Header | Totals row | Rows |
|---|---|---|---|
| `.systemSmall` | yes (chip wins over counts) | no | 2 |
| `.systemMedium` | yes | no | `taskCount` (default 5) |
| `.systemLarge` | yes | yes | `taskCount` |

**Empty / unavailable states** — three distinct faces, never one generic blank:

| Condition | Face |
|---|---|
| No snapshot file at all | `TaskBox` / **No task data** / chip, else *"Add org, project + PAT in Deck settings."* |
| Snapshot exists, `tasks` empty | header + **"Nothing assigned"** |
| Snapshot exists, tasks present, all undated | normal face; counts line reads `"12 open"`; every row shows `—` |

The third row is the honest answer to the §9 risk: if this org never populates
a date, TaskBox is still a useful assigned-work list and says so by showing
`—` rather than fabricating urgency.

### Back face (settings tab — Deck app window only)

`SettingsTab.taskbox`, SF Symbol `checklist`, placed after `.shipbox`.

| Section | Control | Default |
|---|---|---|
| **Azure DevOps** | `TextField` "Organization" | `""` |
| | `TextField` "Project" | `""` |
| | `SecureField` "Personal access token" (`.textContentType(.password)`) | `""` |
| | caption: *"Empty org, project or token = the widget shows no data. The token is sent only to dev.azure.com over TLS. A read-only **Work Items (Read)** PAT is enough."* | — |
| | `FetchStatusCaption(source: .taskbox, clearOn: org␀project␀token)` | — |
| **Tasks** | `Toggle` "Show task list" | `true` |
| | `Stepper` "Task count: N" (2…8, disabled when list off) | `5` |
| | `Stepper` "Due soon window: N days" (1…30) | `7` |
| **Due colors** | `ColorPicker` Overdue | `.red` |
| | `ColorPicker` Today | `.orange` |
| | `ColorPicker` Soon | `.yellow` |
| | `ColorPicker` Later | `.green` |

Undated deliberately has **no** picker — it renders `.secondary`, exactly as
ShipBox's `.neutral` status does. Four pickers, matching ShipBox.

Saving the tab (and opening the window) triggers `refreshTaskBox()` so the
user sees the result of a pasted PAT immediately rather than waiting 60s —
the existing `refreshShipBox()` pattern at `DeckApp.swift:169`.

## 3. Data source

**Provider:** Azure DevOps Work Items REST API, `api-version=7.1`.
**Auth:** PAT over HTTP Basic, `Authorization: Basic base64(":" + PAT)`.
No OAuth, no Entra ID, no device flow — the same static-token shape as ShipBox.
**Cadence:** 60s, in `DeckAgent`'s full refresh, alongside the ShipBox block.
**Path:** agent-pumped (path 2) — the widget sandbox has no network
entitlement. Snapshot at
`…/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck/taskbox.json`.

### Three calls per tick

**1 — WIQL (ids).** `POST /{org}/{project}/_apis/wit/wiql?api-version=7.1`

```json
{"query":"SELECT [System.Id] FROM WorkItems WHERE [System.AssignedTo] = @Me AND [System.State] NOT IN ('Closed','Removed','Done') ORDER BY [System.ChangedDate] DESC"}
```

→ `{"workItems":[{"id":123,"url":"…"}, …]}`. The query is **fixed in code**,
not user-editable (see §6). Ids are capped at **50** before the batch call.

**2 — Batch (fields).** `POST /{org}/_apis/wit/workitemsbatch?api-version=7.1`

```json
{"ids":[123,124],
 "fields":["System.Id","System.Title","System.State","System.WorkItemType","System.IterationPath","System.ChangedDate","Microsoft.VSTS.Scheduling.DueDate","Microsoft.VSTS.Scheduling.TargetDate"],
 "errorPolicy":"omit"}
```

→ `{"count":2,"value":[{"id":123,"fields":{…}}, …]}`. The endpoint caps at 200
ids; our 50 is comfortably under, so no paging in slice 1.

`"errorPolicy":"omit"` is **required, not optional**: without it the batch fails
wholesale if a single id is inaccessible or was deleted between call 1 and call
2 — a real race at a 60s cadence. With it, the missing id is skipped and every
other task still renders.

**3 — Iterations (best-effort).**
`GET /{org}/{project}/_apis/work/teamsettings/iterations?api-version=7.1`
→ `{"value":[{"path":"Manifold\\Sprint 42","attributes":{"startDate":…,"finishDate":…}}]}`

Builds a `[iterationPath: finishDate]` map for the due-date fallback, using the
project's **default team**. **This call is allowed to fail without failing the
tick**: on error the map is empty, items fall back to undated, and the snapshot
is still written with `.ok`. A missing sprint calendar must never blank a
working task list.

### Empty / failure behaviour

- Org, project **or** token empty → agent skips all three calls and records
  `FetchStatusStore.record(.notConfigured, for: .taskbox)`. Recorded, not just
  logged — "you haven't set this up" is the most fixable state there is.
- Call 1 or 2 fails → `FetchClassifier.outcome(for:)` records the reason and
  **the last-good `taskbox.json` is left untouched**. Data is never blanked for
  a failed refresh; the chip carries the honesty. (This is why `FetchStatus`
  lives in its own file per source.)
- WIQL returns zero ids → a snapshot **is** written with `tasks: []` and `.ok`.
  "Nothing assigned" is a real answer, not a failure.

### Write policy: always write

`DeckAgent` has two idioms — skip-if-unchanged (GitBox, DevBox) and
always-write (ShipBox, HomeBox, ClipBox). TaskBox takes **always-write**, and
carries the same comment: `writtenAt` drives the face's 5-minute staleness
window, so a successful fetch must refresh it even when the task list is
unchanged. Skipping would make a perfectly healthy widget claim to be stale on
a quiet day.

## 4. Data model (provider-agnostic by construction)

```swift
enum TaskProvider: String, Codable { case azureDevOps }

enum DueSource: String, Codable {
    case explicit    // Microsoft.VSTS.Scheduling.DueDate
    case target      // Microsoft.VSTS.Scheduling.TargetDate
    case iteration   // iteration path's finishDate
    case none
}

struct TaskItem: Codable, Equatable {
    var id: String              // String, so Jira "PROJ-1" fits without a change
    var title: String
    var state: String           // raw provider state: "Active", "New", "Resolved"
    var itemType: String        // "Bug", "Task", "User Story"
    var url: String             // human URL, built by us (see below)
    var provider: TaskProvider
    var dueDate: Date?
    var dueSource: DueSource
    var changedAt: Date?
}

struct TaskBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    var scope: String           // "Manifold / Manifold" — header text
    var tasks: [TaskItem]       // pre-sorted by TaskFormatting.sorted
}
```

- `id: String` and `provider` are the whole point: GitHub Issues, Jira, Linear
  and Reminders all fit this shape, so PRBox and friends extend the enum rather
  than reshaping the store.
- `url` is **built**, not taken from the payload: the batch API's `url` is the
  API endpoint. Human URL is
  `https://dev.azure.com/{org}/{project}/_workitems/edit/{id}`.
- `state` stays a raw provider string rather than a normalised enum — Azure
  DevOps process templates rename states freely, and slice 1 does not branch on
  state beyond the WIQL exclusion list.

### Due-date resolution (pure, tested)

```
dueDate = DueDate ?? TargetDate ?? iterationFinishDate[IterationPath] ?? nil
dueSource records which one won
```

### Buckets

```swift
enum DueBucket { case overdue, today, soon, later, undated }
```

Computed against `Calendar.current.startOfDay`, so "overdue" means *a day has
passed*, not *24 hours*:

| Bucket | Rule | Color |
|---|---|---|
| `overdue` | `startOfDay(due) < startOfDay(now)` | `overdueColor` (.red) |
| `today` | same day | `todayColor` (.orange) |
| `soon` | within `soonWindowDays` after today | `soonColor` (.yellow) |
| `later` | beyond the window | `laterColor` (.green) |
| `undated` | `dueDate == nil` | `.secondary` |

### Sort order

`due ascending → undated last → within a tie, `changedAt` descending`.
Deterministic and total, so the list doesn't reshuffle between identical ticks
(which would also defeat the agent's `!=` write-avoidance).

### Formatting

- `relativeDay` → `"-2d"`, `"today"`, `"+3d"`, `"—"` for undated. Day-granular,
  clamped at `±99d` so the column can't blow out the row.
- `countsLine` → `"3 overdue · 7 due ≤7d"`; parts skipped when zero; falls back
  to `"N open"` when every bucket is zero-or-undated.

## 5. Shell fit

**No shell invariant is touched.** TaskBox is a WidgetKit widget like the other
nine: `.containerBackground(for: .widget) { Color.clear }`, 60s
`TimelineReloadPolicy.after`, `[.systemSmall, .systemMedium, .systemLarge]`,
settings in the Deck app window only.

| Reused | How |
|---|---|
| `FetchStatus.swift` | `+case taskbox`, `+` copy arms, `+` classifier arm |
| `FetchChip.text` | header chip, unchanged logic |
| `FetchStatusCaption` | settings-tab caption, unchanged |
| `AtomicFile` / store idiom | `TaskBoxSnapshotStore` mirrors `ShipBoxSnapshotStore` |
| `RGBA` / `ColorPicker` binding | four due-color pickers |
| `DeckAgent` full-refresh block | new guarded block after ShipBox |
| `DeckApp` tab + `refresh…()` | new `SettingsTab` case + `refreshTaskBox()` |

`native/project.yml` needs **no edit** (targets enumerate directories), but
`xcodegen generate` **must** be re-run — per CLAUDE.md a new test file is
otherwise silently uncompiled and the suite still reports success.

### Deliberate deviation to flag

Nothing breaks an invariant, but one thing is new: **three HTTP calls in one
tick**, where every existing agent fetch makes one. The mitigation is the
best-effort third call (§3) and a 10s `timeoutInterval` per request, matching
`HostGitHubLoader`. Worst case the block costs ~30s of a 60s tick; it runs
after ShipBox and before the agent exits, so a slow Azure DevOps delays nothing
but its own snapshot.

## 6. Non-goals

- **No writing.** Read-only: no state changes, no comments, no assignment.
- **No OAuth / Entra ID.** PAT only. (Deferred with CalBox's route 3.)
- **No second provider.** `TaskProvider` has one case in slice 1. The shape is
  the deliverable; the second provider is not.
- **No custom WIQL field.** Considered and rejected: a bad query is a silently
  empty widget, and the error copy can't distinguish "your query matched
  nothing" from "your query is wrong". Revisit once one provider is proven.
- **No multi-org / multi-project.** One org, one project — the same single-target
  shape ShipBox shipped with, and the same deferred follow-up.
- **No deep links.** `url` is stored but no `widgetURL`/`Link` is added; no Deck
  widget links out today (verified), and doing it here would make TaskBox the
  odd one out. Cheap follow-up, out of slice 1.
- **`itemType` and `url` are stored, not rendered.** Both are captured in
  `TaskItem` because they are free at parse time and are the obvious next
  iteration (a Bug/Task glyph; a click-through). Neither appears on any face in
  slice 1 — recorded here so a reviewer reads it as a decision, not an
  oversight.
- **No Keychain.** PAT lives in `settings.json` beside the GitHub and opencode
  tokens (§10).
- **No paging.** Hard cap of 50 work items.

## 7. Settings schema

```swift
struct TaskBoxSettings: Codable, Equatable {
    var organization = ""       // "Manifold" or a full https://dev.azure.com/... URL
    var project = ""            // "Manifold"
    var token = ""              // PAT — no default is ever sent
    var showList = true
    var taskCount = 5
    var soonWindowDays = 7
    var overdueColor = RGBA(.red)
    var todayColor = RGBA(.orange)
    var soonColor = RGBA(.yellow)
    var laterColor = RGBA(.green)

    init() {}
    init(from decoder: Decoder) throws { /* decodeIfPresent ?? default, per field */ }
}
```

Added as `var taskbox = TaskBoxSettings()` on `DeckSettings`. Tolerant decode
per field, matching every other settings struct, so an older `settings.json`
loads and a newer one doesn't break an older build.

`organization` **and** `project` are both trimmed and percent-encoded
(`.urlPathAllowed`) at fetch time, mirroring `HostGitHubLoader.makeURL`: a full
URL, a trailing slash, or a bare org name all resolve to the same base, and a
project name containing spaces produces a valid URL rather than a malformed one
that would surface as a `.badResponse` chip blaming the server for a client bug.
Either being empty after trimming → `.invalidTarget`.

## 8. Tests (TDD, `native/SharedTests/TaskBoxSnapshotTests.swift`)

Pure logic only — the loader's HTTP is not tested, exactly as `HostGitHubLoader`
isn't; `WorkItemParser` takes `Data` so fixtures cover the contract.

| Suite | Cases |
|---|---|
| `WorkItemParserTests` | full payload; missing `fields`; missing `System.Title` → row dropped; unknown extra fields ignored; malformed JSON → `nil`; empty `value` → `[]`; ISO8601 with and without fractional seconds |
| `WiqlIdParserTests` | ids extracted; empty `workItems` → `[]`; cap at 50 preserves WIQL order |
| `TargetNormalisationTests` | bare org, full URL, trailing slash all resolve to one base; project with a space is percent-encoded; empty org or project → `.invalidTarget` |
| `IterationMapTests` | path → finishDate; missing `attributes`; null `finishDate` skipped; backslash paths preserved verbatim |
| `DueResolutionTests` | DueDate wins; TargetDate when DueDate absent; iteration when both absent; none when all absent; `dueSource` correct in all four |
| `DueBucketTests` | overdue/today/soon/later/undated at boundaries; **day-granular** (23:59 yesterday is overdue, 00:01 today is today); `soonWindowDays` honoured at N and N+1 |
| `TaskSortTests` | due asc; undated last; tie broken by `changedAt` desc; sort is total and stable across two identical inputs |
| `TaskFormattingTests` | `relativeDay` for -2/-1/0/+1/+3; `—` for undated; ±99d clamp; `countsLine` skipping zero parts; `"N open"` all-undated fallback; **window interpolated at a non-default `soonWindowDays`** |
| `TaskBoxDecodeTests` | tolerant `TaskBoxSettings` decode from `{}`, from partial JSON, from a future field; unknown `DueSource`/`TaskProvider` string → safe default |
| `FetchStatusTests` (extend) | `.taskbox` copy exists for every non-`ok` outcome; `line` and `hint` speak together; **203 → `.authOrTarget`** (§9 C2) |

All tests inject `now` and `Calendar`; none read the clock.

## 9. Risks

### 🔴 R1 — The API is unverified on this machine

`az boards query` returns `TF400813: not authorized`, and the environment's
`AZURE_TOKEN` is rejected **401** by the WIQL endpoint under both Basic and
Bearer. Every payload shape in §3 comes from the documented contract, **not**
from a live response on org `Manifold`.

**Mitigation, in order:**
1. Parsers are written defensively — every field optional, missing entries
   skipped, malformed JSON → `nil` — and fixture-tested (§8).
2. **Before the parser is finalised**, run one `curl` against all three
   endpoints with a real PAT to discover the actual shape. This is a named step
   in the plan, not a hope.
   **The response is read and discarded — it is never committed.** It contains
   real work-item titles, iteration paths and the PAT owner's display name from
   the user's employer's org, and nothing resembling that exists in
   `SharedTests/Fixtures` today. Every committed fixture is **synthetic**,
   hand-written to the shape the curl revealed. Same rule for the widget
   placeholder (§2): obviously-fake titles, since the placeholder is what the
   gallery preview shows on screen.
3. The settings-tab `FetchStatusCaption` makes the first pasted PAT the live
   test, and names the failure precisely.

### 🔴 R2 — This org may not populate any date field

If `DueDate`, `TargetDate` and the iteration calendar are all empty, the
headline feature ("due/overdue counts") renders nothing.

**Mitigation:** designed for, not discovered later. The all-undated face (§2) is
a first-class state: counts collapse to `"N open"`, rows show `—`, and TaskBox
degrades into a useful assigned-work list. Step 2 of R1 also answers this
before any face code is written.

### 🟡 C1 — `@Me` resolves to the PAT's owner

Not to `az`'s logged-in identity. Correct, and worth one line in the settings
caption so a shared/service PAT doesn't surprise anyone.

### 🟡 C2 — Azure DevOps answers a bad PAT with **203**, not 401

A well-known ADO behaviour: an invalid or expired PAT can return
`203 Non-Authoritative Information` with an HTML sign-in page.
`FetchClassifier.outcome(forStatusCode:)` maps 203 to `.badResponse`
("Unexpected response") — which would tell the user the wrong thing.
**Fix:** `AzureDevOpsError` maps a non-200 2xx explicitly to `.authOrTarget`
before delegating to the shared classifier. Covered by a test.

### 🟡 C3 — `FetchSource` gains a case

`FetchStatus.init(from:)` tolerates an unknown *outcome*, but an old build
reading `"source":"taskbox"` fails to decode the whole `FetchStatus` and
renders no chip. Degradation is silent and already the shape of the existing
behaviour — accepted, recorded here rather than discovered.

### 🟡 C4 — State exclusion list is template-specific

`'Closed','Removed','Done'` covers Agile/Scrum/Basic, but a custom process
could use e.g. `'Completed'`. Slice 1 hardcodes the list; a wrong-template user
sees closed items in the list rather than an error. Acceptable for one org;
the fix is the deferred custom-WIQL non-goal.

### 🟡 C5 — Three calls per tick

Addressed in §5. The third is best-effort; each has a 10s timeout.

## 10. Security

- The PAT lives in `settings.json` inside the widget container, plaintext,
  **exactly like the ShipBox GitHub token and the OpenBox token**. Consistent
  with every secret the repo already stores; no new mechanism, no new failure
  mode. Keychain was considered and deferred as a repo-wide change, not a
  TaskBox one.
- No default token is ever sent. Empty token → the fetch does not happen.
- The PAT is sent only to `dev.azure.com` over TLS.
- `DeckAgent` logging stays URL-, token- and name-free: one line per snapshot,
  `written / skipped / failed (<outcome>)`, matching the existing blocks.
- A read-only **Work Items (Read)** scope is sufficient; the settings caption
  says so, so nobody pastes a full-access PAT.

## 11. Definition of done

1. `xcodegen generate` re-run; `xcodebuild … -scheme DeckApp -configuration Release` succeeds.
2. `DeckSharedTests` green, and the new test file is **verified compiled** (not
   just "the suite passed").
3. Payload shape confirmed with a live PAT; **synthetic** fixtures written to
   that shape and committed. No real work-item data in the repo (R1 step 2).
4. TaskBox appears in the Widget Center and renders at S / M / L.
5. All three empty states reachable and correct (no snapshot / no tasks / all undated).
6. Settings tab persists; pasting a PAT refreshes without waiting 60s.
7. The other nine widgets re-added from the gallery and verified unregressed.
8. `README.md` and `ROADMAP.md` updated; M5 TaskBox line ticked.

## 12. Open questions

None blocking. Settled in the Phase 3 interview:

| Question | Decision |
|---|---|
| Due-date semantics | `DueDate` → `TargetDate` → iteration end → undated |
| Scope | Assigned to me, open, one project |
| PAT storage | `settings.json`, ShipBox precedent |
| Slice size | Full widget, Azure DevOps only |
