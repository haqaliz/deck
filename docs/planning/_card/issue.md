# GitBox — inline brief

Source: `deck-next` handoff (2026-08-10), pick: `gitbox`.

Build GitBox, the M3 pending widget (ROADMAP.md:45) that shows today's git
activity across local repos: header with today's commit count + current streak,
a per-day commit chart (last 14 days), and a per-repo list with commit counts.
Copy the NetBox/BatBox shell wholesale (AppMain, Settings, SettingsStore,
MetricsStore, ContentView, SettingsView) and add a pure GitBoxCore loader
(git log / rev-list --count --since) with tests following the
BatBoxCore/NetBoxCore pattern. Resolve the repo-enumeration caveat in the PRD:
a settings path list (defaulting to a ~/dev scan) plus timezone-normalized
streak math. Keep every panel invariant from CLAUDE.md (level .normal, 22pt
rounded mask, PanelHeightKey dynamic height, material-as-background card style)
and register in README/ROADMAP/Package.swift.

## Constraints from the pick

- Shell untouched in behavior: panel invariants in CLAUDE.md (level `.normal`,
  rounded mask, dynamic height via PanelHeightKey, card style).
- Pure loaders, stores own timers, views own layout.
- Caveat to resolve in the PRD: repo enumeration — settings path list
  (defaulting to a `~/dev` scan) and timezone-normalized streak math.
