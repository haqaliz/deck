# LiveBox GPU usage (PRD)

**Status:** built and probe-verified 2026-11-17; release v1.65 pending.
**Source:** `ROADMAP.md` feature backlog (Apple Silicon GPU/ANE), GitHub issue #81.

## Problem

LiveBox shows CPU, memory and disk, but Apple Silicon users who care about GPU
load have to open a separate monitor. The backlog item was blocked on "no public
API"; that is true for ANE, but not for GPU utilization.

## Feasibility (measured 2026-11-17, M4 Max, macOS 26.5.2)

- `IOServiceMatching("IOAccelerator")` + the registry property
  `PerformanceStatistics` exposes `Device Utilization %` (and renderer/tiler
  variants) without root. Five reads 0.5s apart returned 35, 37, 35, 35, 35 and
  the in-use memory moved too, so it is live, not a boot-time snapshot.
- The same property exists on Intel/AMD accelerators that expose it; when it is
  absent the row hides rather than reporting a fabricated 0%.
- **ANE is not shippable.** `powermetrics --samplers ane_power` answers
  "powermetrics must be invoked as the superuser"; the only other source is the
  private `IOReport` framework. A widget cannot elevate, and a private framework
  is not a dependency Deck should take.

## Scope

- A GPU row in LiveBox: small, medium and large, in the same metric-row language
  as CPU/MEM/DISK.
- Settings: show/hide, color, and a warn/alarm threshold pair (80/90 defaults,
  matching the other metrics).
- The chart stays CPU/MEM/DISK. GPU is a current-value row only; adding it to
  the persisted history would force a schema migration for a metric that may be
  absent on the machine.
- ANE: out of scope, with the blocker recorded in the roadmap.

## Failure and edge cases

- No IOAccelerator service or no `Device Utilization %` key → `gpu` is nil and
  the row is not rendered. No zero, no blank metric.
- The row obeys the global threshold-color toggle and its own warn/alarm pair.
- Values are clamped to 0...100 before display.
- The read runs inside the widget extension every render tick, alongside the
  existing mach/getmntinfo sampling; no agent/snapshot is involved.

## Acceptance

- The GPU row appears on an Apple Silicon Mac with a readable counter, at all
  three sizes, and is absent on a machine without one.
- The settings toggle/color/thresholds take effect on the next render.
- CPU/MEM/DISK and the chart are unchanged.
- Shared tests cover the parser clamping and the GPU threshold pair.
