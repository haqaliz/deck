# DevBox — inline brief

Source: `deck-next` handoff (2026-08-12), pick: `devbox`.

Build DevBox, the last unblocked pending M3 widget (ROADMAP.md:45): a system
dev-ops card showing **open TCP listening ports** (process + port) and
**Docker containers** (name, image, status, CPU/mem from `docker stats`) —
both sandbox-blocked, so they pump through `DeckAgent` exactly like the
existing `ProcessSnapshot` path (`DeckAgent/main.swift:24` shows the pattern).

Copy the GitBox widget shell wholesale (`GitBoxWidget.swift`,
`GitBoxSnapshot.swift`, `GitBoxSettings`, `GitBoxSettingsView` tab) and add a
pure `DevBoxCore`-style logic layer (lsof output parser, docker stats parser,
formatters) following the GitLogParser/ProcessSnapshot split, with the pure
parsers unit-tested.

## Caveats to resolve in the PRD

- **Docker is conditional**: the daemon may be absent, stopped, or have zero
  containers. Define the degrade states — "Docker: unavailable" (daemon
  unreachable), "no containers" (daemon up, empty), and the normal list — so
  the card still renders ports/processes when Docker is missing.
- `lsof` and `docker` are subprocesses — sandbox-blocked in the widget, so the
  agent/host sampler only (never in the widget target).
- `docker stats --no-stream --format` parsing must survive localized/missing
  values; keep the format flag list explicit.

## Constraints from the pick

- Shell untouched in behavior: widget sandbox data paths, 60s agent cadence,
  snapshot Codable/Equatable + store pattern, `DeckSettings.containerDirectory`.
- Widgets render snapshots only; pure loaders, stores own timers, views own
  layout (CLAUDE.md conventions).
- Register in `DeckWidgets.swift`, `DeckSettings.swift`, `DeckApp.swift` tabs,
  README and ROADMAP (mark M3 DevBox shipped).
