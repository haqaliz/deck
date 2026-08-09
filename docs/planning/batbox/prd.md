# BatBox — PRD

**Slug:** `batbox` · **Type:** widget · **Status:** approved
**Source:** `docs/planning/_card/issue.md` (deck-next handoff, 2026-08-09)

## 1. Ask

A battery monitor widget for the deck: copy the NetBox shell wholesale and add
one pure loader producing battery state from IOKit power-source APIs. Front
face mirrors NetBox (header metrics, rolling level chart, status list); back
face has the standard toggles/colors.

## 2. User-visible spec

### Front face (what the user reads at a glance — 4 elements)

1. **Header** — two metric labels. `LEVEL` with the current percent
   (   `71%`) and a color dot that shifts by charge: green > 50%, amber 20–50%,
   red < 20% (the threshold shift applies to the header dot only — the chart
   line always uses the picked Level color). `TIME` with remaining time (`6h 34m`) — "to full" when charging,
   "full" when charged, `—` when unknown. Gear icon pinned right (shell pattern).
2. **Chart** — rolling 90-sample (1s) line chart of battery level %,
   single series in the level color, fixed Y domain `0...100` (percent is
   bounded — unlike NetBox's auto-scaled byte rates). History is self-sampled
   from launch, so the line grows from the right edge (never stitches in
   pre-launch state; a fresh launch shows a short line, not a full one).
3. **Divider** — matching NetBox.
4. **Status list** — three rows (no scroll, fixed height):
   - **State** — `Charging` / `Discharging` / `Full` / `AC Power` (plugged, full)
   - **Time** — remaining or to-full, same string as the header
   - **Cycles** — cycle count (`107`)
   Rows show a label + value; value colored with the level color. When a value
   is unknown (e.g. no cycle count on a desktop), the row shows `—`.

**No-battery state (desktop / iMac):** header shows `LEVEL —` and `TIME —`,
chart and list hidden, widget keeps ticking and stays settings-accessible.
Same shape as NetBox's empty state (header `0 B/s`, flat chart).

### Back face (settings)

| Control | Default | Behavior |
|---|---|---|
| Show chart | on | Hides chart + header metric labels (mirrors NetBox) |
| Show status | on | Hides the status list |
| Level color | green | Color picker (shell metricRow pattern) |
| Open at startup | off | LaunchAgent toggle, shown only when no native widget (shell pattern) |

No level threshold pickers — the green/amber/red dot shift is fixed.

## 3. Data source

- **Loader**: IOKit power-source APIs — `IOPSCopyPowerSourcesInfo` /
  `IOPSGetPowerSourceDescription` (pure C, no subprocess). Read keys:
  `kIOPSPowerSourceStateKey` (Battery/AC), `kIOPSCurrentCapacityKey`,
  `kIOPSMaxCapacityKey` → level %, `kIOPSIsChargingKey`, `kIOPSIsChargedKey`,
  `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey`, `kIOPSBatteryCycleCountKey`.
  Verified on this machine (`pmset -g batt`: 71%, discharging, 6:34 remaining,
  cycle count 107 via `system_profiler SPPowerDataType`).
- **Phase 0 spike (DONE, 2026-08-09)**: IOKit power-source dictionary exposes
  everything except the cycle count (only `DesignCycleCount`). Keys verified:
  `Current Capacity`/`Max Capacity`, `Is Charging`, `Power Source State`,
  `Time to Empty` (seconds), `Time to Full Charge` (0 when not charging —
  treat 0 as nil), `Is Present`. Cycle count fallback verified:
  `ioreg -rn AppleSmartBattery` prints `"CycleCount" = 107` in ~13ms (chosen
  over `system_profiler SPPowerDataType` — 143ms+ and slower cold; both are
  local subprocess, same class as LiveBox's `ps`).
- **Pure logic**: level % = current/max, time-minute formatting, state
  classification, cycle-count parsing — all in `BatBoxCore` (unit-testable).
  Loader passes the raw dictionary values into the core; core does the math.
- **Cadence**: 1s via the shell `MetricsStore` timer (history capacity 90,
  mirroring LiveBox/NetBox).
- **Missing/unknown keys**: a key absent (or not a number) → that field is
  `nil` → header/row shows `—`; never a crash, widget keeps ticking.
- **Empty state**: no battery → all fields nil → no-battery card per §2.

## 4. Shell fit

Copied files from `Sources/NetBox/` (renamed `NetBox` → `BatBox`, bundle ids
`com.netbox.*` → `com.batbox.*`): AppMain.swift, Settings.swift,
SettingsView.swift, MetricsStore.swift, ContentView.swift,
NativeWidgetDetector.swift. New loader file `Sources/BatBox/BatteryMetrics.swift`;
new pure library `Sources/BatBoxCore/` (models, math, formatters) + test target
`Tests/BatBoxCoreTests` — the NetBox/NetBoxCore split (git log be2e2aa).

**No shell-invariant deviations.** Panel level `.normal`, 22pt corner mask, top
padding 36 (≥ 28, calibrated live against NetBox: the shell's dynamic-height
path eats a content-dependent slice of declared top padding, and BatBox's
short content eats the most — 36 declared yields the same visible ~13pt card
gap as NetBox's 28), dynamic height via `PanelHeightKey` + `.frame(width: 368,
height: panelHeight)`, card style `.fill(.clear).background(.ultraThinMaterial)
.clipShape(RoundedRectangle(22)).overlay(hairline)` — all untouched. Two
content-only differences: fixed 0...100 chart Y domain (percent is bounded),
and a fixed three-row status list (no scroll — one view-height constant, no
`interfaceListHeight` logic needed).

## 5. Non-goals

- No time-to-empty *prediction* model (uses the system estimate as-is).
- No charge/discharge *rate* (watts/mA) series or derived estimate.
- No health condition line (replace your battery state) or temperature.
- No low-battery notifications, no dock/status-bar integration.
- No manual refresh interval control (fixed 1s, matches LiveBox/NetBox).
- No AC-power history or per-adapter info (that's a power widget, not battery).

## 6. Open questions

None blocking — resolved in interview: status list = State/Time/Cycles; chart =
level only; no-battery = empty-state card; header = LEVEL + TIME.

## 7. Verification

- `swift test` — BatBoxCoreTests: level math (percent clamp, division by zero),
  time formatting (minutes → `6h 34m` / `45m`, nil → `—`), state classification
  (charging/discharging/full/AC), cycle parsing (Int, nil, garbage).
- Phase 0 spike: IOKit dictionary exposes cycle count + time sentinel (else
  `system_profiler` fallback per §3).
- `swift build -c release`; `swift run BatBox --debug-flip`; window-bounds
  check via CGWindowList; corners rounded; sits behind windows.
- `swift run BatBox --debug-render <path>` uses BatBox's own front height
  constant (the NetBox copy hardcodes 358 — adjust, don't inherit).
- `swift run BatBox --click-through` still drag-free and transparent to mouse.
- Live run: confirm header matches `pmset -g batt` values on this machine.
