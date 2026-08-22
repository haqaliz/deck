# Deck: Project Context

This file orients an agent working in this repository. Read it first. Deeper
context lives in `ROADMAP.md` and `docs/planning/`.

## What this project is

**Deck** is a set of small, beautiful macOS desktop widgets, delivered as a
single native app you add from the **Widget Center** (right-click desktop →
Edit Widgets). No floating window cards — everything is a real WidgetKit
widget.

- **LiveBox** — system monitor: live CPU / MEM / DISK chart + top processes.
- **OpenBox** — opencode usage: today's in/out tokens + cost, 14-day chart,
  top models (parsed from the opencode DB).
- **NetBox** — network monitor: per-interface up/down rates + history,
  top interfaces (getifaddrs counters).
- **BatBox** — battery monitor: level, time remaining, charge state
  (IOKit power source).
- **GitBox** — git activity: commits per day for 14 days, today's count,
  streak, and active repos (scanned under `~/dev` by default).
- **ClipBox** — clipboard history: recent copies with previews, local only
  (sampled from NSPasteboard by the agent).
- **DevBox** — dev environment: open TCP listening ports (process + port) and
  running Docker containers (subprocesses, via the agent).
- **WeatherBox** — weather: conditions and a 3-day forecast for your location
  (wttr.in, fetched by the agent). Was HomeBox until its clock half split out.
- **ClockBox** — world clocks: up to six cities (3 on medium, 6 on large),
  each with its time, relative day and offset from your own zone; a chosen
  "main" clock drives the small face. The only widget on **neither** data
  path — pure `TimeZone` + `Date`, no snapshot, no sampler, no network.
- **ShipBox** — build/deploy status: GitHub Actions runs for a repo (fetched
  by the agent with the user's token).
- **TaskBox** — tasks: Azure DevOps work items assigned to you, with open
  count, current sprint and board lanes (PAT, fetched by the agent).
- **CalBox** — calendar: TODAY and TOMORROW sections, each with its own
  show/hide and row count (EventKit, read by the agent; covers whatever macOS
  syncs).

All twelve ship in one WidgetKit extension: `Deck.app` (host + settings window)
→ `DeckWidgets.appex`.

## Architecture

`native/` is an xcodegen project (`project.yml` → `Deck.xcodeproj`) with four
targets:

```
DeckApp/        # host app: settings window (tabs per widget), agent installer
DeckWidgets/    # WidgetKit extension: 12 widgets + Loaders/ (mach, getifaddrs, IOKit)
DeckAgent/      # silent CLI: refreshes sandbox-blocked data snapshots, then exits
Shared/         # DeckSettings (Codable), snapshots + stores, host-only samplers
```

**Two data paths (this is the core design):**

1. **Sandbox-safe, self-sampled** — LiveBox/NetBox/BatBox read mach,
   getifaddrs and IOKit directly inside the widget. LiveBox additionally
   re-samples on a `TimelineView` tick so it feels live.
2. **Sandbox-blocked, agent-pumped** — the widget sandbox forbids subprocesses
   and reading other apps' data (opencode DB, `ps`/process info, `git log`).
   The unsandboxed `DeckAgent` (LaunchAgent `com.deck.agent`, every 60s) reads
   those and writes snapshots into the widget's container:
   `~/Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck/{opencode,processes,gitbox,clipbox,taskbox,calbox}.json`
   The widgets render the snapshots.

**Settings live in the Deck app window only** (per-widget tabs: show toggles,
colors, counts, OpenBox token/URL, GitBox repo paths). They persist to
`settings.json` in the same container and both the app and widgets read it.
No settings UI exists inside widgets (WidgetKit has none).

**Refresh cadence:** everything is 60s (agent, widget timelines). WidgetKit
throttles hidden widgets; the system floors timeline regeneration at ~60s
regardless of requested policy — do not fight it.

## Commands

```bash
xcodegen generate --spec native/project.yml   # regenerate after project.yml
                                              # OR any new source file: xcodegen
                                              # enumerates files at generation
                                              # time, so a new test file is
                                              # silently not compiled and the
                                              # suite still reports success
xcodebuild -project native/Deck.xcodeproj -scheme DeckApp -configuration Release \
  -derivedDataPath native/build.noindex -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build

# install
cp -R native/build.noindex/Build/Products/Release/Deck.app /Applications/
open /Applications/Deck.app                    # installs the LaunchAgent, refreshes data
pluginkit -m -i com.deck.app.widgets           # verify the extension registered
```

Uninstall the background agent: `launchctl bootout gui/$(id -u)/com.deck.agent`
and remove `~/Library/LaunchAgents/com.deck.agent.plist`.

## Signing & install notes

- Automatic signing, team `K6X49DG8VF` (personal team), "Apple Development"
  identity. Requires a real Apple identity: **ad-hoc/self-signed extensions
  are rejected by `pluginkit`**.
- The widget extension is sandboxed; the host app and DeckAgent are not.
- `DeckAgent` is embedded at `Deck.app/Contents/MacOS/DeckAgent` (copied by a
  post-build script, sealed with the app).
- First run of DeckAgent prompts once for "access data from other apps"
  (it runs `ps` for the process list) — click Allow; the grant sticks to the
  stable signature.
- DeckAgent also prompts for **calendar** access (CalBox). A `type: tool`
  target has no bundle, so the usage-description key ships in a
  `__TEXT,__info_plist` section (`CREATE_INFOPLIST_SECTION_IN_BINARY` in
  project.yml) — without it the request is denied without ever prompting.
  Deck.app and DeckAgent are separately signed, so macOS asks once for each.
- **Adding a widget requires a version bump.** WidgetKit caches the widget
  descriptor set per extension version, so a new widget added without raising
  `CFBundleShortVersionString` / `CFBundleVersion` in `project.yml` never
  appears in the Widget Center — the gallery reuses the cached list. Everything
  else looks healthy while this is happening: the binary contains the widget,
  `pluginkit` registers the extension, snapshots pump, chronod logs no errors.
  Check with
  `log show --last 2m --info --debug --predicate 'process == "chronod"' | grep -c <Name>BoxWidget`;
  zero means the descriptors are stale.
- **Never `rm -rf` the widget container.** It deletes the directory tree but
  cannot delete `.com.apple.containermanagerd.metadata.plist` (SIP-protected,
  fails with "Operation not permitted"). Because that plist survives,
  containermanagerd still thinks the container is provisioned and never
  rebuilds the skeleton, so `Data/SystemData/com.apple.chrono/` — where chronod
  writes every rendered timeline — no longer exists. **Every widget then
  renders as an empty rounded rect at every size, gallery previews included**,
  while codesign, `pluginkit`, LaunchServices and crash reports all look
  perfectly healthy. chronod reports it as `CHSErrorDomain (1300)
  "extensionNotFound"`, which is a red herring; the real line is one above:
  `could not create file handle because
  ChronoKit.WidgetCacheManager.CacheManagementError.unsupportedEntryKey`.
  Repair with `scripts/container-repair.sh`. When uninstalling, remove the
  widgets from the desktop *first* and leave the container alone unless you
  actually want to reset settings — note it holds the OpenBox/ShipBox/TaskBox
  tokens, so back up `settings.json` before wiping it.
- **`build.noindex` does not prevent LaunchServices pollution.** The `.noindex`
  suffix only hides the directory from Spotlight; xcodebuild still runs an
  explicit `RegisterWithLaunchServices` phase that registers the dev copy. Run
  `scripts/lsclean.sh` after every release build — not only when widgets start
  rendering as placeholders.
- Build only into `native/build.noindex` (the `.noindex` suffix keeps Spotlight,
  and therefore LaunchServices, from registering throwaway dev copies of
  `com.deck.app`). A registered dev copy — especially one whose worktree was
  later deleted — makes WidgetKit resolve the wrong bundle and reject every
  render: chronod logs `bundleStubNotSupported` / "Bundle version did not
  match", and every widget falls back to its placeholder (text as grey blocks,
  charts still drawn) at every size. Repair with `scripts/lsclean.sh`.

## Conventions

- Metrics loaders return pure data; stores own timers; views own layout.
- Widgets share a visual language: rounded system fonts, monospaced digits,
  colored-dot metric rows, hidden chart axes, section titles tracked 1pt.
- New widgets: copy an existing widget file, add to
  `DeckWidgets/DeckWidgets.swift` (bundle), add settings tab in
  `DeckApp/DeckApp.swift`, add the snapshot to `DeckAgent` when the data is
  sandbox-blocked, register in README.md and ROADMAP.md.
- Widgets must not regress between builds: re-add from the gallery to verify.

## Roadmap

See `ROADMAP.md` for the widget pipeline, milestones, and how to pick the next
widget or feature. Planning artifacts live in `docs/planning/{slug}/`
(prd.md → plan_*.md), produced via the `deck-prd` / `deck-plan` skills.
