# BatBox Bluetooth accessories — PRD

## Ask

Show battery levels for connected Bluetooth accessories (mouse, keyboard,
AirPods) in BatBox, the way the native macOS Batteries widget does.
Slug: `batbox-accessories`.

Source: inline brief. Prior finding: `IOPSCopyPowerSourcesList` returns exactly
one power source on this machine (the internal battery), so accessories are
not reachable through the API BatBox already uses.

## Data source — REVISED after the spike

The original draft chose `system_profiler SPBluetoothDataType -json` via
DeckAgent. **That was wrong, and the spike disproved it.** With an MX Master 3S
actually connected, `system_profiler` reports no battery keys at all — only
address, firmware, minor type and vendor/product IDs. IORegistry's
`BatteryPercent` is likewise empty. Both candidate sources return nothing for
a real device.

`pmset -g accps` *does* show it, which pointed at the true source:

```
-MX Master 3S (id=37819294)	75%;
```

**Accessories are a first-class IOKit power-source type.** The original probe
missed them because `IOPSCopyPowerSourcesList` returns only the internal
battery. The by-type variant returns accessories:

```swift
@_silgen_name("IOPSCopyPowerSourcesByType")
func IOPSCopyPowerSourcesByType(_ type: Int32) -> Unmanaged<CFTypeRef>?
// 0 = all, 1 = internal, 2 = UPS, 3 = internal+UPS, 4 = accessories
```

Verified output for a connected mouse:

| Key | Value | Type |
|---|---|---|
| `Name` | `MX Master 3S` | String |
| `Current Capacity` | `75` | Number |
| `Max Capacity` | `100` | Number |
| `Low Warn Level` | `20` | Number |
| `Accessory Category` | `Mouse` | String |
| `Accessory Identifier` | `A3B7312D-…` | String |
| `Transport Type` | `Bluetooth LE` | String |
| `Power Source State` | `Battery Power` | String |

### What this changes

- **No subprocess, so no agent and no snapshot.** BatBox stays entirely on the
  self-sampled path. No `AccessorySnapshot`, no store, no `DeckAgent` block, no
  staleness plumbing — the whole of critique R3 evaporates.
- **Detection is automatic and live**, which is the requirement: the list is
  whatever IOKit reports at render time. Nothing is ever configured by hand.
- **`Low Warn Level` is the device's own threshold**, so the planned
  `lowThreshold` setting is unnecessary — use what the device reports.
- **`Accessory Category`** ("Mouse", "Keyboard", "Headphones") gives a real
  basis for an SF Symbol per row rather than a generic dot.
- Values are proper `NSNumber`s, not strings, so critique A2 (string-or-number
  parsing) does not apply to this source.

### The cost: this is SPI, not public API

`IOPSCopyPowerSourcesByType` is exported by IOKit — `pmset` links it — but is
**absent from the public SDK headers**, so it must be declared with
`@_silgen_name`. Consequences, stated plainly rather than buried:

- It can change or vanish in any macOS update, with no deprecation warning.
- It is not App Store safe. Deck ships via a personal signing identity and is
  not distributed, so this is acceptable *here* and would not be elsewhere.
- **Unverified:** whether the symbol resolves inside the sandboxed widget
  extension. `IOPSCopyPowerSourcesInfo` already works there and this is the
  same framework, so it very likely does — but "very likely" is exactly the
  kind of claim that cost hours earlier today. First implementation step is to
  prove it in the extension, not the host app.

Mitigation: treat a nil blob or unresolved symbol as "no accessories" and hide
the section. A macOS update that removes the symbol degrades BatBox to what it
does today rather than breaking it.

## User-visible spec

### Front face

- **Small** — one compact line under the existing level/state, e.g.
  `3 ACCESSORIES · LOW 12%`. Surfaces the number that matters without a list.
- **Medium / large** — an `ACCESSORIES` section: one row per device, name
  left, percent right, coloured dot. Row count capped by a setting; large
  shows more.
- AirPods and other multi-cell devices collapse to **one row at their lowest
  cell** — that is the figure that determines when they stop working.

### Identity

`device_address`, never the display name. Names are user-editable and do
duplicate in practice (this machine lists two `NuPhy Halo75 V2-1` entries at
different addresses). Name is for display only.

### Filtering

Only devices actually reporting a battery are shown. A connected device with
no battery keys is dropped rather than rendered as "—", which would make the
section mostly noise.

### Back face (BatBox settings tab)

| Control | Default |
|---|---|
| Show accessories | on |
| Accessory rows | 4 |

No low-threshold setting: each accessory reports its own `Low Warn Level`
(20 for the MX Master), which is more accurate than one global number and is
what the device manufacturer intends. Colour still comes from the shared
`ThresholdTier` language.

## States

Three distinct outcomes, none of them a blank section:

- Nothing connected → the section is hidden entirely, not an empty header.
- Bluetooth off → indistinguishable from nothing connected, and deliberately
  not special-cased.
- SPI unavailable (symbol gone after a macOS update) → also hidden, so BatBox
  degrades to its current behaviour rather than breaking.

There is no staleness state: the data is read live at render time, so a
disconnected device is simply absent from the next render.

## Shell fit

Reuses the shell unchanged: rounded system fonts, monospaced digits,
coloured-dot rows, section titles tracked 1pt. New files follow the seven
existing agent-pumped precedents (`AccessorySnapshot` + store in `Shared/`,
an agent block in `DeckAgent/main.swift`).

Two shell obligations from CLAUDE.md apply: `xcodegen generate` after adding
source files (a new test file that skips it is silently not compiled **and the
suite still reports success**), and a version bump — not strictly required
since no widget is added, but cheap insurance that the gallery re-reads the
descriptor.

## Non-goals

- No accessory battery *history* or charts.
- No notifications when an accessory runs low.
- No renaming or reordering accessories; system order is used.
- No non-Bluetooth peripherals (USB, Thunderbolt).
- No accessory data in any widget other than BatBox.

## Blocking dependency

**The parser cannot be written yet.** Battery keys appear only for
*connected* devices, and no accessory has been connected during any probe of
this machine. Every candidate key name — `device_batteryLevelMain`,
`device_batteryLevelLeft`, `device_batteryLevelRight`, `device_batteryLevelCase` —
is recalled, not observed.

Required before implementation: a real capture with a mouse/keyboard/AirPods
connected, committed to `SharedTests/Fixtures/bluetooth_connected.json`.
This repo already tests parsers against captured payloads (the wttr fixture);
guessing field names would produce a parser that compiles, passes invented
tests, and shows nothing on the desktop.

---

# Self-critique (Phase 4)

## 🔴 Red

**R1 — the parser has no verified input, and that is not a detail to fix
later.** Every battery key name in this document is recalled, not observed.
A parser fitted to guessed spellings compiles, passes tests written against
the same guesses, and renders an empty section forever — the exact failure
mode that cost hours during the container incident, where every check looked
healthy. *Fix:* treat the fixture as a hard prerequisite. No parser code
before `SharedTests/Fixtures/bluetooth_connected.json` exists, captured from
a real connected accessory.

**R2 — "lowest cell wins" silently discards which cell is low.** For AirPods
the case and the buds drain independently; `42%` when the case is at 42 and
the buds at 90 is actively misleading — the user reads it as "my AirPods are
about to die" and charges the wrong thing. *Fix:* keep the single row, but
label it with the cell when the minimum comes from a non-main cell — e.g.
`AirPods Pro  Case 42%`. Costs one short string, removes the wrong reading.

**R3 — BatBox has no staleness affordance today, and the PRD assumes one.**
The other agent-pumped widgets acquired their chip through `FetchStatus`;
BatBox never needed it because IOKit is always live. Adding a snapshot means
adding that plumbing to a widget that has none of it. *Fix:* scope it
explicitly — reuse `ProcessSnapshot`'s `writtenAt` + `maxAgeSeconds` shape
rather than the heavier `FetchStatus` machinery, which exists for *network*
failures (a why-did-the-fetch-fail reason string) that a local subprocess
does not have.

## 🟡 Amber

**A1 — `device_address` is stable, but is it present on every connected
device?** It appears on every entry in the not-connected list on this
machine, and the design keys identity on it. If a connected device ever
omits it the row would be dropped. *Fix:* fall back to the display name as
identity when the address is absent, and cover it in the fixture tests.

**A2 — percent may not be an integer, or even a number.** `system_profiler`
has historically emitted battery levels as strings (`"85%"`, `"85"`) rather
than numbers, and the shape varies by device class. *Fix:* the parser must
accept string-or-number and strip a trailing `%`, with fixture cases for
both. Do not assume `Int`.

**A3 — the small face's compact line competes for space.** BatBox small
already shows level, state and time. Adding `3 ACCESSORIES · LOW 12%` is a
fourth line on the smallest face. *Fix:* verify at the real font before
committing to it; if it crowds, drop to just the low figure (`LOW 12%`) and
hide it entirely when nothing is low.

**A4 — no test can run in CI.** Everything depends on a captured fixture and
on hardware being connected. The fixture makes the *parser* testable, but
nothing verifies that `system_profiler` still emits that shape on a future
macOS. *Fix:* accept it, and note in the plan that a macOS upgrade silently
changing the payload would show as an empty section, not an error — so the
"nothing connected" state and the "parse produced nothing" state should be
distinguishable in the agent's log even though they look identical on the
widget.
