# BatBox Bluetooth accessories — PRD

## Ask

Show battery levels for connected Bluetooth accessories (mouse, keyboard,
AirPods) in BatBox, the way the native macOS Batteries widget does.
Slug: `batbox-accessories`.

Source: inline brief. Prior finding: `IOPSCopyPowerSourcesList` returns exactly
one power source on this machine (the internal battery), so accessories are
not reachable through the API BatBox already uses.

## Data source

Measured, not assumed:

| Source | Cost | Covers | Sandbox |
|---|---|---|---|
| `system_profiler SPBluetoothDataType -json` | 50–120ms | everything, incl. AirPods cells | subprocess → agent only |
| IORegistry `BatteryPercent` | ~10ms | Apple HID only (Magic Mouse/Keyboard/Trackpad) | works in-widget |

**Chosen: `system_profiler` via DeckAgent.** It covers AirPods, which the
IORegistry key does not, and at ~60ms it is cheaper than the `docker ps`
DevBox's agent already runs — so the usual reason to prefer an in-process
IOKit read does not apply. Rejecting the IORegistry option also avoids
maintaining two parsers whose coverage overlaps.

Payload shape (verified on this machine):
`SPBluetoothDataType[0]` holds `controller_properties`, plus
`device_connected` and/or `device_not_connected` — each a list of
single-key dicts mapping display name to a field dict. **`device_connected`
is absent entirely when nothing is connected**; that must not be treated as
an error.

Refresh: 60s, with the rest of the agent's snapshots.

## Architecture: hybrid, deliberately

BatBox keeps reading the Mac's own battery from IOKit **inside the widget**
and gains accessories from an agent snapshot. Moving everything to the agent
for uniformity was considered and rejected: BatBox currently works with the
agent stopped, and that robustness is worth more than tidiness. If the agent
dies, the Mac battery keeps ticking and only the accessory section goes stale.

BatBox therefore becomes the first widget spanning **both** data paths.
CLAUDE.md describes the two-path split as a property of whole widgets, so that
description needs updating.

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
| Low threshold (%) | 20 |

The low threshold drives the dot colour (amber/red) and the small face's
`LOW` figure, reusing the existing `ThresholdTier` colour language rather
than inventing a second one.

## States

Three distinct outcomes, none of them a blank section:

- Agent never ran, or the snapshot is older than its max age →
  `Waiting for the Deck agent…`, matching the other agent-pumped widgets.
- Agent ran, nothing connected → the section is hidden entirely, not an
  empty header.
- Bluetooth off → indistinguishable from nothing connected, and deliberately
  not special-cased.

A disconnected device disappears on the next refresh rather than lingering
at a stale percentage.

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
