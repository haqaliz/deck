# Deck Roadmap

Small, beautiful macOS desktop widgets that behave like native ones. The
product value is **one WidgetKit extension** (eleven widgets in the Widget
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
- [x] **BatBox** — battery: level, time remaining, charge state
- [x] **GitBox** — git activity: today + streak, 14-day chart, active repos
- [x] **DevBox** — open ports/processes, Docker containers (docker stats)
- [x] **ClipBox** — clipboard history with previews (local only)
- [x] **HomeBox** — weather + timezones (wttr.in)
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
- [x] Agent-fetched widgets say *why* a fetch failed (ShipBox / HomeBox /
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
      Follow-ups still open from `docs/planning/shipbox/prd.md:118`: ShipBox
      multi-repo support.
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
      **Open follow-ups:** deep links (`widgetURL`), multi-project/multi-org,
      custom WIQL, a second provider, Keychain storage for the PAT.
- [ ] **PRBox** — GitHub review queue: your open PRs + PRs awaiting review.
      Cheapest of the slate: reuses ShipBox's token, `HostGitHubLoader`, and
      the `FetchClassifier` error path against the pulls/search endpoints.
- [ ] **MarketBox** — configured tickers/crypto: price, day change, sparkline.
      Near line-for-line clone of the HomeBox agent fetch block.
- [ ] **BlueBox** — peripheral battery (AirPods, Magic Mouse/Keyboard).
      **Needs a feasibility spike first:** on the dev machine both
      `system_profiler SPBluetoothDataType -json` and
      `ioreg -r -k BatteryPercent` returned no battery keys for the connected
      mouse and keyboard. Do not plan until a source is proven.

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

- [ ] **ShipBox multi-repo** — several `owner/repo` targets instead of one
      (`docs/planning/shipbox/prd.md:118`). Open design points: `FetchStatusStore`
      is keyed per *source* (`.shipbox`), so per-repo outcomes need either a new
      key or an explicit worst-wins aggregate that names the failing repo;
      `ShipBoxSettings.repo: String` → list needs tolerant-decode migration;
      GitHub rate limits imply a repo cap at the 60s cadence.
- [ ] **OpenBox remote incremental sync** — `limit`-based sync instead of a full
      resync each tick (`docs/planning/openbox-remote/prd.md:105`).
- [ ] **DevBox process hide toggle** — deferred as a fuzzy heuristic
      (`docs/planning/devbox/prd.md:106`).

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
