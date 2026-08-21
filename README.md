# deck — macOS desktop widgets

<p align="center">
  <img src="docs/deck.svg" width="120" alt="Deck logo">
</p>

A collection of small, beautiful macOS desktop widgets, delivered as one native
app — **Deck** — and added from the macOS **Widget Center** (right-click the
desktop → **Edit Widgets…**, or click the clock in the menu bar). Real
WidgetKit widgets with native colors, corners and materials.

## Widgets

| Widget | Shows |
|---|---|
| **LiveBox** | CPU / MEM / DISK usage with a live chart (per-core CPU lines) and top processes (CPU/MEM tabs); metric rows and chart lines turn amber/red past each metric's own warn/alarm thresholds; the large widget can list per-volume disk rows (internal + external volumes) instead of the aggregate DISK row; the process list refreshes at your chosen cadence (default 15s); an optional thermal-pressure row (off by default) shows the system state as NOMINAL/FAIR/SERIOUS/CRITICAL |
| **OpenBox** | opencode usage: today's in/out tokens + cost, 14-day chart (tokens or cost-per-day stacked by model), top models, tool usage counts, top sessions by tokens; in remote mode a failed fetch says why |
| **NetBox** | per-interface up/down rates, history chart, most active interfaces; rates turn amber/red past your warn/alarm thresholds |
| **BatBox** | battery level, time remaining, charge state, level chart |
| **GitBox** | commits per day (14 days), today's count, streak, active repos |
| **DevBox** | open TCP listening ports (process + port) and running Docker containers (CPU/mem) |
| **ClipBox** | clipboard history: recent copies with previews, item kinds, relative times |
| **HomeBox** | weather for your location (conditions + 3-day forecast) and a world clock; a failed fetch says why |
| **ShipBox** | GitHub Actions run status for a repo: status dots, durations, totals; a failed fetch says why |
| **TaskBox** | Azure DevOps work items assigned to you: overdue / due-soon counts and the next few items with due-day dots; a failed fetch says why |

All ten come in **small / medium / large** sizes.

## Install

**Requires signing with an Apple developer identity** (the system refuses
self-signed/ad-hoc widget extensions — `pluginkit` won't register them; a free
Apple ID works):

```bash
xcodegen generate --spec native/project.yml
xcodebuild -project native/Deck.xcodeproj -scheme DeckApp -configuration Release \
  -derivedDataPath native/build.noindex -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build

cp -R native/build.noindex/Build/Products/Release/Deck.app /Applications/
open /Applications/Deck.app     # first run installs the refresh agent
pluginkit -m -i com.deck.app.widgets   # verify the extension registered
```

Then: right-click desktop → **Edit Widgets…** → search "Deck" → add
LiveBox/OpenBox/NetBox/BatBox/GitBox/DevBox/ClipBox/HomeBox/ShipBox/TaskBox.

## Settings

Settings live in the **Deck app** (one tab per widget): show/hide chart,
metrics, lists; colors; counts; OpenBox token + server URL (remote mode);
GitBox repo paths + scan depth. Changes apply to the widgets immediately.

- **OpenBox remote mode:** set a Server URL (e.g. `http://host:4096`) and paste
  your own token — no default token is ever sent, and without a pasted token
  remote mode fetches nothing (it won't fall back to the local DB). OpenBox
  then fetches usage over HTTP from an `opencode serve` instance (basic auth,
  username `opencode`). The chart can switch between token lines and a
  cost-per-day view stacked by model (OpenBox tab → "Cost-per-day chart", off
  by default). The large face can also list the top sessions of the last 14
  days by tokens (OpenBox tab → "Show sessions", off by default).
- **LiveBox** reads mach, getifaddrs-style samplers and IOKit directly inside
  the widget — including the optional thermal row, which reads
  `ProcessInfo.thermalState` (a coarse pressure level, not a temperature: macOS
  exposes no fan speed or degrees without private SMC access); the top-process rows come from the background agent (ps) and
  refresh at your "Process refresh" interval (5–60s, default 15s — the widget
  tick and the fast process agent `com.deck.agent.processes` follow it).
- **NetBox** reads only the interface you pin in settings (default: automatic
  "most active" pick — pinning falls back to automatic while that interface is
  offline). Rates past your warn/alarm thresholds (MB/s, NetBox tab) turn
  amber/red; idle or no-reading rates are never tinted.
- **GitBox** reads only the repo paths you configure (empty by default — add
  comma-separated paths in settings).
- **ClipBox** history lives local-only in the widget container (plaintext, up
  to 20 items); clear it from the ClipBox settings tab.
- **HomeBox** fetches weather from wttr.in via the agent (empty location = auto
  geolocate); timezone rows are local-only (`local` = your zone).
- **ShipBox** needs a repo (`owner/repo`) and a GitHub token in settings —
  without a token nothing is fetched (the token goes only to api.github.com
  over TLS). Runs refresh via the agent every 60s.
- **TaskBox** needs an Azure DevOps organization, a project and a personal
  access token in settings — without all three nothing is fetched (the token
  goes only to dev.azure.com over TLS, and a read-only *Work Items (Read)*
  scope is enough). It shows work items assigned to whoever owns the PAT, not
  whoever is signed in to the browser. Azure DevOps has no universal due-date
  field, so the due day is resolved from `DueDate`, then `TargetDate`, then the
  end of the item's sprint; items with none of those show `—` and the header
  counts fall back to *"N open"*. Refreshes via the agent every 60s.
- **When a fetch fails**, ShipBox, TaskBox, HomeBox and OpenBox (remote mode) say why in
  one short line instead of a generic "no data": *"Add a repo + token in
  settings"* (nothing configured), *"Check repo + token"* / *"Check the
  location"* (credentials or target wrong — 401/403/404), *"Can't reach
  GitHub"* (offline, rate-limited, or the service is down), *"Unexpected
  GitHub response"* (reached it, couldn't parse it). If the background agent
  itself hasn't run for half an hour the line reads *"Agent hasn't run"*.
  These widgets no longer blank out data that has gone stale — whatever was
  last fetched stays on screen with its timestamp and the reason, so a broken
  token never silently empties a widget that was working a minute ago. The
  reason clears itself on the next successful fetch. The same reason appears in
  the widget's settings tab as a full sentence, right under the field that
  causes it, and clears the moment you edit that field.

## How it works

- **Self-sampled widgets** (LiveBox/NetBox/BatBox) read mach, getifaddrs and
  IOKit directly inside the widget — no other process needed.
- **Agent-pumped data** (OpenBox, process list, GitBox, ClipBox, weather, ShipBox,
  TaskBox): the widget
  sandbox forbids subprocesses and reading other apps' data, so a silent CLI
  (`DeckAgent`, embedded in the app) runs every 60s via a LaunchAgent and
  writes snapshots the widgets render. The top-process snapshot is sampled
  faster by a dedicated LaunchAgent (`com.deck.agent.processes`, default 15s).
  ClipBox captures the pasteboard on each tick — consecutive copies within a
  minute collapse to the newest.
- Everything refreshes on a ~60s cadence (WidgetKit throttles faster requests
  on macOS).

## Troubleshooting

**Every widget shows grey placeholder blocks instead of text** (charts still
draw, all sizes affected). LaunchServices is resolving `com.deck.app` to a
stale dev build — chronod rejects every render with `bundleStubNotSupported` /
"Bundle version did not match". Run:

```bash
scripts/lsclean.sh    # unregisters dev copies, re-registers /Applications/Deck.app, restarts chronod
```

Building into `native/build.noindex` (as above) keeps new dev copies from being
registered in the first place.

**A widget says "Check repo + token" or "Agent hasn't run".** That is the
widget reporting the last fetch, not a bug: fix the token/repo/location in Deck
settings (the app refreshes immediately, so the line clears within seconds), or
check the agent is loaded with `launchctl list | grep com.deck.agent`. Reasons
are recorded per source in `fetch-{shipbox,weather,opencodeRemote}.json` inside
the widget container.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.deck.agent
launchctl bootout gui/$(id -u)/com.deck.agent.processes
rm -f ~/Library/LaunchAgents/com.deck.agent.plist
rm -f ~/Library/LaunchAgents/com.deck.agent.processes.plist
rm -rf /Applications/Deck.app
```

## CI & Releases

- **CI**: every push/PR runs the workflow in `.github/workflows/deck.yml` —
  installs xcodegen, generates the project, and builds Release. With the signing
  secrets configured it signs and auto-provisions; without them it builds
  unsigned (compile check only — unsigned widgets can't register in `pluginkit`).
- **Releases**: push a `v*` tag (e.g. `git tag v1.3 && git push origin v1.3`) to
  build, sign, and upload `Deck-macos.zip` (with SHA256) to a GitHub Release.
  Required secrets: `APPLE_CERT_P12_BASE64`, `APPLE_CERT_PASSWORD`, `APPLE_ID`,
  `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` (see the workflow header).

## Development

```bash
xcodegen generate --spec native/project.yml   # after project.yml changes
                                              # AND after adding any source file
xcodebuild -project native/Deck.xcodeproj -scheme DeckApp -configuration Release \
  -derivedDataPath native/build.noindex build         # build
```

The Xcode project regenerates from `native/project.yml` (DeckApp host,
DeckWidgets extension, DeckAgent CLI, Shared models).

**Soak test:** `scripts/soak.sh` stresses the agent write paths (400 agent
runs + 50 overlapping launches, JSON integrity + exit-code assertions) and
runs in a few minutes; it isolates the LaunchAgents and the snapshot
container during the run and restores them afterwards. For the full 24h
stability soak see `docs/planning/crash-robustness-pass/runbook-24h.md`.
