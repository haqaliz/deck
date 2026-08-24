# PRBox — Phase 2 understanding

## What the work is really asking

A thirteenth widget, **PRBox**, showing a review queue mixed from **two
providers** in one list:

- **GitHub** — PRs you authored (open) + PRs where your review is requested.
- **Azure DevOps Git** — the same two questions against `dev.azure.com`.

Settings: the PRBox tab holds **one sub-tab per provider**; each sub-tab has its
own include/exclude toggle plus that provider's credentials and scope. The face
renders the union.

## The shell fits without modification

Both providers are network fetches, so PRBox is squarely on the **agent-pumped
path** already used by ShipBox/TaskBox/WeatherBox: `DeckAgent` fetches every
60s → `prbox.json` in the container → the widget renders the snapshot. No
sandbox question, no new entitlement, no shell invariant touched.

## Precedent to copy (not invent)

| Need | Existing code |
|---|---|
| GitHub HTTP + typed errors | `HostGitHubLoader` / `GitHubError` — `Shared/ShipBoxSnapshot.swift:71` |
| Azure DevOps HTTP, Basic auth, target normalising, date parsing | `HostAzureDevOpsLoader`, `AzureTarget`, `AzureDate` — `Shared/AzureDevOpsLoader.swift:13,25,205` |
| Error → user-facing reason | `FetchClassifier.outcome(for:)` already handles **both** `GitHubError` and `AzureDevOpsError` — `Shared/FetchStatus.swift:81,99` |
| Multi-provider snapshot model | `TaskItem.provider` / `TaskProvider` with tolerant decode — `Shared/TaskBoxSnapshot.swift:19` |
| Settings caption that names the failure | `FetchStatusCaption(source:clearOn:)` — `DeckApp/DeckApp.swift:~930` |
| Agent fetch block shape | `DeckAgent/main.swift:131` (ShipBox) and `:157` (TaskBox) |

`TaskBoxSnapshot`'s comment ("`provider` names the source, so GitHub Issues /
Linear / Reminders extend the enum rather than migrating the store") is the
design PRBox needs from day one, with two providers instead of one.

## Affected files (all append-only except the two enums)

- New: `Shared/PRBoxSnapshot.swift`, `DeckWidgets/PRBoxWidget.swift`.
- New: an Azure DevOps PR loader — either in the new file or appended to
  `Shared/AzureDevOpsLoader.swift`.
- `Shared/FetchStatus.swift` — **enum change**: `FetchSource` gains cases.
  Also `reason`/`hint` switches (`:156`, `:165`, `:192`, `:204`, `:212`) are
  exhaustive over `FetchSource`, so each new case needs its four strings.
- `Shared/DeckSettings.swift` — `PRBoxSettings` + registration + tolerant decode.
- `DeckApp/DeckApp.swift` — `DeckWidget` enum case, sidebar entry, detail
  switch, settings view, `refreshPRBox()` in both `onAppear` and the 60s timer.
- `DeckAgent/main.swift` — fetch block.
- `DeckWidgets/DeckWidgets.swift` — bundle registration.
- `native/project.yml` — **version bump** (`CFBundleShortVersionString` /
  `CFBundleVersion`), or the Widget Center never enumerates the widget.
- `README.md`, `ROADMAP.md`, `CLAUDE.md` — registration; "twelve" → "thirteen".
- `DeckSharedTests` — parser tests. Remember: xcodegen enumerates files at
  generation time, so a new test file needs `xcodegen generate` or it is
  silently not compiled and the suite still passes.

## Ambiguities / open questions for the interview

1. **Where do the tokens live?** GitHub's PAT is `ShipBoxSettings.token`
   (`DeckSettings.swift:483`), Azure's is `TaskBoxSettings.token` (`:515`).
   Options: (a) PRBox gets its own two token fields (user pastes twice, zero
   coupling); (b) a shared `credentials` section both widgets read (one paste,
   but a schema change plus a migration for existing users' pasted tokens).
2. **`FetchSource` granularity.** Per-provider sub-tabs each want their own
   caption, which argues for **two** cases (`prboxGitHub`, `prboxAzure`) over
   one aggregate — but the union face then needs a rule for "one provider is
   down, the other is fine".
3. **Azure DevOps PR search takes identity GUIDs, not `@Me`.**
   `searchCriteria.creatorId` / `.reviewerId` are identity ids; there is no
   `@Me` macro as in WIQL. That implies a `_apis/connectionData` call first to
   resolve the PAT owner's id (cacheable). **Unverified — needs a live probe**;
   TaskBox's history says this class of assumption is exactly what a probe
   overturns.
4. **Azure scope.** Project-level (`{org}/{project}/_apis/git/pullrequests`)
   versus repo-level. Project-level avoids per-repo fan-out; whether it spans
   every repo in the project needs the same probe.
5. **Rate limits.** GitHub `/search/issues` is 30 req/min authenticated — two
   searches per 60s tick is fine, per-repo fan-out is not.
6. **Sort and cap for a mixed list.** Two providers, one list: sort key
   (updated-at?), per-provider caps or a single global cap, and how a provider
   is identified on a row (icon? prefix?).
7. **Does "PRs awaiting my review" include drafts?** GitHub can return draft
   PRs in both queries.

## Probe available

Both PATs are already configured on this machine (`settings.json`: GitHub
`haqaliz/deck`, Azure `ForesightAnalytics/ForesightManifold`), so questions 3
and 4 can be settled against the live APIs before the PRD freezes — the same
move that reshaped TaskBox.

## Invariant check

Nothing here touches a CLAUDE.md invariant: no new data path, no settings UI
inside a widget, no sub-60s cadence, no subprocess. The only cross-cutting
edits are the two exhaustive `FetchSource` switches and the mandatory version
bump.
