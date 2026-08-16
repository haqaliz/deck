# PRD: netbox-interface-picker

Slug: `netbox-interface-picker` · Source: deck-next handoff + inline brief
(`docs/planning/_card/issue.md`) · 2026-08-15

## Ask (restated)

Let the user pin NetBox to one network interface (a manual override of the auto
"most active" pick), chosen from a picker in the NetBox settings tab, with the
auto pick as the default.

## User-visible spec

### Front face (unchanged layout, one behavior change)

- **Small**: DOWN / UP rows (totals) + "ACTIVE <name>" row. When pinned, totals
  and the ACTIVE row show the pinned interface; ACTIVE shows its name.
- **Medium / large**: DOWN / UP rows, optional chart, optional interfaces list.
  When pinned, totals, chart history, and the list all show **only the pinned
  interface** (one list row). The "INTERFACES" section title stays; the
  interfaceCount stepper is moot while pinned (list has 1 row).
- Default (nothing pinned): exactly today's behavior — totals sum all sampled
  interfaces, list shows the top-N most active.

### Settings (back face, NetBox tab)

- New **"Interface"** section in `NetBoxSettingsView` with a `Picker`:
  - "Automatic (most active)" — tag `nil` — the default.
  - One row per sampled interface with real traffic (loader already excludes
    lo/utun/awdl/etc.; additionally skip interfaces with zero rx+tx bytes).
  - The option list is refreshed on each appearance of the tab (`.onAppear`),
    sampled with `NetworkMetricsLoader.sample()` from the host app.
  - If the pinned interface is no longer present (renamed/removed), append it
    as a "`<name>` (offline)" row so the picker keeps showing the stored
    selection (a SwiftUI `Picker` bound to `String?` shows blank when the
    selection matches no tag); the stored value is untouched until the user
    changes it.

## Data source

- Purely the existing `getifaddrs` path already sampled in-process by the
  widget (`NetworkMetricsLoader.sample()` → `InterfaceRates` from two byte
  counter samples 60s apart). Sandbox-safe, no agent, no snapshot, no HTTP.
- Refresh cadence unchanged: timeline reload every 60s, previous-sample
  persisted in UserDefaults.
- **Unavailable/empty states**: first sample (no previous bytes) already shows
  "Sampling…"; pinned-interface-vanished falls back to auto (below).

## Selection logic (new, pure, in Shared)

`NetBoxPinnedInterface.select(pinned: String?, interfaces: [InterfaceRates])`:

1. `pinned` nil/empty → return `interfaces` unchanged (auto).
2. Otherwise filter to `interfaces.filter { $0.name == pinned }`.
3. If the filtered result is empty (pinned interface vanished, e.g. Wi-Fi off)
   → return `interfaces` unchanged (auto fallback).

The provider applies this before computing totals, history, and the interface
list, so all three follow the pin consistently.

## Shell fit

- **Reuse**: `NetBoxWidget.swift` provider + views (only the totals/history/list
  inputs change), `NetBoxSettings` tolerant-decode pattern, `NetBoxSettingsView`
  form style, DeckSharedTests pattern.
- **One deliberate refactor**: move `InterfaceSample`, `NetworkMetricsLoader`,
  and `NetBoxFormatters` from `DeckWidgets/Loaders/NetworkMetrics.swift` into
  `Shared/NetBoxCore.swift` (mirrors the existing `Shared/LiveBoxCore.swift`
  pattern). Required because the host app must enumerate interfaces for the
  picker and the host target compiles only `Shared`; it also finally makes
  `formatRate` testable in DeckSharedTests (was on ROADMAP's deferred-test
  list). Both the app and the widget targets already compile `Shared`, so no
  project.yml change.
- **No deviation** from shell invariants (material card, sizes, cadence).

## Non-goals

- No agent changes, no snapshot changes, no HTTP.
- No per-interface error counters or packet counts (separate backlog item).
- No threshold coloring on rates (separate backlog item).
- No NetBox widget-side editing UI (settings live in the app only).

## Open questions

- None — both flagged design points were confirmed with the user: pinned scope
  is "only the pinned interface", and the loader move to Shared is approved.

## Acceptance

- [ ] Picker in NetBox settings tab: "Automatic (most active)" default + real
      interface rows, refreshed on tab appear, virtual/zero-traffic skipped.
- [ ] Pin an interface → small ACTIVE row, totals, chart history, and the list
      all show only that interface.
- [ ] Pinned interface disappears from the sample → widget falls back to auto
      (totals of all), stored setting untouched.
- [ ] Nothing pinned → byte-identical behavior to today (totals sum all, top-N
      list).
- [ ] Old settings.json without the new key decodes with defaults (tolerant
      decode) — unit test.
- [ ] `NetBoxPinnedInterface.select` unit tests (auto, pin present, pin absent
      → fallback, empty string).
- [ ] `formatRate` tests ported into DeckSharedTests.
- [ ] Build + install, re-add NetBox from the gallery, all three sizes render.
