# OpenBox cost-per-day chart (stacked by model) — PRD

## Ask

Add a **stacked cost-per-day chart** to OpenBox: bars per day, stacked by
model, showing where the money went. Lives in the existing chart slot behind a
settings toggle, fed by one new SQL grouping in the agent reader plus a
snapshot field. Slug: `openbox-cost-per-day`.

Source: `deck-next` handoff → `docs/planning/_card/issue.md` (ROADMAP.md:66
backlog item "Cost-per-day chart (stacked by model)").

## User-visible spec

### Front face (widget, snapshot-rendered)

1. **Chart slot (medium + large)** — a new setting `showCostChart` (default
   **off**) switches the chart between the existing token lines (IN/OUT) and a
   **stacked cost bar chart**: x = day (same 14-day window as today), y =
   cost, one stacked BarMark per day, segments = model. Same hidden axes, same
   height as the token chart (medium 62pt, large 56pt). Small face unchanged
   (no chart slot).
2. **Series cap** — at most the top 3 models by cost in the window as
   segments; everything else merges into an "other" segment. One paid model
   (the norm here) renders as a single-color bar — still correct.
3. **Legend (large only)** — under the chart, a one-line row of colored dots +
   parsed model id (9pt, `ModelParser.parse(model).id`, lineLimit 1), one dot
   per visible segment including "other". Medium shows no legend.
4. **Colors** — first model = `costColor` (continuity with the COST accent);
   remaining segments from a fixed palette (teal, pink, gray); "other" gray.
   No new settings fields.
5. **Empty/stale** — `costDaily` empty → chart slot hidden (same rule as the
   token chart today); today's IN/OUT/COST rows still render. Unavailable card
   unchanged.

### Back face (settings — Deck app OpenBox tab)

- **Chart section** gains: `Toggle("Cost-per-day chart (stacked by model)",
  isOn: $settings.showCostChart)` default off; disabled when "Show 14-day
  chart" is off. No new control types; `OpenBoxSettings` already has tolerant
  decode (PR #8) — zero migration risk. Toggle default **off** so existing
  widgets don't visually regress on update.

## Data source

Extends the existing agent-pumped path — no new sampler, no cadence change:

1. **Query** (verified on the live DB 2026-08-14,
   `~/.local/share/opencode/opencode.db`):
   ```sql
   SELECT date(time_created/1000,'unixepoch') as day,
          model, ROUND(SUM(cost), 4) as cost
   FROM session
   WHERE time_created > (strftime('%s','now','-13 days')*1000)
     AND model IS NOT NULL AND cost > 0
   GROUP BY day, model ORDER BY day
   ```
   Groups by the raw `model` string — identical to `modelsSQL`
   (OpenCodeReader.swift:95-100) so chart segments never merge distinct
   providers. Window: 3 models with cost > 0 on this machine (deepseek-v4-flash
   dominant, qwen, r1). Runs in ms.
2. **Snapshot**: `OpenCodeSnapshot` gains `costDaily: [CostDay]` where
   `CostDay: Codable, Equatable { let day: String; let model: String; let cost: Double }`.
   `OpenCodeReader.load()` fills it via the existing `rows(_:sql:)` helper.
3. **Old-snapshot decode**: new key must not throw — tolerant
   `decodeIfPresent([CostDay].self, forKey: .costDaily) ?? []` added to the
   existing `init(from:)` (OpenCodeSnapshot.swift:59), PR #8 pattern.
4. **Remote mode parity (no degrade)**: `RemoteOpenCodeLoader` already has
   per-session `cost` + `model` (sessions path) and per-message `cost` +
   `modelID` (messages path). Both `aggregate(...)`s gain the same day × model
   cost accumulation alongside the existing `dayTotals`, filling `costDaily`.
   The HTTP API exposes everything needed — do not ship an empty degrade.
5. **Agent/app**: `DeckAgent/main.swift` and the app refresh path are unchanged
   (they call `OpenCodeReader.load()` / save the snapshot — tools flowed the
   same way).

## Shell fit

- Touches: `native/Shared/OpenCodeSnapshot.swift` (CostDay + tolerant key),
  `native/Shared/OpenCodeReader.swift` (one SELECT + mapping), `native/Shared/
  RemoteOpenCodeLoader.swift` (both aggregates accumulate costDaily),
  `native/Shared/DeckSettings.swift` (one Bool — PR #8-safe), `native/DeckApp/
  DeckApp.swift` (one toggle), `native/DeckWidgets/OpenBoxWidget.swift` (entry
  + stacked chart + legend).
- **No shell invariant is touched**: same widget file, same agent snapshot
  path, same 60s cadence, same chart slot/height, hidden axes, monospaced
  digits, tracked section titles.
- **TDD**: pure parts are (a) the row → `CostDay` mapping, (b) the series
  builder (14-day slot fill + top-3-with-other consolidation + stable model
  ordering) and (c) legend rows. Developed in a scratch SwiftPM package at the
  worktree root (`swift test`), ported into `native/`, removed pre-merge — the
  openbox-tool-usage precedent (Package.swift + Sources/OpenBoxToolsCore +
  Tests, git log 2c899e7 → 945a8ad).

## Non-goals

- No per-message/session cost drill-down, no cumulative cost line, no
  cost-per-token, no cost on the small face, no per-model colors in settings.
- No changes to the token chart, models list, tools list, or remote API.
- No new settings control types (toggle only).

## Decisions (resolved in interview)

- `showCostChart` toggle (default off) rather than replacing the token chart —
  opt-in, no visual regression on update (CLAUDE.md "widgets must not regress").
- Group by raw `model` string (consistency with modelsSQL; parsed id only at
  render).
- Series cap: top 3 + "other" (matches the models list ceiling of 3).
- Zero-cost days render as empty bars; `costDaily` empty → slot hidden.

## Open questions

- None — schema, query and model cardinality verified against the live DB in
  Phase 2; remote-mode cost+model fields confirmed present in
  RemoteOpenCodeLoader.swift:53-59, 76-85.
