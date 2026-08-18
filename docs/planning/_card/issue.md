# Deferred parser/formatter test slices (inline brief)

Extend the DeckSharedTests suite to the deferred test slices recorded in
ROADMAP.md under M4 "Deferred from the tests milestone":

1. DevBoxSnapshot lsof/docker parsers
2. RemoteOpenCodeLoader aggregation
3. ProcessSnapshot ps parsing
4. BatteryMetrics formatters

Pure parser/formatter tests — no widget, settings, agent, or shell changes.

Keep the SystemMetrics per-core math out of the first slice (it needs the math
moved to Shared first, touching the LiveBox widget file — that is a follow-on).

Follow the shared-parser-tests precedent:

- `xcodegen generate` + `xcodebuild test -scheme DeckSharedTests` must pass.
- The three app targets still build.
- ROADMAP.md updated to mark the covered items.
