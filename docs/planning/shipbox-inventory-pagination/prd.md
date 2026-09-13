# ShipBox inventory pagination + caching — PRD

Slug: `shipbox-inventory-pagination`. Type: feature (loader + policy). No face,
no settings, no shell changes.

## 1. The ask

Two open follow-ups from ShipBox multi-repo (`ROADMAP.md:371-372`,
`docs/planning/shipbox-multi-repo/prd.md`):

1. **Pagination** — the repo inventory (`GET /user/repos`) is fetched one page
   at `per_page=100` and silently truncates at 100 repos.
2. **Caching** — dynamic mode re-fetches the full inventory (~154 KB, 2.4s,
   probe P2) every 60s tick, costing ~6 MB/hr that a sidecar cache can recover
   (22 → ~16 MB/hr, the figure the multi-repo PRD recorded).

## 2. User-visible behavior

Nothing on the face changes. The user-visible deltas:

- **Dynamic mode (default):** the widget works exactly as today — the same
  repos, the same runs, the same note. The repo list simply stops being
  re-downloaded every minute; it refreshes at most every **10 minutes**.
- **Static picker:** opening **Pick repos…** always fetches a **complete** list
  (past 100 repos too, paginated) — strictly more repos visible than today.
- **Failure shape:** unchanged. A broken token or network still fails the tick
  and writes the same fetch-status note; the last-good snapshot stands.
- **Account switch:** switching GitHub accounts in Credentials never shows
  the previous account's repo list for even one tick of dynamic discovery.

## 3. Data source & refresh cadence

`GET https://api.github.com/user/repos?sort=pushed&per_page=100&affiliation=owner`
(Bearer token, the loader's existing `get`). Measured on the live account:
31 repos, 154 KB, 2.4s, **no `Link` header** (single page — probe P2). This
account can therefore never exercise pagination live; the unit tests are the
only verification, and the live tick must be observed to make **no extra
requests** beyond today's.

### 3.1 Pagination (picker path)

Follow the response `Link` header's `rel="next"` URLs until absent, appending
each page's repos. Bounds:

- **Same-origin only.** The `Link` header is data from the network; the
  request carries the user's token. Only `https://api.github.com` links are
  followed (the `DeckURLForwarding` host-filter precedent).
- **Page cap: 5 pages** (500 repos). A giant account cannot stall the settings
  window; the picker degrades to a complete-as-far-as-it-got list.
- The parser keeps the API's `sort=pushed` order; pages append in the order
  they arrive (page 1's repos stay ahead of page 2's — pushed order is
  global, but the cap note should name the truncation if it ever bites).

### 3.2 Cache (dynamic path)

Sidecar `shipbox-inventory.json` beside the snapshots in
`DeckSettings.containerDirectory` (the `opencode-cursor.json` precedent:
`RemoteOpenCodeSync.swift:169-184`, `AtomicFile.write`, version check, corrupt
→ nil → self-heal).

Record: `{ version, accountID, affiliation, fetchedAt, repos }`.

`affiliation` matters because the two producers fetch different scopes: dynamic
mode asks `affiliation=owner` (the multi-repo PRD's Q1 decision — never show a
repo the user doesn't own) while the picker asks the default (collaborator
repos included, deliberately). A picker-written record must never feed dynamic
discovery, so the policy matches affiliation as well as account. A picker
write is therefore usually displaced by the next dynamic refresh — it exists
for the settings→dynamic switch, and it is harmless when it loses.

Policy (pure, unit-pinned): on each tick,

- **cache fresh** (age < 10 min, account id matches) → use it, **zero requests**;
- **stale / absent / corrupt / account mismatch** → fetch page 1 live;
  success → **write the cache**, use the list; failure → **throw** (today's
  behavior — fetch-status note, last-good snapshot stands).
- **Empty list** caches fine; an empty inventory is a real answer
  (→ `notConfigured` downstream, as today).
- **A `fetchedAt` in the future** (clock change) reads as stale, never as
  fresh forever. Unit-pinned with the rest of the policy.

Refresh fetches **page 1 only**: dynamic candidates are the top
`min(maxRepoCount+3, 8)` of the pushed-sorted list (`DynamicRepoSelector`,
`ShipBoxSnapshot.swift:491`), always the front, so page 1 always contains
them.

### 3.3 Why the cache cannot hide a dead token — and a regression it would cause

The ≤8 probes (`per_page=1`) still run **every tick** against the cached
candidate set, and they 401 the moment the token dies — the tick fails, the
note names the cause. The cache guards only the repo *list*; the token's
liveness is re-proven every 60s regardless.

**But the error it would report is wrong.** Today a dead token fails in
`inventory()` (401) and the tick is classified `.authOrTarget` — "check your
token". With a fresh cache, `inventory()` is skipped, every probe fails, and
`DynamicRepoSelector.select` answers `[]`; `fetch` then hits its
`guard !repos.isEmpty else { throw GitHubError.notConfigured }`
(`ShipBoxSnapshot.swift:315`) and the tick is classified **`.notConfigured`** —
the exact C1 mistake the multi-repo PRD fixed (`prd.md:310`): telling a user
with a revoked token to go add a repo.

**Fix (design requirement):** `discover` distinguishes "nothing has runs" from
"every probe failed". Candidates empty → `[]` (unchanged). Candidates
non-empty and **every** probe failed → throw the first probe error (the tick
is classified by the real cause). Some probes succeeded → proceed as today
(wave 2's partial-failure policy already names the rest). The probe results
must carry the raw `Result` through the selector boundary for this — the
current `hasRuns: Bool` alone cannot tell a 401 from an empty run list.

### 3.4 The freshness window, stated honestly

A repo that gains Actions *and* rises into the top 8 by push recency is
invisible until the next inventory refresh — at most **10 minutes** (recency
is a good proxy for CI, probe P3, so this is rare). Bounded and accepted.

## 4. Account keying

The cache record carries the resolved `CredentialAccount.id`. All three call
sites hold the account: `DeckAgent/main.swift:205` and `DeckApp/DeckApp.swift:410`
fetch with the resolved credential, and `ShipBoxSettingsView` carries both
`accountID` and the resolved `token` (`DeckApp.swift:2143-2148`) for
`loadInventory()` (`DeckApp.swift:2283`). `HostGitHubLoader.fetch` and
`repoInventory` each gain the account id as a parameter. A mismatch reads as
"no cache" and the next refresh overwrites it. (Without this, account B would
probe account A's repos for up to a TTL — self-correcting in a tick but
rendering repos B can see but didn't choose.)

## 5. Picker and cache interplay

The picker (`repoInventory`) stays **always live** — it is user-initiated and
freshness is what the user is looking at — but its paginated result **writes
the cache** for the selected account, so an active settings session keeps
dynamic mode warm between refreshes. (A user who never opens the picker still
gets the cache from the agent's own refreshes.)

## 6. Shell fit

Pure loader + pure policy in `Shared/`; no widget, settings, agent plumbing or
project.yml changes beyond the two call-site signature updates. Panel
invariants untouched (this feature never renders). One convention respected:
loaders return pure data, stores own persistence — the cache policy is a
pure enum beside `DynamicRepoSelector`, the store an `InventoryCacheStore`
beside `ShipBoxSnapshotStore`.

## 7. Non-goals

- No settings UI (TTL, cap, cache on/off are constants).
- No change to the probe waves, fair-share merge, note wording, or
  `FetchStatus` classification.
- No cache for **runs** — only the inventory. Runs stay fresh per tick by
  design (an 8-row widget's runs are its reason to exist).
- No per-page parallelism on the picker path (pages are serial by definition
  — you can't know the next URL before the current response).
- The >100-repo case is **not verifiable live on this account** (31 repos) —
  accepted, unit-tested only.

## 8. Decisions (from interview, 2026-09-13)

| Decision | Choice |
|---|---|
| Cache TTL | 10 minutes, constant (PRD C2's "every ~10 ticks") |
| Picker | Always live; paginated result writes the cache |
| Account keying | Key by resolved account id; mismatch = no cache |
| Refresh failure | Throw — today's behavior (brief's explicit requirement) |

## 9. Open questions

None — the dig and the interview closed them. (Link-header parsing has a
known-unverifiable-on-this-account caveat, recorded above, not a question.)

## 10. Self-critique (2026-09-13)

### 🔴 C1 — A fresh cache turns a revoked token into "not configured"

The most important finding of the critique. Detailed in §3.3 with the fix:
`discover` must throw the first probe error when every probe failed, or the
tick is misclassified as `.notConfigured` — the C1 mistake from the multi-repo
PRD, reintroduced by the cache. **Fixed in the design; must be unit-pinned**
(probe-results-carry-raw-errors test).

### 🟡 C2 — Silent truncation at the page cap

§3.1 caps the picker at 5 pages. A >500-repo account sees a truncated list
with no explanation — the same class of silent truncation this feature fixes
at 100. Accepted: 500 repos is far beyond any picker use, and the cap is a
safety bound, not a product limit. If it ever bites, the fix is a caption,
not a bigger cap. Recorded so the decision is visible.

### 🟡 C3 — The picker writes a cache it never reads

By decision (§5): the picker stays live, but its result warms the cache for
dynamic mode. Two writers (agent refresh, picker) race benignly: both write
whole files atomically (`AtomicFile`), last writer wins, and every reader
validates version + account before trusting it. No test can pin a race; the
atomicity guarantee is `AtomicFileTests`' existing territory.

### 🟡 C4 — The picker's cache write could feed dynamic mode a collaborator's repos

Found during planning, fixed in §3.2: the picker fetches the default
affiliation while dynamic mode fetches `affiliation=owner`, so the cache
record carries the affiliation and the policy matches it. Without this, a
picker-warmed cache would let dynamic discovery win a collaborator repo —
the exact Q1 decision multi-repo made (`prd.md`, "affiliation=owner only").

### 🟡 C4 — Clock changes could freeze the cache

A `fetchedAt` in the future would make the cache look eternally fresh. Fixed
in the policy: future timestamps read as stale (§3.2), unit-pinned.

### Checked and clean

- **Liveness witnesses untouched** — the snapshot and
  `agent-heartbeat.json` still write every successful tick; the cache changes
  neither.
- **Demo data** — the sidecar is never rendered and the snapshots that are
  rendered get the existing `scripts/demo_data.py` scrub; no new leak.
- **Existing ShipBox tests** — `ShipBoxDiscoveryTests`, `ShipBoxSnapshotTests`,
  `ShipBoxMergeTests`, `ShipBoxSettingsTests` already exist; the new tests
  extend that surface rather than creating a parallel one.