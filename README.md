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
| **LiveBox** | CPU / MEM / DISK usage with a live chart (per-core CPU lines) and top processes (CPU/MEM tabs) |
| **OpenBox** | opencode usage: today's in/out tokens + cost, 14-day chart, top models, tool usage counts |
| **NetBox** | per-interface up/down rates, history chart, most active interfaces |
| **BatBox** | battery level, time remaining, charge state, level chart |
| **GitBox** | commits per day (14 days), today's count, streak, active repos |
| **DevBox** | open TCP listening ports (process + port) and running Docker containers (CPU/mem) |

All five come in **small / medium / large** sizes.

## Install

**Requires signing with an Apple developer identity** (the system refuses
self-signed/ad-hoc widget extensions — `pluginkit` won't register them; a free
Apple ID works):

```bash
xcodegen generate --spec native/project.yml
xcodebuild -project native/Deck.xcodeproj -scheme DeckApp -configuration Release \
  -derivedDataPath native/build -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build

cp -R native/build/Build/Products/Release/Deck.app /Applications/
open /Applications/Deck.app     # first run installs the refresh agent
pluginkit -m -i com.deck.app.widgets   # verify the extension registered
```

Then: right-click desktop → **Edit Widgets…** → search "Deck" → add
LiveBox/OpenBox/NetBox/BatBox/GitBox/DevBox.

## Settings

Settings live in the **Deck app** (one tab per widget): show/hide chart,
metrics, lists; colors; counts; OpenBox token + server URL (remote mode);
GitBox repo paths + scan depth. Changes apply to the widgets immediately.

- **OpenBox remote mode:** set a Server URL (e.g. `http://host:4096`) + token
  and OpenBox fetches usage over HTTP from an `opencode serve` instance instead
  of the local database (basic auth, username `opencode`).
- **GitBox** scans `~/dev` by default; add comma-separated paths in settings.

## How it works

- **Self-sampled widgets** (LiveBox/NetBox/BatBox) read mach, getifaddrs and
  IOKit directly inside the widget — no other process needed.
- **Agent-pumped data** (OpenBox, process list, GitBox): the widget sandbox
  forbids subprocesses and reading other apps' data, so a silent CLI
  (`DeckAgent`, embedded in the app) runs every 60s via a LaunchAgent and
  writes snapshots the widgets render.
- Everything refreshes on a ~60s cadence (WidgetKit throttles faster requests
  on macOS).

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.deck.agent
rm -f ~/Library/LaunchAgents/com.deck.agent.plist
rm -rf /Applications/Deck.app
```

## Development

```bash
xcodegen generate --spec native/project.yml   # after project.yml changes
xcodebuild -project native/Deck.xcodeproj -scheme DeckApp -configuration Release \
  -derivedDataPath native/build build         # build
```

The Xcode project regenerates from `native/project.yml` (DeckApp host,
DeckWidgets extension, DeckAgent CLI, Shared models).
