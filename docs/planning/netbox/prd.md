# NetBox — PRD

**Slug:** `netbox` · **Type:** widget · **Status:** approved
**Source:** `docs/planning/_card/issue.md` (deck-next handoff, 2026-08-09)

## 1. Ask

A network monitor widget for the deck: copy the LiveBox shell wholesale and add
one pure loader producing per-interface up/down byte rates from local system
counters. Front face mirrors LiveBox (header metrics, rolling speed chart,
interface list); back face has the standard toggles/colors.

## 2. User-visible spec

### Front face (what the user reads at a glance — 4 elements)

1. **Header** — `UP` / `DOWN` metric labels for the **most active interface**
   (highest recent traffic), formatted rates (e.g. `↑ 1.2 MB/s`, `↓ 340 KB/s`),
   each with its color dot. Gear icon pinned right (shell pattern).
2. **Chart** — rolling 90-sample (1s) line chart of the same interface's
   up and down rates, two series in the up/down colors. Y domain
   `0...max(1, peak)` (explicit floor so a flat-0 series never collapses the
   scale; no fixed 0...100 since byte rates are unbounded). History reseeds
   when the top interface switches (never stitch two interfaces' series).
3. **Divider** — matching LiveBox.
4. **Interface list** — top N interfaces by recent traffic (`en0` Wi-Fi, `en5`
   Thunderbolt, …), each row: name, `↑ rate`, `↓ rate`. Excluded interfaces
   (lo0, utun*, awdl*, …) never appear.

### Back face (settings)

| Control | Default | Behavior |
|---|---|---|
| Show chart | on | Hides chart + header metric labels (mirrors LiveBox) |
| Show interfaces | on | Hides the list |
| Interfaces count | 3 | Stepper 1...10, like LiveBox processCount |
| UP color | green | Color picker (shell metricRow pattern) |
| DOWN color | cyan | Color picker |
| Open at startup | off | LaunchAgent toggle, shown only when no native widget (shell pattern) |

## 3. Data source

- **Loader**: `getifaddrs()` (Darwin, AF_LINK entries) → per-interface
  `ifi_ibytes` / `ifi_obytes` byte counters. Same class as LiveBox's mach calls
  (`CpuTicks.sample()`, Metrics.swift:14-42) — no subprocess, no network.
- **Rates**: deltas between consecutive 1s samples, computed in pure
  `NetBoxCore` math (unit-testable). First sample seeds the baseline, like
  `cpuUsagePercent(previous:)` (Metrics.swift:46-53).
- **Cadence**: 1s via the shell `MetricsStore` timer (history capacity 90,
  mirroring LiveBox).
- **Counter reset/wrap**: any negative delta is treated as a reset — rate 0 for
  that tick and the baseline reseeds (avoids a spurious massive rate).
- **Interface filter (default)**: include physical `en*`; exclude `lo0`, `utun*`,
  `awdl*`, `llw0`, `anpi*`, `ap*`, `bridge*`, `vboxnet*`, `vmnet*`.
- **Empty state**: no counters (or only excluded interfaces) → header shows
  `0 B/s`, chart flat at 0, list hidden; widget keeps ticking.
- **Phase 0 spike (before implementation)**: verify `getifaddrs` AF_LINK
  `ifa_data` populates `ifi_ibytes`/`ifi_obytes` on this macOS via a tiny
  scratch snippet; fallback if it doesn't: `netstat -ib` subprocess parsing
  (still local-first, parser moves to NetBoxCore).

## 4. Shell fit

Copied files from `Sources/LiveBox/` (renamed `LiveBox` → `NetBox`, bundle ids
`com.livebox.*` → `com.netbox.*`): AppMain.swift, Settings.swift,
SettingsView.swift, MetricsStore.swift, ContentView.swift. New loader file
`Sources/NetBox/Metrics/NetworkMetrics.swift`; new pure library
`Sources/NetBoxCore/` (models, rate math, filtering, formatters) + test target
`Tests/NetBoxCoreTests` — the OpenBox/OpenBoxCore split (git log d7770ee).

**No shell-invariant deviations.** Panel level `.normal`, 22pt corner mask, top
padding 28, dynamic height via `PanelHeightKey` + `.frame(width: 368, height:
panelHeight)`, card style
`.fill(.clear).background(.ultraThinMaterial).clipShape(RoundedRectangle(22))
.overlay(hairline)` — all untouched. One chart-only difference: Y domain
auto-scales instead of 0...100 because byte rates are unbounded.

## 5. Non-goals

- No network interface picker in settings (auto-filter + most-active only).
- No ping/latency, no connection health, no per-app bandwidth.
- No packet counters, errors, or WiFi signal info.
- No DockBox-style port listing (that's DevBox's story).
- No manual refresh interval control (fixed 1s, matches LiveBox).

## 6. Open questions

None blocking — resolved in interview: header/chart bind to the most active
interface; list shows top N by traffic.

## 7. Verification

- `swift test` — NetBoxCoreTests: rate math (delta, reset/wrap), filter
  exclusion table, formatter (B/s → B/s/KB/s/MB/s/GB/s), most-active pick.
- Phase 0 spike: `getifaddrs` populates byte counters (else `netstat -ib`
  fallback per §3).
- `swift build -c release`; `swift run NetBox --debug-flip`; window-bounds
  check via CGWindowList; corners rounded; sits behind windows.
- `swift run NetBox --click-through` still drag-free and transparent to mouse.
