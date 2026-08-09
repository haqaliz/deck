# deck — macOS desktop widgets

A collection of small, beautiful macOS desktop widgets — floating glass cards
with native material look that sit **behind** your windows, like native desktop
widgets. Flip any card (gear icon) to configure it.

## LiveBox — system monitor

- **Line chart** — live CPU / MEM / DISK usage (last 90 seconds, 1s updates)
- **Top 3 processes** — switchable tabs: by **CPU** or by **MEM** (up to 20, scrollable)
- Flip card settings (gear icon): hide sections/lines, colors, process count, launch at login
- Drag it anywhere; right-click → Close

```bash
swift run LiveBox
```

Options: `--corner tl|tr|bl|br`, `--margin N`, `--click-through`, `--debug-flip`.
Settings persist to `~/Library/Application Support/LiveBox/settings.json`.

## OpenBox — opencode token usage

Same shell, showing **opencode usage metrics** read from the local opencode
database (`opencode db`):

- **Header** — today's INPUT / OUTPUT tokens and COST
- **Chart** — daily input/output tokens over the last 14 days
- **Models** — top 3 models by cost, parsed into provider / id / variant with a badge
- **Footer** — all-time totals (local) or 14-day window totals (remote)
- Flip card settings: **Server URL** + **Server password** (basic auth,
  username `opencode`; password defaults to `OPENCODE_TOKEN` env), refresh
  interval (5/10/30/60s), colors

**Remote mode:** set a Server URL (e.g. `http://host:4096`) and OpenBox fetches
usage over HTTP from an `opencode serve` instance instead of the local DB —
set `OPENCODE_SERVER_PASSWORD` when starting the server, then enter the same
password in the widget. Remote mode shows 14-day window totals (`14D` label).

```bash
swift run OpenBox --corner tl
```

Options: `--corner tl|tr|bl|br`, `--margin N`, `--click-through`.
Settings persist to `~/Library/Application Support/OpenBox/settings.json`.

## NetBox — network monitor

Same shell, showing **live per-interface network rates** read from the local
system counters (`getifaddrs`):

- **Header** — UP / DOWN rates for the most active interface
- **Chart** — rolling up/down speed lines (last 90 seconds, 1s updates)
- **Interfaces** — top interfaces by traffic (name, ↑ up / ↓ down), virtual
  interfaces (utun, awdl, lo, …) excluded
- Flip card settings: show chart/interfaces, interface count, up/down colors,
  launch at login

```bash
swift run NetBox
```

Options: `--corner tl|tr|bl|br`, `--margin N`, `--click-through`, `--debug-flip`.
Settings persist to `~/Library/Application Support/NetBox/settings.json`.

## Shared behavior

- Native material look (`.ultraThinMaterial`), 22pt rounded corners, hairline border
- Window level `.normal` — widgets stay **behind app windows**, like desktop widgets
- Draggable from anywhere, right-click menu to close
- Initial position follows the display under your cursor

## Native widget (`native/`)

A real WidgetKit widget (CPU/MEM/DISK with a rolling chart and top processes) —
native colors/borders, lives in the Notification Center **widget gallery**, and
can be placed on the desktop behind windows (right-click desktop → Edit Widgets).

**Requires signing with an Apple developer identity** (the system refuses
self-signed/ad-hoc widget extensions — `pluginkit` won't register them):

1. `open native/LiveBox.xcodeproj`
2. In Xcode: LiveBoxApp target → Signing & Capabilities → pick your Team
   (a free Apple ID works)
3. Run (Cmd+R) — the widget appears in the widget gallery
4. Add it: Notification Center → edit widgets, or right-click desktop → Edit Widgets

`xcodegen generate` (in `native/`) regenerates the project after `project.yml` changes.

## Development

```bash
swift build               # build all widgets
swift build -c release    # release build
swift run LiveBox         # run the system monitor
swift run OpenBox         # run the opencode usage widget
swift run NetBox          # run the network monitor widget
```

Both widgets share the same window/panel plumbing (see `Sources/*/AppMain.swift`).
