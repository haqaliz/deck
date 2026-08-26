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
- **BatBox** — battery monitor: level, time remaining, charge state, plus
  Bluetooth accessory batteries (mouse/keyboard/AirPods), detected
  automatically (IOKit power sources).
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
- **ShipBox** — build/deploy status: GitHub Actions runs across up to five
  repos, merged newest-first (fetched by the agent with the user's token).
  Repos are either picked by hand or discovered automatically; the only widget
  that fetches concurrently — see the trap below.
- **TaskBox** — tasks: Azure DevOps work items assigned to you, with open
  count, current sprint and board lanes (PAT, fetched by the agent).
- **CalBox** — calendar: TODAY and TOMORROW sections, each with its own
  show/hide and row count (EventKit, read by the agent; covers whatever macOS
  syncs).
- **PRBox** — review queue: your open PRs and the ones awaiting your review,
  **mixed from two providers** (GitHub + Azure DevOps Git) in one list. The
  first widget with per-provider settings sub-tabs and two `FetchSource` keys,
  and the first to deep-link (rows are `Link`s; small uses `widgetURL`).
  Azure needs an identity GUID from `_apis/connectionData` — see the trap
  below.
- **MarketBox** — markets: crypto, fiat and gold priced in one display
  currency (USD/IRR/IRT/CAD/EUR/AED), from four keyless providers. Tickers are
  picked from a curated list; no charts in the face (see the Swift Charts trap).

All fourteen ship in one WidgetKit extension: `Deck.app` (host + settings window)
→ `DeckWidgets.appex`.

## Architecture

`native/` is an xcodegen project (`project.yml` → `Deck.xcodeproj`) with four
targets:

```
DeckApp/        # host app: settings window (tabs per widget), agent installer
DeckWidgets/    # WidgetKit extension: 13 widgets + Loaders/ (mach, getifaddrs, IOKit)
DeckAgent/      # silent CLI: refreshes sandbox-blocked data snapshots, then exits
Shared/         # DeckSettings (Codable), snapshots + stores, host-only samplers
```

**Two data paths (this is the core design):**

1. **Sandbox-safe, self-sampled** — LiveBox/NetBox/BatBox read mach,
   getifaddrs and IOKit directly inside the widget. LiveBox additionally
   re-samples on a `TimelineView` tick so it feels live. BatBox also reads
   *accessory* power sources — see the SPI note below.
2. **Sandbox-blocked, agent-pumped** — the widget sandbox forbids subprocesses
   and reading other apps' data (opencode DB, `ps`/process info, `git log`).
   The unsandboxed `DeckAgent` (LaunchAgent `com.deck.agent`, every 60s) reads
   those and writes snapshots into the widget's container:
   `~/Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck/{opencode,processes,gitbox,clipbox,taskbox,calbox,prbox}.json`
   The widgets render the snapshots.

**Credentials are records, not widget properties.** A `CredentialAccount`
(`Shared/CredentialAccount.swift`) has a kind (github/azure/opencode), a label,
and whatever identifies the connection — Azure org + project, opencode server
URL. Widgets reference one by id through a `CredentialSlot` (`openbox`,
`shipbox`, `taskbox`, `prboxGitHub`, `prboxAzure`), each of which knows its
kind and its `FetchSource`. The keychain item is `account.<id>.token`; the id
is generated once and never rewritten, because renaming it strands the token.
One decision table, `DeckSettings.gate(_:unavailable:)`, answers "fetch, and if
not, what does the widget say?" for both `DeckAgent` and the settings window —
`off` (nothing selected), `notConfigured` (a selection that no longer resolves)
and `unavailable` (locked keychain) are three different answers on purpose.
`DeckSecret`'s five fixed cases survive only for the one-way migration and a
one-release fallback for a Deck that was upgraded but never opened.

**Settings live in the Deck app window only** (per-widget tabs: show toggles,
colors, counts, account pickers, GitBox repo paths; credentials in their own
tab). They persist to
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

### Repair scripts

```bash
scripts/lsclean.sh          # after EVERY release build — unregisters dev copies
                            # of Deck.app that xcodebuild registered, then
                            # re-registers /Applications and restarts chronod
scripts/container-repair.sh # rebuilds the widget container skeleton when a
                            # partial uninstall left it unprovisioned and every
                            # widget renders blank
scripts/soak.sh             # long-running sanity loop over the snapshots
```

Reinstalling: replace **only** the app bundle —
`rm -rf /Applications/Deck.app && cp -R native/build.noindex/Build/Products/Release/Deck.app /Applications/`.
Do not delete the container; see the trap below.

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
- **A Swift Charts `Chart` inside a widget face silently drops the widget
  from the gallery.** Discovered with MarketBox (2026-08-24): a widget whose
  face draws a `Chart` (even a 30×12 sparkline inside a `ForEach` row) never
  appears in the Widget Center, while the other 13 widgets enumerate fine. The
  usual tells are all absent: pluginkit registers the new extension version,
  the binary contains the widget, the extension launches, no crash report
  appears, and chronod serves the last-good 13-widget descriptor set. The
  documented `log show ... | grep -c <Name>BoxWidget` check cannot be used
  either — the unified log can be entirely empty on a machine. Bisect by
  stripping the widget to a minimal clone (it enumerates), then restore parts
  until it disappears again. **Fix: don't use Swift Charts in widget faces at
  all** — MarketBox's sparkline-first face hit this; the fix and the user's
  own revision both removed Charts (MarketBox ships sparkline-free; the other
  Deck widgets that use Charts render them in full-width chart areas, which
  is fine).
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
- **A calendar event's meeting link is not in `EKEvent.url`.** That field is
  the obvious one and is empty in practice: measured across a real synced
  Google account, **0 of 10** events set `url`, **0** had a URL in `location`,
  and **9 of 10** carried one in `notes`. The notes hold three hosts, not one —
  `meet.google.com` (the call), `support.google.com` ("Learn more about Meet")
  and `tel.meet` (dial-in) — so "first URL in the notes" opens a help page from
  a click on a meeting. `CalendarLink` matches a list of known conferencing
  hosts (exactly or as a subdomain, never as a substring, or `zoom.us.evil.com`
  would pass) and leaves an event with none unlinked.
- **A widget's URL is delivered to the app, not to the browser.** On macOS
  WidgetKit hands `widgetURL` / `Link` destinations to the **containing app**;
  it never opens them itself. A widget that links to a web page therefore needs
  the app to receive the URL and forward it (`DeckAppDelegate.application(_:open:)`
  → `NSWorkspace.open`), or the click just launches Deck and appears to do
  nothing. Two further traps came with it: a plain `WindowGroup` manufactures a
  **new window for every URL delivered**, which needs
  `.handlesExternalEvents(matching: [])` on the scene (not
  `applicationShouldHandleReopen`, which does not cover URL opens); and Deck
  must **not** declare `CFBundleURLTypes` for http(s), or it becomes a
  candidate browser. Forwarding is filtered to http(s)-with-a-host
  (`DeckURLForwarding`) because the URL originates in a snapshot file, which is
  data rather than instruction.
- **Azure DevOps' Git PR API silently ignores an identity it can't parse.**
  `searchCriteria.creatorId` / `.reviewerId` take identity **GUIDs**; there is
  no `@Me` macro as there is in WIQL. A non-GUID value is not rejected — it
  returns **200 with every active pull request in the project**. Measured on a
  live org: 6 with no criteria, the same 6 with `@me`, 0 with a well-formed
  unknown GUID. PRBox therefore resolves the PAT owner's id from
  `{org}/_apis/connectionData` and **fails the fetch** if it can't
  (`HostAzurePRLoader.requireIdentity`); there is no safe fallback, because the
  unfiltered result renders the whole team's work as though it were yours and
  nothing in the response says otherwise. Two more from the same probe: the PR
  payload has **no update timestamp** (only `creationDate`, which is why PRBox
  sorts both providers by creation) and **no web URL** (built as
  `…/_git/{repo}/pullrequest/{id}`), and `reviewerId` returns PRs you have
  **already voted on**, so the review queue filters to `vote == 0` to mean what
  GitHub's `review-requested` means.
- **GitHub's Actions API costs ~11 KB per run, and no field says whether a
  repo has CI.** A `workflow_runs` entry embeds the *entire* repository object,
  so payload scales with runs, not repos: measured on a live account,
  `per_page=1` is 11.4 KB and `per_page=8` is 91.6 KB. ShipBox's automatic mode
  therefore probes candidate repos at `per_page=1` purely to learn which have
  runs, then fetches in full only the ones it will show — fetching every
  candidate in full costs ~45 MB/hour for an eight-row widget. The probe is
  needed because **nothing in a repo object advertises Actions**: no field
  matches `workflow` or `action`, and `actions/runs` answers **200 with
  `total_count: 0`** for a repo with no workflows (an unknown repo is a 404).
  Recency is a good proxy but not a reliable one — 7 of 19 owned repos had any
  runs, and the first miss was the 7th by push date.
- **Fan out concurrently or miss the tick.** `URLSession.timeoutInterval` is
  per *request*, so N serial fetches can stall for N×10s against a 60s agent
  cadence. Five repos measured **9.4s serially, 2.1s concurrently**. ShipBox's
  `HostGitHubLoader.inParallel` is the only `withThrowingTaskGroup` in the
  codebase; every other loader (including MarketBox's four providers) awaits
  serially and gets away with it only because it has fewer sources.
- **Accessory batteries need an SPI, and two obvious sources are dead ends.**
  `IOPSCopyPowerSourcesList` returns only the internal battery — accessories
  are a separate power-source type reached via `IOPSCopyPowerSourcesByType(4)`,
  which IOKit exports but the public SDK headers do not declare, so it is bound
  with `@_silgen_name`. Verified working *inside the sandboxed extension*, not
  merely in a CLI. Before reaching for something else: `system_profiler
  SPBluetoothDataType -json` reports **no battery keys at all** for a real
  connected mouse (only address/firmware/type/IDs), and IORegistry exposes no
  `BatteryPercent` for it either — both were tried and both fail. `pmset -g
  accps` is the quickest ground truth. Being SPI it can vanish in any macOS
  update, so every failure path returns an empty list and the section simply
  hides.
- **Two settings fields are read *inside the widget extension*, and moving one
  breaks a widget silently.** Found while making credentials into accounts
  (2026-08-26): `OpenBoxWidget` read `openbox.serverURL` to decide local vs
  remote, and `PRBoxWidget` read `prbox.{github,azure}.enabled` to decide which
  providers to name in its chip. Both fields moved onto accounts, so both would
  have read empty forever — OpenBox permanently local, PRBox permanently
  both-providers-off — with **no crash, no log and no chip**, just a wrong
  face. `grep -rn "\.enabled\|serverURL" native/DeckWidgets/` is the check.
  Anything the extension reads must stay answerable from `settings.json`
  *without a token*, because the extension has no keychain access at all; the
  replacements (`openBoxUsesRemoteServer`, `prBoxGitHubIsOn`, `prBoxAzureIsOn`)
  turn only on non-secret fields and are unit-pinned. Related: a migration that
  moves a field must **clear the old copy**, or the pre-migration fallback keeps
  answering from a dead field after the new control has taken over.
- **Launching a quarantined Deck deletes it, and `--no-quarantine` is gone.**
  Measured 2026-08-26 on Homebrew 6.0.19 / macOS 15 while wiring up the tap.
  Two separate problems with the install instructions this repo shipped for
  four releases:
  1. `brew install --cask --no-quarantine …` fails outright — Homebrew removed
     the flag ("Error: invalid option"). Every README and cask caveat telling
     users to pass it was handing them an uncommand.
  2. Opening a still-quarantined Deck does **not** just warn. Gatekeeper
     **removes `/Applications/Deck.app`** — not to the Trash, it is simply
     gone, while `brew list --cask` still reports it installed and the
     Caskroom keeps a dangling symlink. Reproduced twice.
  The working sequence is `brew install --cask` → `xattr -dr
  com.apple.quarantine /Applications/Deck.app` → *then* launch. Same bits,
  and the order is the whole difference. All of it disappears on notarization.
  The tap is `haqaliz/homebrew-deck` (created 2026-08-26 — it was referenced by
  the README for four releases before it existed); `homebrew/deck.rb` here is
  the source of truth and `Casks/deck.rb` there is a mirror.
- **An opencode token is Basic auth to the user's own server, not an account on
  a service.** `RemoteOpenCodeLoader` sends
  `Basic base64("opencode:<token>")` to whatever `serverURL` the account
  carries. There is no fixed endpoint to probe the way `api.github.com` and
  `dev.azure.com/{org}` are fixed, so anything that wants to check the
  credential — Verify included — needs the URL first. Verify uses
  `RemoteOpenCodeLoader.probe`, a single `GET /session`; `load` follows up with
  a request *per session* when the server reports no session-level usage, which
  is right for a snapshot and far too much for a credential check.
- **`rsvg-convert -f pdf` can emit a PDF that CoreGraphics draws as nothing.**
  Hit converting the provider marks for the Credentials tab (2026-08-26). The
  opencode logo wraps its paths in a `mask` with `mask-type:luminance` and a
  `clipPath`, both full-canvas no-ops; rsvg turns them into a PDF transparency
  group that renders correctly in rsvg's own PNG output and **completely empty**
  through `NSImage`. Nothing errors: `NSImage(contentsOf:)` succeeds and reports
  a sensible `size`, so the only symptom is a blank icon. Check a converted PDF
  by *drawing* it (`img.draw(in:)` into a bitmap and looking), not by loading
  it. Fix: strip no-op masks and clip paths from the SVG before converting.
  Vendor artwork lives in `DeckApp/Resources/provider-<kind>-{light,dark}.pdf`
  and is host-app only — the widget extension does not ship it and falls back
  to `CredentialKind.systemImage`.
- **A `keychain-access-groups` entitlement SIGKILLs Deck at launch.** Measured
  2026-08-26 (`docs/planning/keychain-tokens/probe.md`) while looking at moving
  the API tokens to the keychain. Signing either the app bundle *or* a bare
  tool built like `DeckAgent` with that entitlement makes the process die
  before `main` — **exit 137**, no crash report, no message. A control isolates
  it exactly: strip the entitlement → exit 0; re-add → 137; strip → 0. The
  entitlement needs a provisioning profile to authorise it, an `.app` can embed
  one at `Contents/embedded.provisionprofile`, and **a `type: tool` target has
  nowhere to put one**. The data-protection keychain is therefore also out:
  `SecItemAdd` with `kSecUseDataProtectionKeychain` returns **`-34018`
  (errSecMissingEntitlement)** without it. Use the legacy (file-based) keychain
  — which needs no entitlement at all.
- **The keychain gives Deck confidentiality at rest, not process isolation, and
  a keychain ACL does not change that.** Same probe. A generic-password item
  written by a bundled app is read by a separately-signed bare tool **inside a
  launchd job, with no prompt**, even with
  `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail` — so the feared
  per-binary ACL prompt never appears. The flip side is that an **ad-hoc-signed
  copy** and **`/usr/bin/security`** read the same item just as freely, and
  still did against a second item written with an explicit `SecAccess` trusting
  only two named binaries (`SecItemAdd` appears not to honour `kSecAttrAccess`).
  Never describe keychain storage in Deck as protecting a token from other
  local processes; it protects it from being *in a file that gets copied*.

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
