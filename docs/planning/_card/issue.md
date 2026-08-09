# BatBox — inline brief

Source: `deck-next` handoff (2026-08-09), pick: `batbox`.

Build BatBox, a battery monitor widget — M3 candidate in ROADMAP.md:43. Copy
the LiveBox/NetBox shell wholesale (`Sources/<Widget>/*`: AppMain, Settings,
SettingsStore, MetricsStore, ContentView, SettingsView) and add one pure loader
via IOKit/pmset for level, time remaining, cycle count, and charging state.
Front face mirrors NetBox: header metrics, rolling charge-level chart, and a
short status list; back face uses the standard toggles/colors. Keep every panel
invariant from CLAUDE.md (level `.normal`, 22pt rounded mask, dynamic height via
PanelHeightKey, material-as-background card style) and register in
README/ROADMAP/Package.swift.

## Constraints from the pick

- Shell untouched in behavior: panel invariants in CLAUDE.md (level `.normal`,
  rounded mask, dynamic height via PanelHeightKey, card style).
- Pure loaders, stores own timers, views own layout.
- Caveat to resolve in the PRD: there is no system battery-history API —
  history must be self-sampled (seeds at launch), and define the
  desktop-no-battery empty state up front.
