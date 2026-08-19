# Source brief: livebox-per-metric-thresholds (inline, from deck-next handoff)

Give LiveBox per-metric threshold pairs: split the single shared warn/alarm
settings into per-metric (CPU / MEM / DISK) warn/alarm pairs, reusing the
shipped `ThresholdTier` core in `Shared/LiveBoxCore.swift` and following the
NetBox threshold-coloring precedent (settings tab section + tolerant decode,
tinting on rows/chart, idle values never tinted).

This is the only unblocked follow-on recorded in the planning docs
(`docs/planning/livebox-threshold-coloring/prd.md:67`, "No per-metric threshold
pairs (follow-on if asked)").

Caveats (from deck-next):

- Do NOT pull in GPU/ANE/thermal — it is blocker-deferred with no public Apple
  Silicon API (`docs/planning/livebox-per-core-cpu/prd.md:94`).
- Pure self-sampled data (path 1 in CLAUDE.md) — no agent, no snapshot, no
  timeline changes; keep the ~60s timeline floor and the per-process refresh
  cadence untouched.