# NetBox — inline brief

Source: `deck-next` handoff (2026-08-09), pick: `netbox`.

Build NetBox, a network monitor widget for the deck — M3 candidate in
ROADMAP.md. Copy the LiveBox shell wholesale (`Sources/<Widget>/*`: AppMain,
Settings, SettingsStore, MetricsStore, ContentView, SettingsView) and add one
pure loader using getifaddrs/netstat byte counters for per-interface up/down
speeds. Front face mirrors LiveBox: header (current up/down rate), rolling
speed chart, interface list; back face has the standard toggles/colors. Keep
every panel invariant from CLAUDE.md (level `.normal`, 22pt rounded mask,
dynamic height via PanelHeightKey, material-as-background card style) and
register in README/ROADMAP/Package.swift.

## Constraints from the pick

- Shell untouched in behavior: panel invariants in CLAUDE.md (level `.normal`,
  rounded mask, dynamic height via PanelHeightKey, card style).
- Pure loaders, stores own timers, views own layout.
- Caveat to resolve in the PRD: speeds are deltas of monotonic counters —
  decide default interface filtering (exclude utun/awdl/vboxnet) and
  counter-reset handling up front.
