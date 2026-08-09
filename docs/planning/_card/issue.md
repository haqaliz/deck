# OpenBox remote server mode — inline brief

Source: `deck-next` handoff (2026-08-09), pick: `openbox-remote`.

OpenBox currently reads usage from the local opencode DB via `opencode db`
(`OpenCodeMetrics.swift`). Add remote server mode: when a token + URL are
configured, fetch today's in/out tokens, cost, 14-day history, and top models
over HTTP instead. The settings token field already exists (README.md) —
verify first that opencode's server exposes usage metrics with that token; if
no HTTP endpoint exists, stop and report back (NetBox becomes the pick). Then
add a pure HTTP loader beside the local one, a mode toggle in Settings, and
keep the shell untouched — no changes to AppMain panel invariants, dynamic
height, or card style.

## Constraints from the pick

- Shell untouched: panel invariants in CLAUDE.md (level `.normal`, rounded
  mask, dynamic height via PanelHeightKey, card style).
- Pure loaders, stores own timers, views own layout.
- Phase 0 feasibility check first: does opencode's server expose a usage
  metrics HTTP endpoint authenticated by the token?
