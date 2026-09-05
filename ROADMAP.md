# Deck Roadmap

Small, beautiful macOS desktop widgets that behave like native ones. The
product value is **one WidgetKit extension** (fourteen widgets in the Widget
Center) plus **one metric story per widget**. New widgets reuse the widget
shell and only add a data source + a layout.

## The widget blueprint (how to add a widget)

1. **Copy a widget**: `native/DeckWidgets/<Widget>Widget.swift` (start from
   GitBox or NetBox) + register it in `DeckWidgets/DeckWidgets.swift`.
2. **Data source**: sandbox-safe loaders (mach, getifaddrs, IOKit) run inside
   the widget; anything else (subprocesses, other apps' data) goes through the
   agent: add a snapshot model + store in `native/Shared/`, sample it in
   `DeckAgent/main.swift`, render from the store in the widget.
3. **Settings**: add a `<Widget>Settings` struct to `Shared/DeckSettings.swift`
   and a tab in `DeckApp/DeckApp.swift`. Settings live in the app only.
4. **Register**: README.md, ROADMAP.md, `DeckWidgets/DeckWidgets.swift`.
5. **Verify**: build + install, re-add from the gallery, check all three sizes.
6. **Plan artifacts**: `docs/planning/{slug}/prd.md` → `plan_*.md` via the
   `deck-prd` / `deck-plan` skills. Pick the next item with `deck-next`.

## Milestones

### M1 — Foundation (DONE)
- [x] LiveBox (CPU/MEM/DISK chart + top processes, CPU/MEM tabs)
- [x] OpenBox (opencode tokens: in/out/cost, 14-day chart, top models parsed)
- [x] Native WidgetKit project building with automatic signing
- [x] Repo: deck, CLAUDE.md, skills, README

### M2 — Native Deck (DONE)
- [x] Deck app + extension registered in the Widget Center (`pluginkit`)
- [x] All five widgets in one bundle, small/medium/large sizes
- [x] Agent pump (`DeckAgent` CLI + LaunchAgent): opencode snapshot, process
      list, git snapshot — silent, embedded in Deck.app
- [x] Settings window in Deck.app (tabs per widget, colors, counts, token/URL,
      repo paths) applied to widgets instantly
- [x] OpenBox remote server mode (token + URL → HTTP metrics)
- [x] Non-native window widgets removed — Widget Center is the only surface

### M3 — More widgets (DONE — candidate list exhausted)
- [x] **NetBox** — network: up/down rates + history, interfaces
- [x] **BatBox** — battery: level, time remaining, charge state, plus
      Bluetooth accessory batteries (IOKit accessory power sources, SPI)
- [x] **GitBox** — git activity: today + streak, 14-day chart, active repos
- [x] **DevBox** — open ports/processes, Docker containers (docker stats)
- [x] **ClipBox** — clipboard history with previews (local only)
- [x] **WeatherBox** — weather (wttr.in); was HomeBox before the clock split
- [x] **ClockBox** — world clocks, up to 6 cities (no data path at all)
- [x] **ShipBox** — build/deploy status: GitHub Actions runs for a repo

### M4 — Polish
- [x] Crash/robustness pass: atomic snapshot writes (unique temp + rename),
      single writer for processes.json (fast agent owns it; host app and full
      agent no longer write it), agent OSLog diagnostics (`com.deck.agent`),
      soak harness `scripts/soak.sh` + 24h runbook
      (`docs/planning/crash-robustness-pass/runbook-24h.md`)
- [x] Settings schema migration (tolerant decode for all settings structs)
- [x] Tests: XCTest target for the Shared parsers (GitLogParser, ModelParser,
      formatters, DB SQL) — `DeckSharedTests`, runs on CI
- [x] Share the agent data path for LiveBox processes on a tighter cadence
      (`com.deck.agent.processes` LaunchAgent at the process refresh interval,
      default 15s; the widget tick, staleness guard, and history window follow
      the same interval)
- [x] Agent-fetched widgets say *why* a fetch failed (ShipBox / WeatherBox /
      OpenBox remote): the agent classifies each loader's typed error into four
      coarse outcomes (not configured / auth or target / unreachable / bad
      response) and records them per source in `fetch-{source}.json`; the
      widgets render one short reason line, and each widget's settings tab
      repeats it as a full sentence under the fields that cause it (token,
      repo, server URL, location), cleared as soon as those fields change.
      **Behaviour change:** these three
      no longer blank data on age — a snapshot that exists is always rendered
      with its timestamp, and a silent agent gets its own "Agent hasn't run"
      wording. Also removed the dead OpenBox "Refresh interval" stepper (the
      settings key stays, tolerantly decoded).
      Follow-up from `docs/planning/shipbox/prd.md:118` (ShipBox multi-repo)
      shipped 2026-08-25 — see M6.
- [x] Dev builds no longer break widget rendering: derived data lives in
      `native/build.noindex` so Spotlight/LaunchServices never registers
      throwaway copies of `com.deck.app` (stale registrations made WidgetKit
      reject every render — all widgets fell back to placeholders);
      `scripts/lsclean.sh` repairs an already-polluted LaunchServices DB

Deferred from the tests milestone (all covered as of v1.10):
- SystemMetrics per-core math is now in `Shared/SystemMetricsCore.swift` and
  covered by `DeckSharedTests` (`SystemMetricsCoreTests`), along with the
  DevBox parsers, `RemoteOpenCodeLoader` aggregation, `ProcessSnapshot`
  parsing, and `BatteryMetrics` formatters — see `deferred-parser-tests`.

### M5 — New widgets (candidates, pick via deck-next)

Widgets come before improvements: M3's candidate list is exhausted, so this is
the next slate. Ordered by priority, not by cost.

- [x] **CalBox** — calendar: two sections, TODAY and TOMORROW, each with its
      own show/hide and row count. **Route: EventKit** (shipped).

      *Correction to this file's earlier caveat.* It recorded that
      `~/Library/Calendars/` was "empty on the dev machine — no account is
      configured today". That was wrong: the directory is TCC-protected, and
      `ls` reporting `Operation not permitted` was misread as absence. A signed
      EventKit probe returned `granted: true`, **11 calendars**, 61 events in
      7 days — including the Google account `aliz@foresightanalytics.ca`
      synced through Internet Accounts. Routes 2 (secret ICS URL) and 3
      (Google OAuth) were dropped: EventKit sees *more* than the ICS route
      (which reaches one calendar and is cached by Google for hours) at a
      fraction of OAuth's cost. **Do not re-litigate the transport** without
      new evidence.

      The shell caveat was real and is resolved: `DeckAgent` is `type: tool`
      with no Info.plist, so it now carries
      `NSCalendarsFullAccessUsageDescription` in a `__TEXT,__info_plist`
      section (`CREATE_INFOPLIST_SECTION_IN_BINARY`, project.yml). Verified
      under launchd, not just from a terminal, so the grant belongs to
      `com.deck.agent` rather than to a parent process. Deck and DeckAgent are
      separately signed and therefore need one TCC grant each.

      Design notes worth keeping (`docs/planning/calbox/`):
      - Calendars default on by `allowsContentModifications`, not by title —
        a `"Holidays…"` prefix match is locale-fragile, and `sourceType` /
        `isSubscribed` miss holiday calendars delivered as plain CalDAV.
      - Recurring occurrences share one `eventIdentifier` (17 events → 10 ids
        on this machine), so ids are keyed by occurrence.
      - **The countdown was removed after review.** The face led with a live
        `Text(_:style: .timer)` under an unlabelled block: the block read as
        belonging to nothing, and the countdown restated what the row beneath
        it already said. With it went `NextEvent` (which picked what to count
        down to, including a 90-minute in-progress grace rule) and `Countdown`
        (which worded it) — deleted rather than left as unused tested code.
      - **One timeline entry, like every other Deck widget.** An earlier
        version emitted an entry at each event boundary so the countdown could
        roll over exactly; that archived 24 full views into a 1.4 MB timeline
        (24x TaskBox's), which WidgetKit accepted and then drew as an empty
        widget. Watch archive size under
        `~/Library/Containers/com.deck.app.widgets/Data/SystemData/com.apple.chrono/timelines/`
        when a widget renders blank — it is a fast tell.
- [x] **TaskBox** — tasks: due/overdue counts + the next few items.
      Shipped 2026-08-22 (`docs/planning/taskbox/`). Azure DevOps only, via
      WIQL `[System.AssignedTo] = @Me` → `workitemsbatch` (with
      `errorPolicy: omit`) → team iterations, PAT over Basic auth. The
      snapshot is provider-agnostic (`TaskItem` with a String `id` and a
      `provider`), so a second provider extends the enum rather than
      migrating the store.
      **Verified against the live org on 2026-08-22** (org `ForesightAnalytics`,
      project `ForesightManifold`) — the earlier "never tested against a real
      API" caveat is closed, and testing it changed the design:
      - **Due dates were removed entirely.** `DueDate`/`TargetDate` are sparse,
        and the sprint-end fallback gave every item in a sprint the same date.
        The face now shows board lanes instead.
      - **Cross-project leak fixed.** A project-scoped WIQL *URL* does not
        filter by project — the clause `[System.TeamProject] = @project` is
        required. Without it the dev org returned 67 items across three
        projects instead of the 25 in the configured one. Worth remembering
        for any future WIQL.
      - **`System.BoardColumn` is not usable** as a lane source: null on 24 of
        50 sampled items, and reads `Doing` where the board header says
        `In Progress`. States are stored raw and mapped at render time, with
        the mapping editable in settings.
      - **The WIQL exclusion list is narrower than it looks.** It drops
        `Closed`, `Removed` and `Done` but not `Resolved` or `Completed`, so a
        team using those words really does receive finished items. TaskBox
        gives them a `done` lane (checked before the open lanes) and renders
        them struck through rather than letting them read as outstanding.
      **Open follow-ups:** multi-org, custom WIQL, a second provider.
      (Multi-project shipped 2026-08-28, see M6; Keychain shipped 2026-08-26.)
- [x] **PRBox** — review queue: your open PRs + PRs awaiting your review,
      **mixed from GitHub and Azure DevOps Git** in one list (the original
      entry scoped this to GitHub only). Shipped 2026-08-24
      (`docs/planning/prbox/`). Per-provider settings sub-tabs, each with its
      own include toggle, credentials and `FetchSource` key; the face names
      the provider whose pull requests are missing when one half fails.
      **Probed live before the PRD was written, which reshaped it three times:**
      - **Azure's Git PR API silently ignores an unparseable identity.** There
        is no `@Me` macro; `creatorId=@me` returns 200 and *every active PR in
        the project* (6 / 6 / 0 for none / `@me` / unknown GUID). The loader
        resolves the id from `_apis/connectionData` and fails rather than
        falling back — an unfiltered query looks exactly like a working one.
      - **Azure PRs carry no update timestamp**, only `creationDate`, so both
        providers sort by creation date. Sorting GitHub by `updated_at` would
        sink a freshly-pushed Azure PR below a stale GitHub one.
      - **`reviewerId` returns PRs you already voted on**, while GitHub drops
        them from `review-requested`. Filtered to `vote == 0` so one list means
        one thing.
      Also: Azure reports no total for a PR query (hence `$top=101` and a
      "100+" ceiling), the project-level endpoint spans every repo in the
      project (no per-repo fan-out), and GitHub search allows 30 req/min
      against 2 calls per tick.
      Rows are clickable (the first Deck widget to deep-link): medium and
      large link per row, the small face carries a `widgetURL` to the top pull
      request. Restricted to http(s) with a host — the snapshot is data, not
      instruction.
      **Review state shipped 2026-09-02** (`docs/planning/prbox-review-state/`):
      each row carries a coarse `✓`/`✗` glyph — someone else approved /
      someone is asking for changes, never your own vote — with a
      **Show review state** toggle (default ON) that also gates the GitHub
      per-PR fetches. Probed live, and the probe settled the two open
      questions:
      - **Azure needs zero extra requests.** `reviewers[]` with `vote` values
        (+5/+10 approved, −5/−10 changes requested) is already in the
        `pullrequests` payload the loader parses; the fold excludes the PAT
        owner, whose own `+10` rides authored rows and must not read as
        "approved".
      - **GitHub is one request per PR, and the original non-goal's arithmetic
        was too pessimistic.** The 30/min budget is for the *search* API; the
        reviews endpoint is core (5000/hr). Measured: 6 PRs = 6.31s serial,
        **1.09s concurrent** — the fan-out reuses `withThrowingTaskGroup`, and
        the probe set is capped to the provider's own newest `prCount` rows
        (the only ones that can render). A per-PR failure is a row without a
        glyph, never a failed tick.
      **Open follow-ups:** multi-org, a third provider. (Multi-project shipped
      2026-08-28, see M6; Keychain shipped 2026-08-26.)
- [x] **MarketBox** — configured tickers/crypto: price, day change, sparkline.
      Shipped 2026-08-24 (`docs/planning/marketbox/`), and the interview grew
      it past the ROADMAP entry: **mixed assets** (crypto + fiat + gold 1g) all
      priced in **one global display currency** — USD, IRR or IRT (Toman =
      IRR ÷ 10) — at the **free-market** rate. Four keyless providers, each
      probed live before the PRD:
      - **CoinGecko** (crypto price + 24h % + 7-day sparkline; free tier has
        no `irr`/`irt` vs_currency, so the conversion is done client-side);
      - **Wallex** `USDTTMN` (the free-market Toman anchor — an Iranian
        exchange's order book, 201k Toman per USDT vs open.er-api's 152k);
      - **gold-api** (XAU spot → per gram ÷ 31.1035);
      - **open.er-api** (fiat cross-rates, e.g. CAD).
      **priceto.day was rejected after a live probe**: it serves a Cloudflare
      JS challenge to non-browser clients (error 1015) — DeckAgent's plain
      URLSession cannot solve it. CryptoCompare now demands an API key
      (CoinDesk takeover). Yahoo works for GC=F/CAD=X but is a flaky
      unofficial scrape, so **fiat/gold rows are price-only in v1** — no 24h %
      or sparkline for them until a free no-key history source appears.
      Unknown symbols are surfaced (`Unknown: XRPX`), the snapshot stores the
      currency it converted for (the header never mislabels a mid-tick
      settings change), and a single fetch-status key covers four providers:
      the loader only fails when *no* row at all could be priced; partial
      results render with a note. Sparklines are downsampled to 30 points in
      the loader (the CalBox archive-size lesson).
      **Layout (user revision 2026-08-24):** small = up to 4 rows **price-only**
      (no day change); medium = up to 5 rows with the 24h change; large = up to
      12 rows (the `tickerCount` setting). **Display currency is a list, not a
      toggle** — USD, IRR, IRT (Toman, free-market), CAD, EUR and AED (live FX
      rate); the converter multiplies by the Wallex Toman anchor or the
      open.er-api rate depending on the pick. **Sparklines were dropped by user
      decision** — the first face drew them with Swift Charts, which made
      WidgetKit **silently drop the widget from the gallery** (the Charts-in-a-
      widget-face trap, see CLAUDE.md); the user then removed the sparkline
      requirement entirely, and the loader no longer asks CoinGecko for the
      series. Tickers are **picked, not typed** — a blind-typed symbol was
      unknowable to the user; the old `symbols` string migrates to `tickers`.
      *(As shipped this was a curated list behind twelve slot pickers, the
      ClockBox pattern; superseded by the live lookup below, which kept the
      "picked, not typed" rule and replaced the fixed list.)*
      **Live coin lookup shipped 2026-09-05**
      (`docs/planning/marketbox-coin-lookup/`): settings hold the CoinGecko
      **id**, not a bare symbol, so the agent stops resolving through a
      hand-written table and the catalogue opens from 43 coins to all of them.
      The twelve numbered slots become an add/remove list with an **Add
      Ticker…** search sheet. **Probed live first, and the probe rewrote the
      plan four times:**
      - **`/coins/list` — the endpoint this entry named — is the wrong one.**
        1.24 MB, 19,594 coins, `{id, symbol, name}` with no rank, and **2,396
        of 15,090 distinct symbols map to more than one coin** (`BTC` is 11,
        `PEPE` 21, `GOLD` 9; alphabetically `batcat` precedes `bitcoin`).
        Picking by symbol over it recreates the blind-typed-symbol problem the
        curated list was introduced to kill.
      - **`/search?query=` is the right one:** 10.5 KB, keyless, server-side,
        already market-cap ordered, and carrying the `market_cap_rank` that
        makes a choice possible. `/coins/markets?per_page=250` works (197 KB)
        but is unnecessary — the curated 43 serve the empty-query state for
        free and offline, which is all that map is still for.
      - **The rate limit is shared with the agent and bit during the probe:**
        six requests in ~2 minutes returned **429 with `retry-after: 55`**,
        while the agent already spends up to 4 calls per 60s tick on the same
        public IP. A keystroke-per-request picker would blank MarketBox while
        the user was choosing a ticker. Hence a 600 ms debounce, a 2 s floor, a
        per-query cache, host-app-only execution, and a 429 that degrades the
        sheet and can never fail a tick.
      - **CoinGecko drops an unknown id silently** — `ids=bitcoin,not-a-coin`
        answers 200 with one row, and an **empty `ids=` answers 200 with the
        top 100 coins (83.6 KB)**, which would render as the user's own list.
        So the builder now separates "the source is down" (`Crypto
        unavailable`) from "this coin has no data" (`No data: X`), and the
        empty-ids request is guarded twice.
      Two things the self-critique caught that the PRD had wrong: keyed on
      symbols the whole feature would have rendered `Unknown: PURPE` for every
      new coin (the curated table answers nil outside its 43), and a duplicate
      symbol would have been dropped silently — the face draws `Text(row.symbol)`
      alone, so one symbol means one row, refused out loud.
      **Fixed in passing:** `MarketPriceFormatter` fell through to `%.4f` below
      1.0, so **SHIB, PEPE and BONK — all three already in the shipped curated
      list — rendered as `$0.0000` in v1.39**, and a 50% move looked identical
      to no move. Sub-cent prices now use significant digits.
      **Open follow-ups:** fiat/gold 24h % + sparklines (needs a history
      source), stocks/indices, the Toman rate's own 24h change on the USD row
      (Wallex `24h_ch`, already parsed).
- [x] **BlueBox** — peripheral battery (AirPods, Magic Mouse/Keyboard).
      **Already shipped inside BatBox** (`542c893`,
      `docs/planning/batbox-accessories/`) and ticked in M3; this entry was
      stale. The caveat it recorded — that `system_profiler` and
      `ioreg -r -k BatteryPercent` return no battery keys — is the *disproven
      draft*, not the outcome: the spike found `IOPSCopyPowerSourcesByType(4)`,
      an SPI bound with `@_silgen_name`. See the CLAUDE.md note.

Rejected with a recorded blocker (do not re-recommend):
- **MusicBox / now-playing** — MediaRemote is entitlement-gated as of
  macOS 15.4; the AppleScript fallback only sees Music.app, not Spotify or
  browsers.
- **TempBox / fan + sensor temps** — SMC sensors need private API on Apple
  Silicon, the same family as the GPU/ANE blocker
  (`docs/planning/livebox-per-core-cpu/prd.md:94`). `ProcessInfo.thermalState`
  already shipped as the sanctioned proxy.
- **MailBox** — Full Disk Access plus Mail's undocumented Envelope Index
  schema; fragile across OS updates.

### M6 — Improvements (after M5)

Deferred behind the new widgets by decision on 2026-08-22.

- [x] **ShipBox multi-repo** — up to five repos merged into one newest-first
      list, with two ways to choose them: **Automatic** (default; the repos you
      pushed to most recently that have runs) and **Pick repos** (five slot
      pickers over the repos the token can see). Shipped 2026-08-25
      (`docs/planning/shipbox-multi-repo/`).
      **Probed live before the PRD, and three findings changed the design:**
      - **Nothing in a repo object says whether it has Actions.** No field
        matches `workflow`/`action`, and only **7 of 19** owned repos had any
        runs — so automatic mode cannot know which repos have CI without
        asking each one. It probes candidates (wanted + 3, capped at 8) at
        `per_page=1` and fetches in full only the winners. Recency predicts CI
        well but not perfectly: the first repo without runs was the 7th by
        push date, which is what sizes the buffer.
      - **Serial fan-out does not fit the tick.** Five repos measured **9.4s**
        serially against **2.1s** concurrently, and with the 10s per-request
        timeout the serial worst case runs past the 60s cadence. This is the
        codebase's **first `withThrowingTaskGroup`**; every other loader
        awaits its sources one after another.
      - **A run object embeds the entire repository object** — ~11.4 KB *per
        run* (`per_page=1` → 11.4 KB, `per_page=8` → 91.6 KB). Fetching every
        candidate in full would have cost ~45 MB/hour for a widget that shows
        eight rows; the two-wave probe halves it.
      Rate limits turned out not to be the constraint at all (5000/hr core
      against ~360 calls/hr), which is the opposite of what this entry assumed.
      The `FetchStatusStore` question resolved to **keep one `.shipbox` key**
      and carry per-repo detail in the snapshot's `note`, MarketBox's
      one-key/several-providers precedent. Two honesty fixes came out of the
      PRD's own critique: a failed *inventory* call is classified as itself and
      never as "not configured" (it would tell a user with a revoked token to
      go add a repo), and on the small face a non-zero fail count now outranks
      the fetch chip — the old precedence could render two green rows while
      another repo was red.
      **Open follow-ups:** inventory pagination past 100 repos, caching the
      discovered set across ticks (~16 MB/hr instead of ~22).
      **Fair share shipped 2026-09-05** (`docs/planning/shipbox-fair-share/`):
      a busy repo can no longer crowd out a quiet one. `ShipBoxMerge.fairMerge`
      interleaves the merged list round-robin — each repo's newest run lands
      in the first `repoCount` rows, the first element stays the globally
      newest run (so the small face's link target is unchanged), and the
      toggle **Fair share across repos** (default ON) returns the list to
      strictly newest-first. Pure policy, unit-pinned; the existing
      `per_page = max(runCount, 2)` provably suffices. This retires the
      multi-repo PRD's "no fair share" non-goal (`prd.md:190-191`).
- [x] **OpenBox remote incremental sync** — `limit`-based sync instead of a full
      resync each tick (`docs/planning/openbox-remote/prd.md:105`). Shipped
      2026-08-27 (`docs/planning/openbox-remote-incremental-sync/`).
      The agent carries a per-session watermark + a parts-free 13-day message
      archive in an agent-only sidecar (`opencode-cursor.json`): idle ticks are
      one `GET /session` and zero message fetches (per-session `time.updated`
      skip), changed sessions page `limit=100` + `before` cursors newest-first
      until caught up, and the existing aggregator rebuilds the snapshot from
      archive + new messages — all decisions pure and unit-pinned
      (`RemoteOpenCodeSync`, `DeckSharedTests`). Servers that ignore `limit`
      or `before` are detected on the fly (over-full page / identical page)
      and fall back to today's behavior, so no live probe was needed. In
      passing, the loader now decodes both `/session/{id}/message` shapes —
      the `[{info, parts}]` envelopes it was built against and the flat
      `[...info, parts]` arrays current servers serve. Dormant on the dev
      machine until an opencode account carries a `serverURL` (both are empty
      today); the first tick after upgrade does one full resync, then
      incremental forever after.
- [x] **Azure DevOps multi-project** — one account covers up to five projects
      in its organization, for **both** TaskBox and PRBox (each listed it as an
      open follow-up). Shipped 2026-08-28 (`docs/planning/azure-multi-project/`).
      `CredentialAccount.project` became `projects`; the account editor lists
      what the PAT can see (`_apis/projects`) behind five slots and falls back
      to typed names when the token cannot list them.
      **Probed live first, and the probe corrected the plan twice:** this org
      has **six** projects, not the two the brief assumed — there is no
      `Manifold`, the neighbour is **`Manifold Ops`**, whose space exercises URL
      encoding on the live path. Measured after: **25 items in
      ForesightManifold, 42 in ForesightDevops, 0 in Manifold Ops** — 67 in
      total, which is exactly the "67 across three projects" the TaskBox entry
      recorded as the cost of the single-project scope. All 67 now render.
      Three findings shaped the implementation:
      - **Cost is sublinear.** `workitemsbatch` and `connectionData` are
        organization-scoped while WIQL and the PR query are project-scoped, so
        TaskBox is N+1 requests and PRBox is 2N+1 — not 3N. The per-project
        calls fan out with `withThrowingTaskGroup`, the second use of that
        pattern after ShipBox.
      - **PRBox row ids collided across projects.** `azureDevOps:{repo}#{n}`
        is not unique: PR numbers are per repo and a repo name is only unique
        within its project, so two projects with an `api` repo shared one id —
        a duplicate `ForEach` key and a silently dropped row. The project is
        now part of the id, and the regression test asserts on
        `Set(ids).count`.
      - **A merged batch needs `System.TeamProject`.** Every row's URL was
        built from the queried project, so one organization-scoped batch would
        have deep-linked every row into whichever project came first.
      Partial failure follows MarketBox: some projects is an answer with a note
      naming the ones that failed, none throws and the last good snapshot
      stands (verified by an unchanged file mtime). The sprint chip shows only
      with exactly one project, since a current sprint is per project and team.
      **Open follow-ups:** multi-org (needs a slot that binds several accounts,
      interviewed and deliberately not chosen), review state / approval counts,
      custom WIQL, raising the five-project cap (one constant — this org has
      six).
- [ ] **DevBox process hide toggle** — deferred as a fuzzy heuristic
      (`docs/planning/devbox/prd.md:106`).

### M7 — Launch readiness (distribution, not features)

Deck is feature-complete for a public launch; what is missing is everything
around the binary. Ordered by what blocks what.

**Everything gated on the paid Apple Developer Program has a step-by-step
runbook: [`docs/planning/notarization/runbook.md`](docs/planning/notarization/runbook.md)** —
enrollment choice, certificate, project settings, the two-pass notarize/staple
in CI, the verification gates, and what the identity change resets.

- [x] **DMG releases.** `Deck-<tag>.dmg` (app + `/Applications` symlink) with
      `SHA256SUMS.txt` and install instructions, replacing `Deck-macos.zip`.
- [x] **Repo hygiene.** Apache-2.0 `LICENSE` + `NOTICE`, `CONTRIBUTING.md`,
      `CODE_OF_CONDUCT.md`, issue/PR templates, README badges, GitHub
      description and topics.
- [x] **ClipBox no longer records secrets.** Copies marked
      `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType`
      (what every password manager sets) are dropped instead of written to
      `clipbox.json` and drawn on the desktop.
- [x] **`get-task-allow` out of Release builds**
      (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`). It shipped in every release
      up to v1.19, letting any local process debug the app that holds the
      calendar grant, the clipboard history and three API tokens.
- [x] **`settings.json` is 0600**, and agent logs moved from world-writable
      `/tmp` to `~/Library/Logs/Deck` (0700).
- [x] **Uninstall is a button** (General tab): remove the agents, erase the
      data. The container itself is deliberately never deleted.
- [x] **Homebrew cask** (`homebrew/deck.rb` → tap `haqaliz/homebrew-deck`).
      The `xattr -dr com.apple.quarantine` line in the caveats is what users
      need until notarization lands — and it must run **before** the first
      launch, because a quarantined launch makes Gatekeeper *delete* the app.
      This entry used to credit `--no-quarantine`; Homebrew removed that flag,
      and `README.md` and `homebrew/deck.rb` were corrected while this was
      still telling readers to use an uncommand.
- [x] **Screenshot pipeline** — `scripts/demo-data.sh` sanitizes the snapshots
      in place so the widgets can be captured without publishing real calendar
      entries, work items, clipboard contents or repo paths.
- [ ] **Verify on a second Mac.** The one unproven assumption in the whole free
      distribution path: that `pluginkit` registers a development-signed
      extension on a machine outside the signing team. Test before announcing
      anywhere.
- [ ] **Notarization** — needs the paid Apple Developer Program. Developer ID
      Application certificate, `notarytool submit --wait` + `stapler staple` in
      the release job, drop `-allowProvisioningDeviceRegistration`. This also
      removes the hard expiry below. Full runbook:
      [`docs/planning/notarization/runbook.md`](docs/planning/notarization/runbook.md).
      **Hardened runtime is no longer part of this** — it shipped in v1.41 under
      the existing identity (see below), so the paid day changes the certificate
      and only the certificate.
- [x] **Hardened runtime, landed early** — shipped v1.41, 2026-09-06
      (`docs/planning/hardened-runtime-preflight/`). `ENABLE_HARDENED_RUNTIME`
      was `NO` on DeckApp and DeckWidgets and **absent entirely on DeckAgent**,
      which is one of the two causes the runbook names for a first `Invalid`
      notarization; absent and `NO` look different in the file and identical in
      the product. All three now declare it, a unit guard enumerates the targets
      out of `project.yml` (so a target added later fails the suite rather than
      shipping unhardened), and the release job refuses to package a build whose
      binaries do not report `runtime`.
      **Done now, separately, on purpose.** The notarization release changes the
      identity, the runtime flag, the CI flags and — by decision — the bundle
      id, all at once; it resets every user's TCC grants, forces every user to
      re-add their widgets, and its rollback is documented as not symmetric. One
      of those four variables can be spent while a rollback is still `cp -R` of
      the previous build, so it was.
      **Measured on a real install rather than assumed**
      (`verification.md`): all three binaries `flags=0x10000(runtime)`;
      **no exception entitlement needed** (the app still carries none at all, so
      Deck runs hardened with library validation on); both agents tick; `ps`,
      `docker` and `git` all still spawn; the sandboxed extension launches and
      chronod schedules all fourteen widget kinds; AMFI logs nothing.
      Three findings worth keeping:
      - **TCC grants survive a re-signature under an unchanged identity.** Six
        calendar events read, no prompt. So when grants reset on the Developer
        ID release, the *identity* is the reason — not the runtime flag.
      - **chronod's failed reloads are pre-existing.** 11.3% of reloads failed
        before the change and 11.1% after; they are stale `HomeBoxWidget`
        timeline archives (`CHSErrorDomain 1100`) left from the HomeBox →
        WeatherBox/ClockBox split, plus three `1103`s. A count taken only after
        a change would have read as damage.
      - **`log show` without `--info --debug` returns nothing for Deck**, agent
        lines included — so an AMFI query looks identically silent whether or
        not anything happened. The silence was only admitted after a positive
        control proved the log was answering.
- [ ] **The expiry cliff.** Xcode signs development builds with no secure
      timestamp (`Signed Time=`, not `Timestamp=`), so signature validity is
      tied to the certificate: **2027-08-09**, after which every copy of Deck
      in the world stops launching. A Developer ID signature is timestamped and
      survives. This is the real reason to buy the program, more than the
      notarization ticket itself.
- [ ] **Bundle identifier.** `com.deck.app` / `com.deck.agent` is reverse-DNS
      for a domain nobody owns. Changing it after launch forces every user to
      re-add their widgets and re-grant TCC, so it has to happen before.
      **Prepared but deliberately not applied** (2026-08-29,
      `docs/planning/bundle-identifier/`). The new prefix is
      `io.github.haqaliz.deck` — backed by the account that already hosts the
      repo and the tap, so it is a namespace actually controlled. By decision it
      rides the **notarization** release rather than shipping alone, because
      that already forces the same re-grant (notarization runbook, Step 6); the
      one-line flip and its gate are
      [`flip-runbook.md`](docs/planning/bundle-identifier/flip-runbook.md).
      What shipped now is everything that can ship dormant: `DeckBundle` as the
      single Swift source (pinned by tests against `project.yml`, the generated
      `DeckAgent/Info.plist`, both LaunchAgent plist names and Labels, and
      `scripts/lib/ids.sh` — drift fails the suite), every call site routed
      through it, and `ContainerMigration`, which carries `settings.json` into
      the new container and is inert while the ids match.
      **Probed live on a real renamed build, and three of the plan's own
      predictions were wrong:**
      - **The container needs no help.** containermanagerd provisions the new
        one — full skeleton, metadata plist, home symlinks — at `lsregister`
        time, *before* the app is installed, let alone launched. The migration
        writes into it directly; the feared hand-made-skeleton case cannot
        arise.
      - **The old agent does not run the new binary.** The launchd job records
        the parent bundle *identity* (`parent bundle identifier`,
        `parent bundle version`), not just a path, so replacing the bundle makes
        it fail `78: EX_CONFIG` rather than executing whatever now sits there.
        The default-settings snapshot corruption the plan was designed around
        cannot happen. The migration still runs from both entry points, because
        the agent is registered at login and the app is not.
      - **The orphaned agent records cannot be deleted, only disabled.** The old
        app record is *replaced* and its two agent records are *re-parented to
        the new app*, so Login Items shows four DeckAgent rows, two unrunnable.
        `launchctl bootout` fails (`No such process`) and the new bundle has no
        handle on them, so the flip ships the old-named plists for one release
        purely to `unregister()` them — which flips them to
        `[disabled, allowed]` rather than removing them. Only `sfltool resetbtm`
        removes them, and it wipes every login item on the machine.
      Also measured: **rollback is not symmetric.** Reinstalling the old bundle
      over the new leaves two BTM app records claiming one URL and launchd
      refuses both jobs; the in-app toggle, `kickstart` and restarting `smd` all
      fail, and only a logout/login repairs it.
- [x] **Agent liveness check** — shipped 2026-08-30
      (`docs/planning/agent-liveness/`). Was the **prerequisite for the bundle
      rename**, and a standing bug found while probing it. `SMAppService.status` answers "is
      there a registration record", not "is the job loaded", and those came
      apart on the dev machine for **6 hours**: BTM `[enabled, allowed]`, the
      toggle on, `launchctl print` reporting no such service, and nothing
      written since 17:51. v1.34's notice cannot catch it — that fires on
      `[enabled, disallowed]` → `.requiresApproval`; this is `.enabled`, so
      `AgentReconcilePolicy` correctly does nothing. It is the third distinct
      way the agents can be down (never registered / user-vetoed /
      registered-but-unloaded) and the only one Deck is blind to.
      **The rename puts every user into exactly this state**, since the new
      agents register only when the renamed app first launches — so this ships
      first or the flip silently stops background refresh for everyone.
      Deck already has the ground truth: `processes.json` has been the fast
      agent's **single writer** since v1.30, so its mtime distinguishes "an
      agent ran" from "the app ran" with no ambiguity — every other snapshot is
      written by both, which is why this went unnoticed for so long. Compare it
      against `processRefreshInterval` while `agentAtLogin` is on and report in
      General beside the Login Items notice. Recovery is the documented toggle
      off→on; it cannot be driven from outside the app, because with the record
      `.enabled` the reconcile policy re-adopts `agentAtLogin: true` from the
      registration and never unregisters — so `settings.json` is not a test seam
      for this.
      **What shipped.** `AgentLivenessPolicy` (pure, in `Shared/RefreshPolicies.swift`
      beside the two policies it belongs with) reads the age of `processes.json`
      — the fast agent's single writer since v1.30 — against
      `max(4 * processRefreshInterval, 120)`, and the General tab draws one
      notice plus a **Restart agents** button when it is stale. `.healthy` and
      `.unknown` draw nothing; silence is the healthy state.
      `DeckSettings.agentsRegisteredAt` is the grace-period clock, so a fresh
      install and the first launch after the rename stay silent.
      **Scope, stated honestly:** the snapshot witnesses only
      `com.deck.agent.processes`. The 60s agent has no unambiguous witness (the
      host app writes everything it writes), so the notice says "background
      refresh has stopped" and never names an agent.
      **Two bugs the work caught, both in itself:**
      - **Keeping the stamp one-time with `guard stored == nil` defeats the
        rename case outright.** `ContainerMigration` carries a non-nil timestamp
        from the old install, so a *fresh* registration would never restart the
        clock and the new container's empty `processes.json` would read as
        "registered ten days ago, never ran" — the notice firing falsely on the
        exact release it exists to protect. The rule has two triggers, not one
        (`AgentRegistrationClock`): registering restarts the clock
        unconditionally; adoption happens only when there is no clock at all.
      - **`JSONEncoder` writes `Date` as seconds since the 2001 reference date**,
        not the Unix epoch. Harmless (same encoder both sides) and confusing to
        anyone reading `settings.json` by hand, so it is pinned by a test.
      **Verified against a real fault, not a synthesized one**
      (`docs/planning/agent-liveness/verification.md`): the dev machine was
      already in the state, undetected, for **38 hours** — a leftover of the
      08-29 rename probe. Two corrections came out of it:
      - **`launchctl print` reported the job as present.** The fault was one
        line down: `last exit code = 78: EX_CONFIG`, `job state = spawn failed`,
        **`runs = 13741`** — thirteen thousand failed spawns at 5s intervals. So
        "registered but not running" has at least two shapes, and a check built
        on `launchctl print` succeeding would have called this one healthy.
      - **"Only a logout/login repairs it" is too strong.** The two-BTM-records
        `EX_CONFIG` state that the rollback note calls logout-only was repaired
        by replacing the bundle and pressing **Restart agents** — the agent
        wrote one second later. Which half did the work is not isolated.
      **The check found its own cause, and it was a shipped bug.**
      `reconcileAgents()` called `legacyCleanup()` on every launch, which
      `launchctl bootout`s the legacy agent labels — and before the rename those
      *are* the current labels. So opening Deck took down the two jobs
      SMAppService was running, and nothing put them back (a bootout leaves the
      registration `.enabled`, so reconciliation correctly does nothing). That
      is the 6-hour silence in the bundle-identifier probe and the 38-hour one
      found here. It went unnoticed because opening Deck is what breaks it *and*
      what makes the data look fresh — the host app pumps every snapshot except
      `processes.json`. Fixed the same day (`LegacyAgentCleanup`, below).
      **Both open follow-ups shipped 2026-08-31** — see the entry below.
- [x] **A heartbeat witness for the 60s agent** — shipped 2026-08-31
      (`docs/planning/agent-heartbeat/`). Closes both follow-ups the liveness
      check left open. The notice could prove only that
      `com.deck.agent.processes` ran; `com.deck.agent` writes ten snapshots and
      the host app writes every one of them, so a dead 60s agent produced **no
      notice at all** while OpenBox, GitBox, TaskBox, CalBox, PRBox, ShipBox,
      WeatherBox and MarketBox went stale — with LiveBox ticking in front of the
      user throughout, which is what made the silence convincing.
      `agent-heartbeat.json` is the 60s agent's own witness, `AgentEvidence`
      gives every witness three answers instead of two (a corrupt file is no
      longer "never ran"), and the notice **names the half that stopped** and
      says what still works.
      **Three decisions worth keeping:**
      - **The witness is a file, not a field on `DeckSettings`.**
        `ContainerMigration` copies only `settings.json`, so a field would land
        in the renamed container holding a timestamp from the old install with
        an agent that has never run there — the exact false positive
        `AgentRegistrationClock` exists to prevent.
      - **It is written at the *start* of the tick.** The full path awaits ~10
        mostly serial sources at 10s timeouts, so an end-write would report a
        slow-but-healthy tick as dead — and catches nothing extra, because
        launchd starts no new tick while one is running.
      - **The upgrade guard is a rule in the policy, not a restart of the grace
        clock.** The clock version was written first and is resettable by
        relaunching Deck: a user who reopens the window every few minutes would
        never see the notice. `.never` from a witness while the *other* agent is
        demonstrably alive is treated as ambiguous instead — which also covers
        the release that introduces the witness, where every upgraded install
        finds it absent.
      **Measured live, and the fault reproduced rather than synthesized:** the
      upgrade case was checked against a real 8.9-hour-old registration with the
      fast agent writing 11 seconds earlier; a `bootout` of the 60s agent alone
      froze the heartbeat while `processes.json` advanced every ~35s for five
      minutes; and a Deck relaunch did not reset the verdict. Also measured: a
      real agent tick is **~68s**, not 60.
      **The notice was captured rendering** for three of its four shapes
      (data-agent down, process-agent down, corrupt witness), each against a real
      booted-out agent, with the toggle left on throughout and **Restart agents**
      repairing it twice. Both-down was not captured: with both agents out the
      fast one came back on its own, so the state at capture really was
      "60s down, fast healthy" and the notice was right about it. That recovery
      is itself unexplained — `agentsRegisteredAt` was restamped with nothing
      pressed, which points at `reconcileAgents()` running from a window
      re-creation; recorded as an observation, not a conclusion.
      **Open follow-up:** re-add the widgets from the gallery (low risk — the
      extension's own sources are untouched).
- [x] **`legacyCleanup` no longer boots out the running agents** — fixed
      2026-08-30, the cause of everything the liveness check detects. The
      cleanup now acts only on labels whose `~/Library/LaunchAgents/<label>.plist`
      actually exists: a ≤1.32 install has one and its stale bootstrap really
      does collide with the SMAppService registration over the same label; a
      v1.33+ install has none and needed nothing done to it. Verified on the
      installed copy (the only place SMAppService registers) — before, a single
      quit/relaunch killed both jobs permanently; after, three cycles left them
      alive with the snapshot advancing throughout. The residual case (a plist
      alongside an already-`.enabled` registration) is unreachable in practice
      and is no longer silent if it ever happens, because the liveness notice
      reports it.
- [x] **Keychain for the credentials** — shipped 2026-08-26
      (`docs/planning/keychain-tokens/`). **Five** tokens, not the three this
      entry used to claim: OpenBox, ShipBox, TaskBox, and PRBox's separate
      GitHub and Azure tokens (it predated PRBox shipping two). Migrated one
      way on first launch — write, read back to confirm, *then* blank the
      file — so a keychain failure can never cost the only copy of a token.
      **Probed live before the PRD, and every finding changed the design:**
      - **The feared per-binary ACL prompt does not exist.** A bare tool signed
        like `DeckAgent` reads an item written by the bundled app **inside a
        launchd job, with no prompt**, even with the auth UI suppressed.
        Confirmed in production: with Deck.app not running, one agent tick
        refreshed ShipBox, TaskBox and both PRBox providers, all `ok`.
      - **The presumed fix is fatal.** Signing either binary with a
        `keychain-access-groups` entitlement **SIGKILLs it at launch** (exit
        137, no crash report) — there is no provisioning profile to authorise
        it, and a `type: tool` target has nowhere to embed one. The data
        protection keychain refuses to write without that entitlement
        (`-34018`). Deck uses the legacy login keychain, which needs no
        entitlement at all. See the CLAUDE.md trap.
      - **It buys confidentiality at rest, not process isolation.** An
        ad-hoc-signed binary and `/usr/bin/security` both read a probe item
        with no prompt, and still did against an item written with an explicit
        `SecAccess` trusting only two named binaries. The README says so
        plainly rather than implying the tokens are now safe from other local
        software.
      A locked keychain gets its own `FetchOutcome` (`credentialsUnavailable`)
      instead of reading as "not configured" — telling someone to paste a token
      they already pasted is the ShipBox C1 mistake. **That path is designed
      and unit-tested but never exercised against a genuinely locked
      keychain**: locking the dev machine's login keychain would have left
      unlock prompts across other apps that could not be undone without the
      user's password.
      **Open follow-ups:** exercise the locked-keychain path on a scratch
      account; revisit access groups if Deck ever gains a provisioning
      profile.
- [x] **Credentials tab: typed accounts** — shipped 2026-08-26
      (`docs/planning/credentials/`). Credentials stop being a property of a
      widget and become records widgets reference by id. Many accounts per kind
      (github / azure / opencode), each with its own connection identity; every
      widget tab picks one from a kind-filtered dropdown, so switching between
      two opencode servers is a selection rather than a re-paste, and ShipBox
      and PRBox can share one GitHub token instead of holding two copies.
      Decisions taken with the user: per-widget picker with no global default;
      the account owns its connection fields (Azure org **and** project,
      opencode server URL); no inline token fields on widget tabs; a manual
      Verify per account; migration auto-creates accounts and dedupes identical
      tokens; PRBox's picker replaces its Include toggles; deleting names the
      widgets that break.
      **The self-critique caught five things the PRD had wrong**, and each
      changed the build:
      - **Two reads live inside the widget extension.** `OpenBoxWidget` read
        `serverURL`, `PRBoxWidget` read the two `enabled` flags. Both fields
        move onto accounts, so both would have read empty forever with no
        crash, no log and no chip. See the CLAUDE.md trap.
      - **Migration would have re-enabled a PRBox provider the user switched
        off.** `enabled` defaults to false and a token can sit behind a disabled
        provider; since a selected account now *means* enabled, migrating the
        selection would silently restart a stream they had removed. The account
        is created either way — never lose a token — but not selected.
      - **`DeckSettings.CodingKeys` is hand-written**, so a forgotten case
        compiles, decodes as absent and never encodes. Every account would have
        vanished on the next keystroke. **`ShipBoxSettings` has a hand-written
        `encode(to:)` too** — the same bug, one file over, which the critique
        did not catch and the tests did.
      - **`scrubbedOfSecrets()` was written against five fixed fields.**
        `CredentialAccount.encode(to:)` now omits the token outright *and* the
        scrub loops the accounts: two independent guarantees, because a fixed
        list is auditable by a human and an unbounded one is not.
      - **`Set<DeckSecret>` cannot name a dynamic account**, so the
        locked-keychain distinction is now keyed by account id.
      **The cached Azure identity GUID is display-only.** Verify stores it, but
      `HostAzurePRLoader` keeps resolving identity live per fetch and keeps
      failing closed — a GUID cached against a since-replaced token would render
      the whole team's pull requests as the user's own, and nothing in the
      response says the filter was ignored.
      **The tab is shaped like System Settings' Internet Accounts** (the user
      asked for it explicitly): a list with a chevron per row, one
      **Add Account…** button opening a searchable provider picker, and a page
      per account with back/forward in the **window toolbar**. Search covers the
      names Azure DevOps has had — `ado`, `vsts`, `devops`, `tfs`. Provider
      marks are the vendors' own SVGs converted to vector PDFs, in both
      appearances; see the `rsvg-convert` trap in CLAUDE.md, which cost an hour
      because the bad PDF loads without error and reports a sensible size.
      **opencode's credential is not like the other two.** It is Basic auth to
      the user's own `opencode serve`, so Verify cannot run without the server
      URL — there is no fixed host to probe. The same URL is what puts OpenBox
      in remote mode, which replaced the old "empty text field means local"
      convention.
      **Found in passing, not fixed:** `RGBA.init(_ color: Color)` calls
      `NSColor(color)`, so *decoding* `DeckSettings` bridges a dozen SwiftUI
      Colors into AppKit — and that bridge is not thread-safe. One crash was
      captured on 2026-08-26: `SIGABRT`, malloc corruption inside
      `-[NSConcreteMapTable grow]` under `NSColor.init(_:)`, under
      `DevBoxSettings.init()`, under `DeckSettings.init(from:)`. `load()` is
      called from the app, the agent and every widget timeline. Predates this
      work entirely. Fix by storing default colours as literal components
      instead of round-tripping through `Color`/`NSColor`.
      **Open follow-ups:** the legacy per-slot fallback is a one-release
      courtesy for a Deck that was upgraded but never opened — remove it after
      1.30 ships. Azure's project lives on the account, so TaskBox and PRBox on
      different projects need two accounts sharing one PAT.
- [x] **`RGBA`/`NSColor` race** — fixed 2026-08-26. `RGBA(.green)`-style
      defaults bridged through `NSColor` on every decode, from three processes
      concurrently; one `SIGABRT` was captured. Defaults are now literal
      components and `RGBA.init(_ color: Color)` is `@MainActor`, so the unsafe
      bridge is a compile error anywhere but a `ColorPicker` write-back. Fixing
      it turned up a second bug in the same line of code: system colours are
      **appearance-dependent**, so the old defaults froze whichever appearance
      happened to be current — `Color.green` is `0.204, 0.780, 0.349` under
      aqua and `0.188, 0.820, 0.345` under darkAqua. The palette is pinned to
      aqua. No stored colour changes; defaults only apply to absent keys.
- [x] **`SMAppService`** instead of hand-written LaunchAgent plists — puts Deck
      in System Settings → Login Items, where a suspicious user looks first.
      Shipped 2026-08-27 (`docs/planning/smappservice/`). Both agents
      (`com.deck.agent` 60s, `com.deck.agent.processes` fast) are registered via
      `SMAppService.agent(plistName:)` from plists sealed in the signed bundle,
      addressing the embedded DeckAgent with a move-proof `BundleProgram`
      (relative to the bundle). Behavior changes that shipped with it:
      - The "Refresh in background" toggle is now authoritative: relaunching
        Deck no longer reinstalls agents the user switched off. Deck never
        fights a choice made in System Settings → Login Items; what it does
        about one depends on the direction (see the correction below).
      - The fast agent's plist pins StartInterval at the 5s minimum of the
        setting range; the agent self-throttles to the configured
        `processRefreshInterval` (pure policy, unit-pinned), and the processes
        snapshot is always written — so LiveBox's process rows no longer go
        empty on quiet machines.
      - The per-tick agent file logs are gone (launchd cannot expand `~` in a
        signed static plist); diagnostics are OSLog-only
        (`log show --predicate 'subsystem == "com.deck.agent"'`), which was
        already the documented path.
      Legacy `~/Library/LaunchAgents` plists are booted out and deleted on
      launch for one release (upgraded installs), and the manual uninstall
      commands in README still work. Known limitation: registration requires
      the app to be in an approved location — a dev build in `build.noindex`
      cannot register (verify through the installed copy, as usual).
      Measured 2026-08-27: a `launchctl bootout` of a *registered* agent (while
      the app is not running) takes the job down until login — the
      registration record survives (status stays `.enabled`, reconcile does
      nothing) and smd does not reload it spontaneously; recovery is a
      toggle-off/on cycle (unregister + re-register) or the next login.
      Both hand-driven checks were run after v1.33 shipped, through the
      accessibility API. The in-app toggle off→on cycle passed: off writes
      `agentAtLogin = false`, on re-registers both agents
      (`managed_by = com.apple.xpc.ServiceManagement`), and `processes.json`
      then rewrites ~20s apart on the 5s launchd tick with a 15s setting —
      throttled, and written every time.

      The System Settings disable→relaunch check **failed**, and v1.33 shipped
      with the gap. A user veto in Login Items does not produce
      `.notRegistered`, which is what the policy's adopt-the-drift row was
      written for; it produces `.requiresApproval` (confirmed by logging
      `SMAppService.status.rawValue` from the app: `2`). `sfltool dumpbtm`
      shows why — the BTM record carries two independent axes, and the veto
      leaves it `[enabled, disallowed]`: Deck's registration stands, the user's
      permission does not. `.notRegistered` is only reachable when Deck itself
      never registered or unregistered. Deck therefore kept its toggle on
      while nothing ran, silently.
- [x] **Agents blocked in Login Items are reported, not fought** — follow-up to
      the above. `(true, .requiresApproval)` now returns `.reportBlocked` and
      the General tab shows "Turned off in System Settings → Login Items.
      Deck's agents are not running." under the toggle. Neither side is
      rewritten, because the same OS state also means "registered, awaiting
      first approval" on a fresh install — flipping the toggle off there would
      undo a setting the user never touched. Verified end to end on the
      installed copy: veto → relaunch → notice shown, toggle still on; re-allow
      → relaunch → notice gone (status back to `1`).

      One trap found while testing it: **replacing the app bundle resets the
      veto to `[enabled, allowed]`**, so a disable/reinstall/relaunch sequence
      tests nothing. Install first, then disable, then relaunch.
- [ ] **Sparkle auto-update.** Pointless before notarization (the update would
      be Gatekeeper-blocked too), necessary immediately after.
- [ ] **Landing page** for the launch URL.

**Not the Mac App Store.** Deck cannot ship there as architected: MAS requires
every bundled executable to be sandboxed, and DeckAgent exists precisely
because the sandbox forbids what it does — running `ps` and `docker`, reading
the opencode DB and `git log`, installing LaunchAgents. Direct distribution
with a Developer ID is the path; the $99 program covers both, so nothing is
lost by choosing it.

### Fixed in passing

- **Top-level `DeckSettings` decode was not tolerant** (fixed 2026-08-22 with
  TaskBox). `settings-schema-migration` made the nine per-widget structs decode
  tolerantly but deliberately left `DeckSettings` itself on the synthesized
  decoder, which throws `keyNotFound` for any absent section. Because
  `DeckSettings.load()` falls back to `DeckSettings()` on *any* decode error,
  adding a widget section silently reset **every** setting — colors, tokens,
  repo paths — for anyone whose `settings.json` predated it, then overwrote the
  file on the next save. Every widget added since ShipBox would have done this.
  The container now decodes each section with `decodeIfPresent`; three
  regression tests pin it.

## Feature backlog (existing widgets)

LiveBox:
- [x] Per-core CPU lines (first 8 cores) or per-core selection
- [x] Thermal state row (`ProcessInfo.thermalState`: nominal/fair/serious/
      critical; amber at serious, red at critical; off by default)
- [ ] Apple Silicon GPU/ANE usage — blocked: no public API
      (`docs/planning/livebox-per-core-cpu/prd.md:94`)
- [x] Disk per-volume (multiple mounts, internal + external)
- [x] Threshold coloring (amber/red when a value crosses warn/alarm thresholds)
- [x] Per-metric threshold pairs (CPU/MEM/DISK each have their own warn + alarm)

OpenBox:
- [x] Cost-per-day chart (stacked by model)
- [x] Session list (top sessions by tokens, large face) — "drill-down" is the
      list itself; WidgetKit has no in-widget navigation, so tap-through is
      out of scope
- [x] Tool usage stats (bash/edit/read counts from the DB)

NetBox:
- [x] Network interface picker (manual override of the auto "most active" pick)
- [x] Per-interface packet counts / error counters
- [x] Threshold coloring on rates

## Planning workflow

- **Pick** the next widget/feature: `deck-next` (reads this file + docs/planning).
- **Plan**: `deck-begin-fast <slug>` → PRD (`deck-prd`) → plan (`deck-plan`) → implement.
- Artifacts live in `docs/planning/{slug}/`; deferrals must record the blocker.
