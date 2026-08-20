# Source brief: livebox-thermal-state (inline, from deck-next handoff)

Add a thermal-state row to LiveBox, sampled inside the widget via
`ProcessInfo.processInfo.thermalState` (nominal/fair/serious/critical) — pure
path-1 self-sampled data: no agent, no snapshot, no timeline or cadence
changes. Map the four levels onto the shipped tint language by extending the
`ThresholdTier` core in `Shared/LiveBoxCore.swift` (serious → warn, critical →
alarm; nominal/fair never tinted, matching the "idle values are never tinted"
rule from netbox-threshold-coloring). Add a `showThermal` toggle to
`LiveBoxSettings` (`Shared/DeckSettings.swift:75`) with tolerant decode + a
CodingKeys entry, and a LiveBox settings-tab section in `DeckApp.swift`. TDD
the pure level→tier mapping in `DeckSharedTests` first.

Caveats (from deck-next):

- `thermalState` is a coarse enum, not degrees — no temperature or fan data
  (private SMC only).
- GPU/ANE stays out of scope: blocker-deferred for lack of a public Apple
  Silicon API (`docs/planning/livebox-per-core-cpu/prd.md:94`), so
  `ROADMAP.md:79` gets split rather than fully closed.
- Verify tinting under real thermal pressure (sustained load or
  `sudo pmset -a thermalstate`), then build, install, and re-add LiveBox from
  the gallery at all three sizes.
