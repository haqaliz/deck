---
name: deck-prd
description: Generate, critique, and refine PRDs for Deck widgets and features. Two modes: interview (guided requirements discovery from a brief) and critique (self-critique of an existing PRD, surfacing red/amber gaps). Triggers on "deck-prd", "prd interview", "critique prd".
tags:
  - documentation
  - planning
---

# Deck PRD

## Modes

### Interview mode (from a brief)

Turn a one-paragraph brief (or GitHub issue) into a structured PRD for a widget
or feature:

1. **Restate the ask** in one sentence; confirm the slug.
2. **User-visible spec** — front face: header metrics, chart/list, what the user
   reads at a glance. Back face (settings): each control (toggles pinned right,
   color pickers, steppers) and its default.
3. **Data source**: where the metrics come from (mach APIs, `ps`, sqlite, HTTP),
   refresh cadence, and what happens when the source is unavailable (empty state).
4. **Shell fit**: which shell files it reuses; any deviation from the shell
   invariants in CLAUDE.md (flag them, don't hide them).
5. **Non-goals**: what this widget explicitly does not do.
6. **Open questions**: things the context can't answer — ask the user only these.

Output: `docs/planning/{slug}/prd.md` (+ `spec.md` if the widget has aspects that
should be planned separately).

### Critique mode (existing PRD)

Read the PRD and pressure-test it:

- 🔴 **Red**: would break a shell invariant (material card, dynamic height,
  corner mask, behind-windows level, settings persistence) or has no real data
  source.
- 🟡 **Amber**: ambiguous defaults, missing empty states, refresh-cadence gaps,
  unclear failure behavior.
- For each, state the fix concretely.

## Widget-specific checklist (every PRD must answer)

- What does the front face show at a glance? (3–5 elements max)
- What settings live on the back face? Defaults sane?
- Data source exists and is local-first? Fallback when unavailable?
- Refresh cadence that fits the data (1s for CPU, minutes for weather)?
- Does it reuse the shell without touching the panel invariants?
