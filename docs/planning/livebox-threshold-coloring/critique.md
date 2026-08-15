# Self-critique: livebox-threshold-coloring

Critique pass (deck-prd critique mode) of `docs/planning/livebox-threshold-coloring/prd.md`.

## 🔴 Red (blocking)

None.

- No shell invariant is touched: settings persist via the tolerant-decode
  pattern, no agent/loader/snapshot changes, the material card and 3-size
  layouts are untouched (prd.md §4).

## 🟡 Amber (fixes below)

1. **Warn > alarm in the UI.** Steppers are independent 0...100; a user can set
   Warn 90 / Alarm 80 and the row will simply alarm at 80 — correct but
   confusing. Fix: add a caption under the steppers ("Alarm takes precedence
   when it is lower than Warn") and a unit test pinning the precedence. Not
   clamping ranges — it keeps the all-alarm configuration (warn=alarm=90)
   reachable.
2. **Default 80/90 tuning.** macOS MEM% can sit high under normal use, so MEM
   may warn often; DISK at 80% is a reasonable fullness warning. Fix: defaults
   stay 80/90, but this is the first thing to sanity-check on a live install
   during Phase 6 verification. Users can disable via the toggle.
3. **Process-list percents use the metric colors too.** Alarm red on a row and
   the CPU% column's `cpuColor` both read "colored percent" in the large face.
   Fix: leave process rows untouched (per PRD non-goals) — accepted visual
   trade-off, noted here so it isn't mistaken for a regression.
4. **Color-only signal.** No icon/text change accompanies the recolor. For a
   glanceable widget this is the point of the feature; note it as an accepted
   limitation, not silently.

## Verdict

Approve the PRD as written with the §Amber-1 caption added; all fixes are
non-structural (a caption + a test).
