# Source brief: livebox-process-cadence (inline, from deck-next handoff)

LiveBox's CPU chart re-samples live on a TimelineView tick, but the top-process
rows render from the agent's `processes.json` snapshot which refreshes only
every 60s — a visible staleness gap on the deck's liveliest widget.

Plan (draft): sample the process snapshot at a tighter interval (agent change,
keep CPU cost negligible) and have LiveBox re-read it on its existing live
tick; wire an optional interval setting with tolerant decode, test the Shared
changes in DeckSharedTests.

Caveats (from deck-next):

- Do NOT fight the ~60s WidgetKit timeline floor (CLAUDE.md) — the gain is
  fresher snapshot data per render, not more renders.
- Also pick up the deferred SystemMetrics per-core math tests (ROADMAP.md:58)
  since both touch the same files.
- GPU/ANE/thermal is out (documented blocker: no public Apple Silicon API —
  docs/planning/livebox-per-core-cpu/prd.md:94).
