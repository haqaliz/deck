# Inline brief: livebox-threshold-coloring

Source: deck-next handoff (2026-08-15).

Build LiveBox threshold coloring: CPU/MEM/DISK metric rows and the per-core CPU
lines turn amber/red when a value crosses thresholds (defaults ~80%/90%,
editable in the LiveBox settings tab, persisted with tolerant decode like every
other settings struct). Pure layout work — the widget already samples mach
in-process, so no agent, no new loader, no snapshot changes; keep the color
rules in one small shared helper (formatter-style, testable in DeckSharedTests)
so NetBox threshold coloring (ROADMAP.md:81) can reuse them. Caveat: verify the
colors read well on both light and dark widget materials, and don't let this
slice absorb the GPU/ANE feasibility work (ROADMAP.md:67).
