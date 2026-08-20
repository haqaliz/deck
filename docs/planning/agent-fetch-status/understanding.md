# agent-fetch-status — understanding note

Slug confirmed: `agent-fetch-status` (descriptive; the type lives in the branch
`feat/agent-fetch-status/aliz`).

## What the work is really asking

Three widgets render agent-fetched data that can fail for *user-fixable*
reasons (wrong token, wrong repo, no token pasted) and for *transient* reasons
(offline, API down). Today every one of those collapses to one generic line,
so the user cannot tell "I typed the repo wrong" from "my wifi is down" from
"there genuinely are no runs yet".

The ask: record **why** the last fetch attempt failed, and say it on the widget
face in one short human line.

## What the code actually does today (verified)

**The agent throws the reason away.** `DeckAgent/main.swift:103` and `:116` use
`try?`, so the typed error is discarded and only a fixed OSLog string is
written ("failed weather snapshot (network unavailable)", "failed shipbox
snapshot (network or API unavailable)"). Nothing reaches the container.

**The loaders already have typed errors** — this is the good news, the
classification input already exists and is pure:

| Loader | Error type | Cases |
|---|---|---|
| `HostGitHubLoader` (`ShipBoxSnapshot.swift:75`) | `GitHubError` | `invalidRepo`, `serverError(Int)`, `transport(String)`, `invalidPayload` |
| `HostWeatherLoader` (`HomeBoxSnapshot.swift:65`) | `WeatherError` | `invalidLocation`, `serverError(Int)`, `transport(String)`, `invalidPayload` |
| `RemoteOpenCodeLoader` (`RemoteOpenCodeLoader.swift:12`) | `RemoteError` | `invalidURL`, `unauthorized` (401/403), `serverError(Int)`, `transport(String)` |

GitHub's 401 vs 404 both arrive as `serverError(code)` — the code is retained,
so "auth or repo wrong" is distinguishable from "GitHub is down" (5xx).
`OpenCodeReader.load()` (local mode) is not a fetch and returns `nil` with no
error type — it means "no local opencode DB / no usage", a different story.

**Widgets decide availability purely by snapshot age**, and each has a
hard-coded generic hint:

| Widget | Availability rule | Unavailable line |
|---|---|---|
| ShipBox (`ShipBoxWidget.swift:65,123`) | age > 30 min | "No build data" / "Paste a repo + token in Deck settings." |
| HomeBox (`HomeBoxWidget.swift:80,136`) | age > 30 min | "No weather data" / "Waiting for the Deck agent…" |
| OpenBox (`OpenBoxWidget.swift:94,172`) | age > 2 h | "No opencode data" / "Run opencode to record usage." |

ShipBox additionally distinguishes `runs.isEmpty` → "No runs yet"
(`ShipBoxWidget.swift:140`) — but only while the snapshot is fresh, which is
exactly the ambiguity the ShipBox PRD follow-up names.

## Two writers, not one (important)

Both `DeckAgent/main.swift` **and** the host app write these snapshots — the app
refreshes on launch and on settings change (`DeckApp.swift:53-65`, with
`refreshOpenCode()` `:88`, `refreshHomeBox()` `:140`, `refreshShipBox()` `:149`).
Whatever records status must be written by both paths, or a settings change in
the app will silently leave a stale reason on screen.

Note this differs from `processes.json`, which crash-robustness-pass
deliberately reduced to a single writer (ROADMAP M4); these three files have
always had two.

## Design constraint found in the code

The agent skips writes when a snapshot is unchanged (`main.swift:57`,
`opencode != OpenCodeSnapshotStore.load()`). If a per-attempt timestamp became
part of snapshot `Equatable`, every tick would differ and the skip
optimization would die — more writes, against the M4 robustness work.

That pushes toward **status in its own file(s)**, not new fields on the
snapshot structs:

- a failure then never rewrites the data file, so "never blank a widget that
  has real data" is guaranteed structurally rather than by care;
- `Equatable`/diff/soak behaviour of the three snapshots is untouched;
- a status can exist when no snapshot has ever been written (first run with a
  bad token) — the case an embedded field cannot express;
- missing file = no status = exactly today's behaviour (free tolerant decode).

Cost: one extra small file read per timeline (ShipBox already re-loads its
snapshot in the header, `ShipBoxWidget.swift:184`), and 3 new files in the
container.

## Affected files (expected)

- New: `Shared/FetchStatus.swift` (outcome enum + store + pure classification
  + the human line), `SharedTests/FetchStatusTests.swift`.
- `DeckAgent/main.swift` — `try?` → `do/catch`, classify, record (3 sites).
- `DeckApp/DeckApp.swift` — same recording in the 3 refresh methods; the dead
  `OpenBoxSettings.refreshInterval` stepper at `:399` is the flagged ride-along.
- `DeckWidgets/{ShipBox,HomeBox,OpenBox}Widget.swift` — unavailable view renders
  the reason; data-present faces get a reason hint next to the existing stale
  hint.
- `README.md`, `ROADMAP.md` — registration.

No `project.yml` edit needed (sources are directory-based) — but `xcodegen
generate` **is** required so the new files compile (CLAUDE.md).

## Shell invariants — no conflict

Path-2 widgets only; no new sampler, no timeline/cadence change, no settings UI
inside a widget, no new entitlement. The status line reuses the existing
rounded-font / secondary-foreground language.

## Ambiguities for the interview

1. **Scope**: all three widgets in one slice, or ShipBox first (its PRD is the
   recorded source) with HomeBox/OpenBox as slice 2?
2. **Staleness windows**: keep the shipped 30 min / 2 h blanking (unavailable
   view just names the reason), or keep showing last-good data past the window
   with the reason attached? The brief says never blank *real* data.
3. **Wording set**: how many distinct outcomes to surface — proposed coarse
   four: not configured / auth or target wrong / unreachable / bad response.
4. **Local OpenBox mode**: does a missing local DB deserve its own line, or is
   status remote-mode-only?
5. **Ride-along**: wire `OpenBoxSettings.refreshInterval` or delete it?
