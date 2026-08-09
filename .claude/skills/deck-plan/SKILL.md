---
name: deck-plan
description: Create a phased technical implementation plan from planning artifacts in docs/planning (PRD). Use after deck-prd when ready to execute. Triggers on "deck plan", "implementation plan", "plan from PRD".
tags:
  - planning
  - documentation
---

# Deck Tech Plan

Create a phased technical implementation plan from `docs/planning/{slug}/prd.md`
(+ `spec.md`). Inputs come from `deck-prd`; do not require the full begin flow.

## Structure

Output: `docs/planning/{slug}/plan_YYYYMMDD.md`

For each phase:

1. **Goal** — one sentence.
2. **Files touched** — explicit paths (e.g. `Sources/NetBox/Metrics.swift`).
3. **Steps** — numbered, each independently verifiable.
4. **Verification** — how to prove the step works:
   - Pure logic → XCTest (`swift test`) or a one-off `swift` script check.
   - UI/shell → `swift build -c release` + `swift run <Widget> --debug-flip` +
     `CGWindowList` bounds check (height = content, corners rounded).
5. **Dependencies** — which steps must wait on which.

## Phase ordering rules

- **Shell/data first**: settings struct + loader + store before any UI.
- **Front face before back face**: the card shows data first, settings second.
- **Verification per phase, not at the end**: every phase ends green
  (`swift build` passes, the widget runs).
- Tests for parsers/formatters come WITH the code (TDD), not after.

## Widget blueprint template

For a new widget (from ROADMAP.md):

1. Scaffold `Sources/<Widget>/` from the LiveBox shell (AppMain, Settings,
   SettingsStore, MetricsStore, ContentView, SettingsView).
2. `Package.swift`: add the executableTarget.
3. Loader: pure structs + functions; no timers.
4. Settings: defaults + persistence path (`~/Library/Application Support/<Widget>/settings.json`).
5. Front face: header + chart/list; back face: settings (toggles right, colors).
6. Flip + dynamic height wiring (reportHeight / panelHeight).
7. Register in README.md + ROADMAP.md.
