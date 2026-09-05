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
  **picked, never typed**, from a live CoinGecko search in the settings tab —
  settings store the coin's id, so the agent resolves nothing at fetch time; no
  charts in the face (see the Swift Charts trap).

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

The two background agents are registered with `SMAppService` from plists in
the signed bundle (`Contents/Library/LaunchAgents/`, `BundleProgram` relative
addressing); they show up under System Settings → General → Login Items. Manual
fallback: `launchctl bootout gui/$(id -u)/com.deck.agent` (and
`.processes`), plus remove any legacy `~/Library/LaunchAgents/*.plist`
(pre-SMAppService installs). Registration only works from an approved
location — dev builds in `build.noindex` cannot register; verify through the
installed copy. Note: booting out a *registered* agent takes the job down
until the next login or a toggle-off/on cycle — the registration survives
(status stays `.enabled`), so neither the app's reconcile nor smd reloads it.

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
- **The settings window and the agent share one rate-limit budget, and the
  agent loses.** Found building MarketBox's coin picker (2026-09-05). CoinGecko
  is keyless, so every request from this machine counts against one public-IP
  quota: **six requests in ~2 minutes returned 429 with `retry-after: 55`**,
  and `DeckAgent` already spends up to **4 calls per 60s tick** on it (crypto,
  gold, Toman, FX). A search-as-you-type picker would therefore 429 *the agent*
  and blank the widget while the user was choosing a ticker — the settings UI
  breaking the data path it configures. Any live lookup behind a settings
  control needs a debounce, a floor between requests and a per-query cache
  (`CoinSearchPolicy`), must run **host-app-only on user interaction**, and must
  degrade itself rather than the snapshot. Two more measured facts about that
  API worth keeping: an **unknown id is dropped silently** (`ids=bitcoin,nope`
  → 200 with one row, nothing saying the other was ignored), and an **empty
  `ids=` returns the top 100 coins** (200, 83.6 KB) rather than an error or an
  empty list — so a request with no ids must never be built, or the widget
  renders a stranger's portfolio as the user's own.
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
- **`NSColor(SwiftUI.Color)` is not thread-safe, and it was reachable from
  `DeckSettings`' decode path.** Every widget settings struct built its default
  colours with `RGBA(.green)`, whose init bridges through `NSColor` — so merely
  *decoding* settings ran a dozen bridges, from the app, `DeckAgent` and every
  widget timeline at once. Crashed in production 2026-08-26: `SIGABRT`, malloc
  corruption inside `-[NSConcreteMapTable grow]` under `NSColor.init(_:)` under
  `DevBoxSettings.init()`. Defaults are now literal components
  (`RGBA.systemGreen` and friends) and `RGBA.init(_ color: Color)` is
  `@MainActor`, so reaching for the bridge off the main thread is a compile
  error instead of a race — the one legitimate caller is a `ColorPicker`
  writing back. **The same defaults were also appearance-dependent**:
  `Color.green` bridges to `0.204, 0.780, 0.349` under aqua and
  `0.188, 0.820, 0.345` under darkAqua, so whichever appearance was current
  when a settings file was first written got frozen into it. The palette is
  pinned to the aqua values, which is what a headless process resolves.
- **`hdiutil create -fs HFS+` silently produces an unmountable DMG on macOS 26,
  and nothing downstream notices.** Cost an hour releasing v1.40 (2026-09-05).
  The release job created the image, `codesign` warned, `shasum` recorded the
  bytes, `gh release create` published it, and the run was **green** — but
  `hdiutil attach` and `hdiutil convert` both answered **"corrupt image"**, three
  cut attempts running. Everything that usually localises a bad download says
  the file is fine: two different tools fetch identical bytes, the sha256
  **matches the release's own `SHA256SUMS.txt`** (so the runner really did
  publish this), the `koly` trailer arithmetic is consistent, and the embedded
  XML plist parses with all 8 `blkx` entries — the damage is inside the
  compressed data fork. Ruled out by measurement, not guesswork: the runner
  image (identical `macos-26-arm64` 20260831.0337.3 / macOS 26.6.2 built a
  working v1.39 hours earlier), and `codesign --force` failing with "no identity
  found" (it leaves the file **byte-identical and still valid** — that warning
  is a red herring the log ordering makes look guilty). **Fix: build the image
  as `-fs APFS`.** APFS disk images are readable on 10.13+, far below Deck's
  macOS 15 deployment target. **And verify before publishing** — the job now
  runs `hdiutil verify` plus a real `attach`/`test -d Deck.app`/`detach`, because
  the whole failure mode is that a green run happily ships an image nobody
  opened. Locally the same content packed 8/8 good as HFS+, so do not expect to
  reproduce it on your own Mac.
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

- **Editing `settings.json` by hand while Deck.app is running tests nothing.**
  The host app holds settings in memory and its own refresh path writes the
  snapshots (`DeckApp.swift`, the TaskBox and PRBox refreshes), so a running
  Deck silently overwrites both the file you edited and the snapshot you were
  inspecting — with its stale copy. Hit while verifying multi-project
  (2026-08-28): a failure case appeared to produce a *newer, differently
  shaped* snapshot than the passing case before it, which is impossible from
  the agent alone. `pgrep -lf "MacOS/Deck$"` is the check; quit Deck first, and
  drive the agent directly with
  `/Applications/Deck.app/Contents/MacOS/DeckAgent`. The tell that a snapshot
  was genuinely left alone is an **unchanged mtime**, not unchanged content.
- **A repo name is only unique inside its Azure project, and PR numbers are
  per repo.** `azureDevOps:{repo}#{number}` looked like a safe id for one
  project and is a collision as soon as an account covers two: two projects
  each with an `api` repo and a PR #12 produce one id, which SwiftUI collapses
  into a single row through the duplicate `ForEach` key — no crash, no log,
  one row simply missing. The project is part of the identity. Same shape of
  bug in the work-item batch: `workitemsbatch` is **organization**-scoped while
  WIQL is project-scoped, so one merged call returns rows from every project
  and `System.TeamProject` must be requested, or every row's URL is built from
  whichever project was queried first and deep-links into the wrong place.
  Useful in the other direction too: because the batch and `connectionData` are
  org-scoped, N projects cost N+1 requests for TaskBox and 2N+1 for PRBox
  rather than 3N.
- **A user veto in Login Items is `.requiresApproval`, not `.notRegistered`,
  and reinstalling erases it.** Measured 2026-08-27 by logging
  `SMAppService.status.rawValue` from the app. Switching Deck off under System
  Settings → General → Login Items leaves the BTM record
  `[enabled, disallowed]` (`sfltool dumpbtm`) — two independent axes, where
  `enabled` is Deck's registration and `disallowed` is the user's permission —
  and `status` reports `.requiresApproval` (raw `2`). `.notRegistered` is only
  reachable when Deck itself never registered or called `unregister`, so a
  reconcile policy that keys "the user turned us off" on `.notRegistered`
  never fires and the app silently claims background refresh is on while
  nothing runs (shipped that way in v1.33). The state is indistinguishable
  from "registered, awaiting first approval" on a fresh install, so Deck
  reports it in the General tab rather than rewriting either side. Two further
  traps when testing this: **replacing the app bundle resets the veto to
  `[enabled, allowed]`**, so disable-then-reinstall tests nothing (install
  first, then disable, then relaunch); and replacing the bundle also takes the
  running jobs down without reloading them, same as a `bootout`.
- **`SMAppService.status` says a record exists, not that the job runs — and
  `launchctl list` cannot tell you either.** Measured 2026-08-29
  (`docs/planning/bundle-identifier/probe.md`). Both agents sat
  `[enabled, allowed]` in `sfltool dumpbtm` with the "Refresh in background"
  toggle on, while `launchctl print gui/$(id -u)/com.deck.agent` answered
  `Could not find service` and **nothing was written for 6 hours**. `.enabled`
  is what `SMAppService` reports for a registration record; whether launchd
  bootstrapped the job is a second, invisible axis. `AgentReconcilePolicy`
  correctly does nothing (intent on, state `.enabled`), and v1.34's notice
  cannot fire — that one is for `[enabled, disallowed]` → `.requiresApproval`.
  Three traps around it:
  1. **`launchctl list | grep com.deck.agent` prints nothing on a healthy
     install.** SMAppService jobs are not bootstrapped into `gui/<uid>` under
     their plist label; the labels appear only in the domain's enabled/disabled
     table. README and the issue template asked for that command from v1.33
     until it was corrected.
  2. **The two snapshot witnesses are the only unambiguous liveness probes, one
     per agent.** `processes.json` has been the fast agent's single writer since
     v1.30 and `agent-heartbeat.json` is the 60s agent's, added for exactly this
     reason: every *other* snapshot is written by the host app too, which is why
     a dead agent is invisible while Deck is open. Their mtimes separate "an
     agent ran" from "the app ran" — and, since v1.37, which agent.
     `agent-heartbeat.json` is written at the **start** of the full refresh, not
     the end: the path awaits ~10 mostly serial sources at 10s timeouts, so an
     end-write would report a slow-but-healthy tick as dead while catching
     nothing extra (launchd starts no new tick while one is running, so a hung
     agent stops advancing it either way). Measured 2026-08-31: a real tick is
     **~68s**, not 60 — `StartInterval` plus the tick's own duration — which is
     what the 240s limit actually absorbs. **Deck now reports this
     itself** (`AgentLivenessPolicy`, `docs/planning/agent-liveness/`): the
     General tab says "Background refresh has stopped" with a **Restart agents**
     button once the snapshot is older than
     `max(4 * processRefreshInterval, 120)`, held back by a grace-period clock
     (`DeckSettings.agentsRegisteredAt`) so a fresh install and the first launch
     after a rename stay quiet.
     Since v1.37 both agents have a witness and the notice **names the half that
     stopped** — before that, a dead 60s agent alone produced no notice at all
     while eight widgets went stale and LiveBox kept ticking in front of the
     user. Two traps came out of building it: **a grace-period guard belongs in
     the policy, not in the clock**, because a clock is restarted by relaunching
     Deck and a user who reopens the window every few minutes would never see
     the notice (the same shape as the bug where opening Deck was both what
     broke the agents and what made the data look fresh); and **`.never` from a
     witness is not always a fault** — the release that introduces a witness
     finds it absent on every upgraded install, so "never written, while the
     other agent is demonstrably alive" is treated as ambiguous rather than
     damning.
     **`launchctl print` is not a substitute, even when it finds the job.**
     Measured 2026-08-30: the job was present, with `runs = 13741` and
     `last exit code = 78: EX_CONFIG` / `job state = spawn failed` — thirteen
     thousand silent failed spawns at 5s intervals. "Registered but not running"
     has at least two shapes (job absent; job present but spawn-failing), and
     only "did it write anything" catches both.
     Two traps for anyone building on this: **`sfltool dumpbtm` prompts for an
     admin password and blocks on it** — not read-only from a script's point of
     view, and minutes to dump; and a grace-period stamp **guarded on `== nil`**
     silently defeats the rename case, because `ContainerMigration` carries a
     non-nil timestamp from the old install into an empty container. Registering
     must restart that clock unconditionally (`AgentRegistrationClock`).
  3. **`settings.json` is not an off switch.** Setting `agentAtLogin: false`
     with Deck quit is undone on the next launch: with the record `.enabled` the
     reconcile policy reads the registration as the newer choice and adopts it
     back to `true`, never unregistering. Recovery is the in-app toggle
     (`unregister()` directly) or a login — and `launchctl bootstrap` of the
     bundle's plists fails with `Input/output error`, because `BundleProgram`
     resolves only inside the SMAppService context.
- **Deck used to boot out its own agents on every launch** (fixed 2026-08-30).
  Measured 2026-08-30 (`docs/planning/agent-liveness/verification.md`).
  `reconcileAgents()` calls `legacyCleanup()` on every launch, which
  `launchctl bootout`s `DeckBundle.Legacy.agentLabel` and `.fastAgentLabel` —
  and **before the rename those are the current labels**, not old ones. So each
  launch takes down the two jobs SMAppService is running, and nothing puts them
  back: the registration survives as `.enabled`, so
  `resolve(intent: true, state: .enabled)` returns `[]` and reconcile correctly
  does nothing. Measured directly: healthy at `runs = 24`, quit + relaunch, both
  jobs `Could not find service` and the snapshot frozen at the relaunch instant;
  left alone, the same registration ran three minutes and twenty clean ticks.
  **This is the cause of the 6-hour and 38-hour silences** recorded below and in
  `docs/planning/bundle-identifier/probe.md` — the toggle-cycle recovery and
  "settings.json is not an off switch" are both describing this symptom. It went
  unnoticed because opening Deck is what breaks it *and* what makes the data look
  fresh, since the host app pumps every snapshot except `processes.json`.
  **Fixed** by `LegacyAgentCleanup`: boot out only labels whose
  `~/Library/LaunchAgents/<label>.plist` actually exists — a ≤1.32 install has
  one and needs the bootout, a clean install has none and needs nothing. The
  condition is the plist rather than "is this label still current", because the
  plist is what the function cleans, and a leftover under an old label must
  still go after the rename. Verified on the installed copy: before, one
  quit/relaunch killed both jobs permanently; after, three cycles left them
  alive. **If you add another caller of `legacyCleanup()`, keep the guard** —
  removing it re-creates a fault whose only symptom is silence.
- **Renaming the bundle identifier: four measured surprises.** From a real
  renamed build installed over `/Applications/Deck.app`
  (`docs/planning/bundle-identifier/`, prepared but not applied).
  1. **The new container needs no help.** containermanagerd provisions it — full
     skeleton, metadata plist, home symlinks — during `lsregister`, *before* the
     app is installed or the extension ever runs. A migration can write into it
     directly.
  2. **The old launchd job does not run the new binary; it dies.** The job
     records `parent bundle identifier` and `parent bundle version`, not just a
     path, so after the swap it fails `78: EX_CONFIG` / `spawn failed` rather
     than executing whatever now sits at `Contents/MacOS/DeckAgent`. Background
     refresh therefore stops until the renamed app launches and registers.
  3. **Orphaned agent records are re-parented, not deleted, and `unregister()`
     only disables.** BTM *replaces* the old app record and re-parents its two
     agent records to the new app, so Login Items shows four DeckAgent rows, two
     unrunnable. `launchctl bootout` fails (`No such process`), and
     `SMAppService.agent(plistName:)` resolves plists **inside the current
     bundle**, so the new bundle has no handle unless it ships the old names.
     Doing so flips them to `[disabled, allowed]`; only `sfltool resetbtm`
     removes them, and it wipes every login item on the machine.
  4. **Rollback is not symmetric.** Reinstalling the old bundle over the new one
     leaves **two BTM app records claiming the same URL**, after which launchd
     refuses both jobs with `EX_CONFIG`. The in-app toggle,
     `launchctl kickstart -k` and restarting `smd` all fail; only a
     logout/login repairs it. **Corrected 2026-08-30**
     (`docs/planning/agent-liveness/verification.md`): a logout is *not* the
     only repair. A machine sat in this exact state — two records for
     `file:///Applications/Deck.app/`, both jobs `EX_CONFIG`, 16 days uptime —
     for 38 hours, and replacing the app bundle followed by an in-app
     unregister→register (the **Restart agents** button) fixed it; the agent
     wrote one second later. Which half of that did the work is not isolated,
     so try it before telling anyone to log out. Note the two faults are
     distinct and both were present on that machine: the `EX_CONFIG`
     spawn-failure above (duplicate BTM records), and the far more common
     launch-time self-bootout described further up.
- **`Embed LaunchAgents` used to ship plists from the previous build.** It was
  `mkdir -p` + `cp` with no clean, so an incremental build across a rename
  sealed *both* generations into the signature with nothing complaining. Fixed
  by clearing the destination first (`project.yml`); if you add another
  copy-into-the-bundle phase, clear its destination too.
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
