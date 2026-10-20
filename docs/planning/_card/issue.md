# devbox-process-hide-toggle (inline brief)

Source: `dbf task 72`, from the ROADMAP M6 open item (2026-10-21).

## Brief

DevBox's open-ports card shows system processes (`rapportd`, `ControlCenter`…)
unfiltered; the top-N cap limits the count but not the noise. Add a user-editable
hide list so those rows can be removed.

Deferred in `docs/planning/devbox/prd.md:106` as "a fuzzy heuristic" — the design
problem is the matching rule, not the feature.

## Scope shape (from the issue)

- DevBox settings: a hide list, default empty (no change for existing users).
- Filter at render time, not in the agent snapshot — the snapshot stays complete.
- Exact `command` match, case-insensitive; no fuzzy substring.

## Done when

Editable in DevBox settings, hidden rows disappear at every size, tests cover the
matcher, ROADMAP item checked.

Issue: https://github.com/haqaliz/deck/issues/72
