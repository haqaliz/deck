# PRD: agent-fetch-status

**Slug:** `agent-fetch-status` (branch `feat/agent-fetch-status/aliz`)
**Type:** feat · **Source:** `docs/planning/_card/issue.md`, follow-up recorded
at `docs/planning/shipbox/prd.md:123` · **Dig:** `understanding.md`

## 1. The ask

When an agent-fetched widget has nothing to show, say **why** — "check repo +
token" is a different problem from "can't reach GitHub", and today both render
the same generic line. And when a fetch fails but real data is already on
screen, keep the data and attach the reason instead of eventually blanking it.

## 2. User-visible spec

No new settings; no new controls. Everything is on the front face.

### 2.1 Widget has data (any age)

The normal face renders as it does today, plus:

- **Reason chip** in the header line, next to the existing totals/time hint:
  a short line naming the outcome (see §2.3), shown only while the last
  recorded attempt failed. Same type language as the stale hint
  (`ShipBoxWidget.swift:184`): 10pt rounded, `.tertiary`.
- **Age is always visible past 5 min** (today's `stale` rule), so old data
  reads as old rather than as current.
- Small face: the chip degrades to the reason alone (no totals) — a small
  widget has room for one hint, not two.

### 2.2 Widget has no data at all

The existing unavailable view, with its hard-coded second line replaced by the
recorded reason when one exists. Falls back to today's wording when no status
has been written yet (fresh install, agent hasn't run).

### 2.3 The four outcomes and their copy

The shared outcome vocabulary is coarse on purpose — wttr.in and
`opencode serve` do not report failures precisely enough to justify more.
The line is per-source, because "check repo + token" is nonsense for weather:

| Outcome | ShipBox | HomeBox | OpenBox (remote) |
|---|---|---|---|
| `notConfigured` | "Add a repo + token in settings" | *(n/a — empty location is valid: wttr.in geolocates)* | "Paste your opencode token" |
| `authOrTarget` | "Check repo + token" | "Check the location" | "Check server URL + token" |
| `unreachable` | "Can't reach GitHub" | "Can't reach wttr.in" | "Can't reach the opencode server" |
| `badResponse` | "Unexpected GitHub response" | "Unexpected wttr.in response" | "Unexpected server response" |

`ok` renders no chip at all.

**OpenBox local mode never shows a chip (🔴 C2).** The status file is about the
remote path only. Without this rule a user who tries remote mode, fails, then
clears the server URL would keep a stale "Check server URL + token" chip on a
perfectly healthy local OpenBox. Two guards: the widget reads the status only
while `settings.openbox.serverURL` is non-empty, **and** a successful local
load records `ok`, so the file can never hold a stale failure.

### 2.4 Blanking is dropped (behaviour change)

Today ShipBox/HomeBox blank past 30 min and OpenBox past 2 h
(`ShipBoxWidget.swift:65`, `HomeBoxWidget.swift:80`, `OpenBoxWidget.swift:94`).
After this slice, **a snapshot that exists is always rendered**; the age hint
and the reason chip carry the honesty instead. The unavailable view is reached
only when no snapshot exists at all.

**Dead-agent rule (from the critique, 🔴 C1).** A failure chip only appears if
an attempt was *made*. If the agent is not running at all, no attempt is
recorded and the face would otherwise show week-old data with nothing but a
timestamp — strictly less honest than today's "Waiting for the Deck agent…".
So: when the newest of (`snapshot.writtenAt`, `status.attemptedAt`) is older
than 30 min, the chip reads **"Agent hasn't run"**. The data still stays on
screen; only the wording changes. This keeps the old signal without blanking.

## 3. Data source

No new source — this is metadata about fetches that already happen.

**Classification input already exists and is typed** (`understanding.md` §2):
`HostGitHubLoader.GitHubError`, `HostWeatherLoader.WeatherError`,
`RemoteOpenCodeLoader.RemoteError`. The agent currently discards it with `try?`
(`DeckAgent/main.swift:103,116`); it becomes `do/catch` + a pure classifier.

Mapping (pure, TDD'd):

- transport error → `unreachable`; invalid payload / unparseable JSON → `badResponse`
- HTTP 401/403/404 → `authOrTarget`; 429 + 5xx → `unreachable`; other 4xx → `badResponse`
- malformed config (`invalidRepo`, `invalidURL`, `invalidLocation`) → `authOrTarget`
- configured-off (ShipBox repo/token empty; OpenBox serverURL set + token empty) → `notConfigured`
- success → `ok`

**Storage: one small file per source**, `fetch-{source}.json` in the widget
container, next to the snapshots — *not* new fields on the snapshot structs.
Reasons (from the dig):

1. A failure then never touches the data file, so "never blank real data" holds
   structurally, not by care.
2. Snapshot `Equatable` stays payload-only, so the agent's
   "skipped (unchanged)" write-avoidance (`main.swift:57`) survives — a
   per-attempt timestamp inside `Equatable` would make every tick differ and
   undo M4 robustness work.
3. A status can exist when no snapshot ever has (first run, bad token) — the
   case an embedded field cannot express.
4. Missing file = no status = exactly today's behaviour.

**Every branch records, including the skips (🔴 C2/C3).** The agent's
"not configured" paths currently only log and move on (`main.swift:127`,
and the `token.isEmpty` branch at `:52`); they must write `notConfigured`, or
the widget can never distinguish "you haven't set this up" from "nothing has
ever run". Likewise a successful fetch must write `ok` — the file is what
clears a previous failure.

**Both writers record it.** The host app refreshes on launch and on settings
change (`DeckApp.swift:53-65,88,140,149`) as well as the agent, so both call
the same recorder — otherwise a settings change leaves a stale reason on screen.

**Cadence:** unchanged (60s agent tick, 60s timelines). Reading one extra small
JSON per timeline; ShipBox already re-reads its snapshot in the header.

**Tolerant decode:** an unrecognised outcome string decodes to `ok` (renders
nothing) so a newer agent never makes an older widget show a wrong reason.

## 4. Shell fit

- New: `Shared/FetchStatus.swift` (source + outcome enums, `FetchStatus`,
  `FetchStatusStore`, classifiers, per-source copy),
  `SharedTests/FetchStatusTests.swift`.
- Touched: `DeckAgent/main.swift` (3 catch sites), `DeckApp/DeckApp.swift`
  (3 refresh methods + the ride-along in §6), the three widget files
  (provider + header chip + unavailable line), `README.md`, `ROADMAP.md`.
- `xcodegen generate` required (new source files; directory-based sources —
  no `project.yml` edit).
- No shell invariant touched: no new sampler, no entitlement, no cadence
  change, no settings UI inside a widget, no new settings key.

## 5. Non-goals

- No retry/backoff, no notifications, no menu-bar alerting.
- No raw API error strings on the face (they leak URLs/repos; the agent's
  logging contract at `main.swift:15-17` forbids it — outcomes only).
- No status for **local** OpenBox mode: `OpenCodeReader.load()` has no typed
  error, and today's "Run opencode to record usage." is already the correct
  and specific line. Remote mode only.
- No status for GitBox/DevBox/ClipBox (local samplers; different failure story).
- No change to the fetch logic itself, the 60s cadence, or any payload shape.
- No per-widget "last attempt" timestamp on the face beyond the existing age
  hint.

## 6. Ride-along (approved)

Remove the dead `OpenBoxSettings.refreshInterval` stepper
(`DeckApp/DeckApp.swift:399`) — it drives no code path (flagged in
`docs/planning/livebox-process-cadence/prd.md:86`). The `refreshInterval` key
stays in `OpenBoxSettings` with its tolerant decode so existing `settings.json`
files still load unchanged.

## 7. Decisions (from the interview)

- Scope: all three widgets in one slice — the mechanism is shared.
- Blanking: dropped; data + reason chip + age (§2.4).
- Vocabulary: four coarse outcomes (§2.3).
- Ride-along: remove the stepper, keep the key.

## 8. Test strategy (TDD, DeckSharedTests)

Pure logic first, RED → GREEN:

1. `classify` over each loader's error cases, including status-code branches
   (401/403/404 → `authOrTarget`; 429/500 → `unreachable`; 418 → `badResponse`).
2. Per-source copy table (§2.3): every source × outcome returns the expected
   line; `ok` returns nil.
3. `FetchStatus` round-trip encode/decode; unknown outcome string → `ok`;
   missing file → nil status.
4. Store save/load against a temp-dir URL. Note the codebase pattern is
   **URL injection**, not container redirection: `ProcessSnapshotStore` exposes
   `save(_:to:)` / `load(from:)` (`ProcessSnapshotStoreTests.swift:31-33`), so
   `FetchStatusStore` must do the same, with the container path as the default.

Widget faces are verified by build + install + gallery re-add at all three
sizes (no UI test target exists).

## 9. Verification

- `xcodegen generate` + Release build green; `DeckSharedTests` green.
- Manual, per widget, all three sizes after re-adding from the gallery:
  bad token → "Check repo + token"; unset repo → "Add a repo + token in
  settings"; wifi off → "Can't reach GitHub"; recover → chip disappears.
- With a good snapshot on screen, break the token: data stays, chip appears,
  age keeps counting — nothing blanks.
- `log show --predicate 'subsystem == "com.deck.agent"'` still shows one line
  per snapshot; no URL/token/repo leaks.

## 10. Open questions

None blocking — §7 resolved the four; local-mode OpenBox is settled as a
non-goal (§5).

## 11. Self-critique (deck-prd critique mode)

Findings against the first draft, with the fix applied in-place above.

🔴 **C1 — Dropping blanking loses the dead-agent signal.** A chip is only
written when an attempt happens. With the agent stopped (or never installed),
nothing attempts, nothing is recorded, and the face would show arbitrarily old
data with no explanation — a regression against today's "Waiting for the Deck
agent…". *Fixed*: dead-agent rule in §2.4 (newest of writtenAt/attemptedAt
older than 30 min → "Agent hasn't run"), data still not blanked.

🔴 **C2 — Stale status can outlive the mode that produced it.** OpenBox
switching remote → local would keep showing a remote failure chip forever, and
a ShipBox repo cleared in settings would keep "Check repo + token". *Fixed*:
§2.3 mode guard for OpenBox, plus §3 — success writes `ok` and the
not-configured branches write `notConfigured`, so no branch leaves the file
untouched.

🔴 **C3 — The not-configured branches never reach the classifier.** The agent
skips the fetch entirely when repo/token are empty (`main.swift:127`), so the
most user-fixable state of all would never be recorded. *Fixed*: §3 — the skip
branches write status too.

🟡 **C4 — Test API mismatch.** The draft assumed container redirection; the
codebase injects URLs (`ProcessSnapshotStore.save(_:to:)`). *Fixed*: §8.4, and
`FetchStatusStore` takes the same shape.

🟡 **C5 — 429 reads as "Can't reach GitHub".** Rate-limited is not unreachable,
but it is transient and not user-fixable, so it groups with `unreachable`
rather than earning a fifth outcome. Accepted, documented here; revisit only if
rate limiting turns out to be common at a 60s cadence (it should not be —
5000 req/h authenticated vs 60 req/h used).

🟡 **C6 — Small-face crowding.** A chip plus the totals line will truncate the
repo name at `.systemSmall`. *Fixed*: §2.1 — on small, the chip replaces the
totals line rather than joining it.

🟡 **C7 — Two writers race on the status file.** App and agent can write the
same `fetch-*.json` concurrently. `AtomicFile` keeps each write atomic, so the
worst case is last-writer-wins between two attempts made seconds apart — both
report the same outcome in practice. Accepted; no locking.
