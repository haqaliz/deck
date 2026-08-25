# PRD — ShipBox multi-repo

**Slug:** `shipbox-multi-repo` · **Branch:** `feat/shipbox-multi-repo/aliz`
**Closes:** `ROADMAP.md:311` (M6), follow-up from `docs/planning/shipbox/prd.md:118`

## 1. The ask, in one sentence

ShipBox watches one `owner/repo`; grow it to a small set of repos — discovered
automatically by default, or picked by hand — merged into one newest-first list
of runs, without adding a second snapshot, a second fetch-status key, or a
second timeline entry.

## 2. Live API probe (run 2026-08-25 against `api.github.com`, ShipBox's own PAT)

Written **before** the design below, because this repo has twice been saved by
doing so (PRBox, MarketBox). Five findings, three of which changed the design.

| # | Probe | Result | Consequence |
|---|---|---|---|
| P1 | `GET /rate_limit` | core **5000/hr**, remaining 5000 | Not a constraint. 60 ticks/hr × 6 calls = 360/hr, doubled to ~720 when the settings window is open. Room to spare. |
| P2 | `GET /user/repos?sort=pushed&per_page=100` | 200, **31 repos**, 154 KB, 2.4 s, **no `Link` header** | The inventory both modes need is **one call**. No pagination for this account; >100 repos would need it, so the design caps at one page and says so. |
| P3 | Does a repo advertise Actions? | **No such field.** `[k for k in repo if "workflow" in k or "action" in k]` → `NONE` | **Dynamic mode cannot know which repos have CI without calling each one.** Drives the over-fetch rule in §5. |
| P4 | `actions/runs?per_page=1` × all 19 owned repos, concurrently | 19 calls in **3.0 s**; **7 of 19 have runs**; the 6 most-recently-pushed all do; `haqaliz/homebrew-contig` (7th by push) has none | Recency predicts CI well but not perfectly — over-fetch a small buffer and keep the first N that answer. |
| P5 | 5 repos, `per_page=10`, **serial vs concurrent** | **serial 9.44 s**, concurrent **2.06 s**; payload **~119 KB per repo** | **Serial fan-out is not viable**: `URLSession.timeoutInterval` is 10 s *per request*, so five stalled repos is a 50 s tick against a 60 s cadence. Concurrency is mandatory (§7 deviation). `per_page=5` halves the payload to 57 KB — run objects embed the entire repository object. |

Two smaller facts, both load-bearing:

- **An unknown repo returns 404** (`FetchClassifier` → `.authOrTarget`), and a
  repo with **no workflows returns 200 with `total_count: 0`** — indistinguishable
  from "no runs yet". One bad repo must therefore not fail the whole fetch.
- **`affiliation` matters**: `owner` → 19 repos (all `haqaliz`), the default →
  31, including 12 repos owned by four other people the user collaborates with.

## 3. User-visible spec — front face

**Layout: one merged stream, newest first across all repos** (user decision).
Accepted trade-off: a repo with busy CI can push a quieter repo off the list
entirely. No per-repo fair share, no grouping — see non-goals.

**Row identity: the repo replaces the workflow name** (user decision).

```
┌── ShipBox ──── 3 repos ─── 1 fail · 4 pass ──┐
│ RUNS                                          │
│ ● deck #15            master · 3m12s          │
│ ● deck #14            master · 1m02s          │
│ ● cyclo #88           main · RUNNING          │
│ ● pong #7             main · 2m30s            │
└───────────────────────────────────────────────┘
```

- **Row** — status dot (existing four colors) · `<repo-short> #<runNumber>` ·
  `<branch> · <duration|RUNNING|QUEUED>`. `repo-short` is the segment after the
  `/` (`haqaliz/deck` → `deck`); the owner is noise when most repos share one.
  Where two configured repos share a short name, both fall back to `owner/repo`
  for **all** rows (one rule per snapshot, not per row).
- **Header** — `entry.repo` is replaced by a repo count (`"3 repos"`), keeping
  the existing totals line and chip to its right. One configured repo renders
  its name exactly as today, so a single-repo user sees no change at all.
- **Small** 2 rows · **medium** `runCount` rows · **large** `runCount` rows plus
  the existing PASS/FAIL/RUN/QUEUED totals row. Unchanged from today.
- **Note line** (new, MarketBox precedent) — one line naming repos that failed
  while others succeeded; nil when everything worked. §6.
- **Rows are clickable** (user decision): each row is a `Link` to the run's
  `html_url`; the small face carries a `widgetURL` to the newest run.
  `ShipRun.htmlURL` is already parsed and currently unused.

**Empty states** — unchanged in shape: no snapshot → "No build data" + the chip;
snapshot with zero runs → "No runs yet".

## 4. User-visible spec — back face (settings)

The tab gains **two sub-tabs**, PRBox's precedent (`DeckApp.swift`, per-provider
sub-tabs). Mode is a stored setting, not just UI state.

**Dynamic (default)** — zero-config: paste a token, get your active repos.

| Control | Default | Notes |
|---|---|---|
| `Repos to watch` stepper | **3** (range 1–5) | The only repo control in this mode |
| Caption | — | "The repos you pushed to most recently that have any Actions runs." |

**Static** — explicit picks.

| Control | Default | Notes |
|---|---|---|
| `Repo 1…5` pickers | empty | Populated from `/user/repos` (default affiliation, so collaborator repos are pickable). Slot order is display order; an empty slot closes up. |
| Caption | — | Names why the list is empty when it is (no token / fetch failed) |

Shared by both: the existing `GitHub token` field, `Show runs list`,
`Run count` (2–8), and the four status colors — all unchanged.

- A configured repo the inventory doesn't offer stays visible and changeable
  (MarketBox's `configuredSymbolsNotInPicker` rule) — a token that lost `repo`
  scope must not silently erase the user's picks.
- The inventory is fetched by the **host app** when the tab appears, never by
  the agent and never by the widget. It is not persisted.
- `FetchStatusCaption(source: .shipbox, clearOn:)` stays, with the mode, the
  repo list and the token in its `clearOn` key.

## 5. Data source and fetch policy

Unchanged path: `DeckAgent` (60 s) → `shipbox.json` → widget. The host app's
`refreshShipBox()` mirrors it exactly, as today.

**Resolving which repos to fetch:**

- *Static* — the configured slots, in order, capped at 5.
- *Dynamic* — one `GET /user/repos?sort=pushed&per_page=100&affiliation=owner`,
  then **two waves** (C2): wave 1 probes the top `min(maxRepoCount + 3, 8)` repos
  at `per_page=1` (~11 KB each) to learn which have runs; wave 2 fetches full
  runs for the first `maxRepoCount` winners only. Fetching all candidates in
  full would cost ~45 MB/hr for an 8-row widget; this halves it to ~22 MB/hr. P3 forces
  the over-fetch (nothing in the repo object says "has CI"); P4 sizes the
  buffer at 3 (the first miss on real data was at position 7).
  `affiliation=owner` deliberately excludes the 12 collaborator repos P2 found:
  auto-discovery should not surface someone else's repo by recency. The static
  picker offers them, so nothing is unreachable. *(Amber — see §9 Q1.)*

**Fetching runs:** `per_page = max(runCount, 2)` (≤ 8, so ≤ 8 runs per repo).
A correct merged top-`runCount` needs at most `runCount` per source, which makes
this provably sufficient and roughly halves P5's payload.

**Concurrency:** all repo fetches run in one `withTaskGroup`, each with the
existing 10 s timeout. P5 makes this non-optional.

**Merge:** all runs concatenated, sorted by `createdAt` descending (PRBox's
"creation date is the key both providers can promise" rule), tagged with their
repo.

**Cadence:** unchanged 60 s everywhere. One timeline entry, 60 s reload policy.

## 6. Failure policy — the design point the card flagged

`FetchSource.shipbox` **stays one key**. It cannot grow per-repo keys (the enum
is static), and it should not: the widget needs one sentence, not five.
MarketBox already solved this shape for four providers.

| Situation | `FetchStatus` | Snapshot | Face |
|---|---|---|---|
| All repos fetched | `.ok` | written, `note = nil` | normal |
| Some repos failed, ≥1 succeeded | **`.ok`** | written from the survivors, `note` names the failures | rows + note line |
| Every repo failed | classified from the **first** error | **not written** (last-good survives) | last-good rows + chip |
| No token, empty static list, or a **successful** inventory call that found no repo with runs | `.notConfigured` | not written | "No build data" + chip |
| The dynamic **inventory call itself** failed (401, offline) | classified from that error | not written | last-good rows + chip (**never** "not configured" — C1) |
| Repos fetched, all returned `total_count: 0` | `.ok` | written, `runs: []` | "No runs yet" |

**Note wording** reuses `PRChip.text`'s composition rule verbatim
(`FetchStatus.swift:349`), which already solved "name which target failed" for
N=2:

- one failure → `"cyclo: check repo + token"`
- N failures, same outcome → `"cyclo + 2 more: check repo + token"`
- N failures, different outcomes → `"cyclo: check repo + token +2 more"`

The reason strings come from the existing `FetchStatusCopy.line(source:outcome:)`
table, so no new copy is invented.

## 7. Shell fit

**Reused unchanged:** `AtomicFile` (one file, one write), `FetchStatusStore` /
`FetchClassifier` / `FetchStatusCopy` / `FetchChip`, `RunParser`,
`RunFormatting`, `ShipStatus.map`, `DeckLink` + `DeckURLForwarding` (for the new
row links), the agent's 60 s LaunchAgent, the host app's 60 s timer.

**Invariants checked (CLAUDE.md):** no Swift Charts anywhere near the face; one
timeline entry with a 60 s policy (the CalBox 1.4 MB-archive lesson); all
network in the unsandboxed agent/host; one snapshot file written atomically;
tolerant decode on every settings struct; version bump to **1.28 / 28** across
the three targets in `project.yml`.

**One deviation, stated not hidden:** `withTaskGroup` for the fan-out is the
**first concurrent fetch in the codebase** — every existing loader awaits
serially (MarketBox awaits its four providers one after another). P5 shows why:
serial is 9.4 s measured and 50 s worst-case against a 60 s tick. Contained to
`HostGitHubLoader`; no shared mutable state (each child returns its own result).

**Migration:** `ShipBoxSettings.repo: String` → `repos: [String]` + `repoMode`,
following MarketBox's `symbols` → `tickers` migration exactly (read the legacy
key when the new one is absent, normalize, encode only the new shape). A
non-empty legacy `repo` migrates to `repos: [repo]` **and pins the mode to
static**, so an existing user keeps the repo they configured instead of being
silently switched to auto-discovery. `ShipBoxSnapshot` gains a hand-written
tolerant `init(from:)` (legacy `repo` → `repos`, missing `ShipRun.repo` → ""),
so the first tick after the upgrade renders the old snapshot instead of blanking
to "No build data".

## 8. Non-goals

- **No per-repo fair share or grouping.** A busy repo crowding out a quiet one
  is the accepted cost of the merged stream (§3).
- No org-wide or "all my repos" watching beyond the cap of 5.
- No pagination past the first 100 repos in the inventory.
- No checks/commit-status API, no deployments, no PR merge status (carried from
  ShipBox slice 1).
- No "latest per workflow" grouping.
- No per-repo colors, no per-repo run counts.
- No Keychain move for the token — that rides the Developer ID release
  (`docs/planning/notarization/runbook.md:249`).

## 9. Open questions

- **Q1 (amber, defaulted):** dynamic mode uses `affiliation=owner`, so the 12
  collaborator repos P2 found never auto-appear. Defensible (auto-discovery
  shouldn't surface someone else's repo), reversible in one line, and the static
  picker still offers them. Ship as specified unless you want the wider set.
- **Q2 (amber, defaulted):** `maxRepoCount` defaults to **3**, not 5 — three
  rows of repos is what fits a medium face beside a `runCount` of 4. Trivially
  changed in settings.
- **Q3 (green):** >100 repos needs inventory pagination. Not this unit of work;
  recorded as a follow-up.

---

## 10. Self-critique (deck-prd critique mode)

Eight findings against §1–9. Two red, five amber, one green. Fixes are folded
into the sections above where they were cheap; the rest are called out here.

### 🔴 C1 — The failure table calls a failed inventory fetch "not configured"

§6's last-but-one row lumps "dynamic found no repos" in with "no token" and
routes both to `.notConfigured`. But *dynamic found nothing* has two very
different causes: the account genuinely has no repos with Actions (correctly
"not configured"), and **`GET /user/repos` itself failed** — 401 from a revoked
token, or offline. Routing a failed inventory call to `.notConfigured` tells the
user "add a repo + token in settings" when their token is right there and the
real answer is "GitHub is unreachable". That is precisely the class of lie the
`agent-fetch-status` milestone existed to kill (`ROADMAP.md:74`).

**Fix (applied to §6):** the inventory is a fetch like any other. It fails →
classify with `FetchClassifier` and keep the last-good snapshot. Only an
**empty result from a successful call**, an empty static list, or a missing
token is `.notConfigured`.

### 🔴 C2 — Dynamic mode as specified downloads ~45 MB/hour

§5 fetches `min(maxRepoCount + 3, 8)` repos at `per_page = runCount`. Measured
against the live API just now:

```
per_page=1  →  11.4 KB      per_page=8  →  91.6 KB
per_page=5  →  57.2 KB      per_page=10 → 114.5 KB
```

A run object embeds the entire repository object, so payload is ~11.4 KB **per
run**. Eight repos × 8 runs = ~760 KB **every 60 seconds — ~45 MB/hour**, for a
widget showing at most 8 rows. The buffer repos are the waste: 5 of the 8 are
fetched in full only to be discarded for having no runs.

**Fix (applied to §5):** two waves. Wave 1 probes the candidates at
`per_page=1` (~11 KB each) purely to learn which have runs; wave 2 fetches
`per_page = runCount` for the `maxRepoCount` winners only. 8×11.4 + 3×91.6 ≈
**366 KB/tick (~22 MB/hr)**, half the bytes, at the cost of one extra round trip
(~1.3 s, measured). Static mode is unaffected — it fetches exactly its
configured repos in one wave.

*Recorded as a follow-up, not built:* caching the discovered set and re-running
discovery every ~10 ticks would drop dynamic mode to ~16 MB/hr, but it adds
cross-tick state the snapshot doesn't have today.

### 🟡 C3 — In dynamic mode, the failure copy points at a field that isn't there

`FetchStatusCopy` is keyed by `FetchSource` alone, so `.shipbox` +
`.authOrTarget` always reads **"Check repo + token"** and the settings caption
expands it to a sentence about the repo field. In dynamic mode there is no repo
field — the only thing the user can fix is the token, and the copy sends them
hunting for a control that does not exist in the tab they are looking at.

**Fix:** a small mode-aware shim in front of `FetchStatusCopy.line` that
substitutes token-only wording for `.shipbox` when `repoMode == .dynamic`
("Check your token"). Do **not** add a `FetchSource` case — the file's own
comment says the key exists so that each settings sub-tab shows its own
sentence, and here both sub-tabs share one fetch.

### 🟡 C4 — A failing repo can be invisible on the small face

Small shows 2 rows from a merged newest-first list, so two fresh passing runs
from a busy repo can fill it while another repo is red. The header totals line
(`1 fail · 4 pass`) is the mitigation — except `ShipBoxWidget.swift:180`
**suppresses the totals on small whenever a chip is present**, on the grounds
that a small face has room for one hint. With a chip showing, a small ShipBox
can render all-green while a repo is failing.

**Fix:** on the small face, when `totals.failure > 0`, the totals line wins over
the chip (invert the existing precedence). A red count is a fact about the data;
the chip is a fact about the fetch, and the data wins when it is bad news.

### 🟡 C5 — A failing repo's last-good runs are dropped, not kept

§6 writes the snapshot from the survivors, so a repo that fails a tick loses its
rows entirely until it recovers. This is MarketBox's policy and it contradicts
the principle in `FetchStatus.swift:11` ("a failure never rewrites the data file
— last-good data cannot be lost"), which was written when a snapshot had exactly
one source.

**Decision: keep the MarketBox policy** (drop the rows, name the repo in the
note) rather than merging stale runs from the previous snapshot into a fresh
one. Retained rows would silently age at different rates inside one list sorted
by creation date, and `stale`/`writtenAt` are per-snapshot, so nothing on the
face could tell the user which rows were three ticks old. Losing rows for one
tick is honest; a list where some rows are stale and unlabelled is not.
*Recorded so the next reader sees it was chosen, not missed.*

### 🟡 C6 — The static picker is empty until a token exists, with no explanation

Static mode's pickers are populated from `/user/repos`, which needs the token
that lives in the shared section. A user who opens the tab, switches to Static
and finds five empty dropdowns has no way to know why.

**Fix:** the shared token field renders **above** the sub-tabs, and the static
tab's caption states the dependency and the current reason it is empty — no
token / the inventory fetch failed (with its classified reason) / the account
has no repos. Reuses the existing caption machinery; no new copy table.

### 🟡 C7 — The dynamic set changes under the user with no warning

Push to a repo and it can enter the watched set, displacing another. That is the
point of the mode, but nothing in the UI says so, and the effect on the face
(rows for a repo the user never configured) reads as a bug the first time.

**Fix:** the dynamic caption already drafted in §4 states the rule; make it
explicit that the set **changes as you push** rather than only describing how it
is chosen.

### 🟡 C8 — The PRD names no verification

Every prior Deck unit of work TDD'd its pure logic. This one has a clear
pure-logic surface and the PRD doesn't claim it.

**Fix (for the plan):** XCTest coverage in `native/SharedTests/` for the merge
+ sort, the short-name collision rule, the note composition (one / same-reason /
mixed-reason), the settings migration (legacy `repo` → static mode), the
snapshot's tolerant decode, and the dynamic selection rule (buffer, first-N
non-empty). The faces and the settings sub-tabs are verified by build + install
+ re-add from the gallery at all three sizes, per the blueprint.

### 🟢 C9 — Inventory pagination past 100 repos

Already recorded as §9 Q3. This account has 31, no `Link` header. Fine to defer.
