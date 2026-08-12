# LiveBox per-core CPU lines — inline brief

Source: `deck-next` handoff (2026-08-12), pick: `livebox-per-core-cpu`.

Build per-core CPU lines for LiveBox: expose per-processor ticks from the
existing `host_processor_info` sample in `SystemMetrics.swift` (currently summed
in the loop at lines 33-39), compute per-core usage deltas as a pure,
unit-tested function, and render thin per-core lines in the existing LiveBox
chart with a small/medium cap (e.g. top 8) to avoid noise on 10-12 core
machines.

No agent or snapshot changes — the loader already runs sandbox-safe in-widget.
Keep the total CPU line as the prominent one; per-core lines are secondary
stroke.

## Caveats to resolve in the PRD

- **Cap/grouping**: multi-core machines (up to 12 lines on Apple Silicon) get
  visually noisy — cap to N cores (e.g. 8) or group E/P-cores.
- **Chart shape**: the shared chart view is currently single-line — it needs
  thin multi-line strokes.
- **Settings toggle**: decide whether a "per-core lines" toggle belongs in the
  LiveBox settings tab (default on/off).

## Constraints from the pick

- Shell untouched in behavior: sandbox-safe self-sampled loader path, 60s
  cadence, no agent/snapshot/container changes.
- Pure logic (per-core delta percent computation) unit-tested via the scratch
  SwiftPM package precedent (DevBoxCore), ported into the widget target.
- Register in README and ROADMAP (mark backlog item shipped).
