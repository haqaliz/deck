# Understanding: shipbox-inventory-pagination

## What the work is really asking

Two open follow-ups from shipbox-multi-repo, both about the **inventory** —
the `GET /user/repos` repo list ShipBox asks GitHub for:

1. **Pagination.** `repoInventory` (settings picker) and `inventory` (dynamic
   mode) both issue one `per_page=100` request and silently truncate at 100
   repos. Follow the `Link` header's `rel="next"` until exhausted.
2. **Caching.** Dynamic mode re-fetches the full inventory (~154 KB, 2.4s —
   probe P2) every 60s tick. Cache the parsed list in a sidecar file and
   refresh only when the cache is older than a TTL (~10 min ≈ "every ~10
   ticks", PRD C2 note). 22 MB/hr → ~16 MB/hr.

## The loader today (ShipBoxSnapshot.swift)

- `HostGitHubLoader.fetch(settings:token:)` (:302) — dynamic mode calls
  `discover(maxCount:token:)` (:358) → `inventory(token:)` (:385), **one
  request, one page, no Link handling**.
- `repoInventory(token:)` (:374) — settings picker, same one-page shape.
- `DynamicRepoSelector.candidates` (:491) — `prefix(min(maxCount+3, 8))` of the
  pushed-sorted list. Candidates always come from the **front**, so page 1
  always contains them → dynamic mode needs only page 1; **pagination matters
  only for the picker**.
- Probes (≤8 × `per_page=1`, 11.4 KB each) run **every tick regardless** and
  are also the token-freshness guard: a revoked token 401s a probe within one
  tick, so a fresh cache can never hide a dead token.
- Call sites: `DeckAgent/main.swift:205` and `DeckApp/DeckApp.swift:410` —
  both have the resolved `CredentialAccount` in hand (`.id` available).

## The sidecar precedent (exactly this shape)

`OpenCodeSyncStore` (`RemoteOpenCodeSync.swift:169-184`): state in
`DeckSettings.containerDirectory` (`shipbox.json` sibling), `AtomicFile.write`,
version check on load, corrupt → nil → self-heal. Cross-tick state for a
short-lived CLI agent is **only possible on disk** — the agent exits every tick.

## Design decisions to settle in the interview

1. **TTL** — fixed 10 min (PRD's "every ~10 ticks")? Constant, or in settings?
   (No settings changes is a stated goal of the brief — lean constant.)
2. **Account-keyed cache** — the inventory is per-token. A user switching
   GitHub accounts could otherwise serve account A's list to B for up to TTL
   (B probes A's repos; self-corrects in a tick, but keying by account id is
   cheap — both call sites have `credential.id`).
3. **Picker** — always live (user-initiated, freshness matters), or reuse a
   fresh cache? Lean always-live, but it should *write* the cache so an active
   settings session keeps dynamic mode warm.
4. **Page cap** — a safety bound on the picker's pagination (e.g. 5 pages =
   500 repos) so a giant account can't stall the settings window.
5. **Refresh failure** — must throw (today's behavior: fetch-status note, last-
   good snapshot stands). Brief is explicit.
6. **Cache-write on refresh** — refresh = page 1 only (candidates are the
   front); the cache stores page 1. Empty list caches fine (→ `notConfigured`).
7. **Link parsing safety** — follow only same-origin `api.github.com` `rel="next"`
   (the Link header is data from the network; the token rides the request).

## Files

- `native/Shared/ShipBoxSnapshot.swift` — loader changes (+ Link parser,
  inventory cache store + policy; or a new `ShipBoxInventoryCore.swift` —
  codebase splits pure core files per widget, e.g. `MarketBoxCore.swift`).
- `native/SharedTests/` — Link parser, cache policy, pagination driver tests +
  fixtures. No fixtures dir for ShipBox yet? (SharedTests/Fixtures exists.)
- No changes: widgets, settings, project.yml, agent/app refresh logic beyond
  the two `fetch` call sites (signature: pass account id).

## Risks / open questions

- Pagination is **unverifiable live on this account** (31 repos, no Link
  header — probe P2) → unit tests are the only verification; observe no extra
  request on the live tick.
- The cached list can hide a repo that gained Actions AND rose into the top 8
  within the TTL window (bounded, ~10 min, recency proxy makes it rare).