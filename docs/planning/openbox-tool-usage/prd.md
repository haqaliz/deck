# OpenBox tool usage — PRD

## Ask

Add a **TOOLS** section to the OpenBox large widget: per-tool call counts
(bash/edit/read/…) from the opencode DB, shown as a top-N list with a settings
toggle and count stepper in the OpenBox tab. Slug: `openbox-tool-usage`.

Source: `deck-next` handoff → `docs/planning/_card/issue.md` (ROADMAP.md:68
backlog item "Tool usage stats (bash/edit/read counts from the DB)").

## User-visible spec

### Front face (widget, snapshot-rendered)

1. **Large only** — a `TOOLS` section below the existing MODELS section
   (divider + section title, same pattern as `modelsList`): rows of
   `tool name` + call count (monospaced, trailing). Top N by count
   (`toolCount` setting, default 5, cap 10). Tool names raw (bash, read,
   edit, grep, write, glob, task, skill…).
2. **Medium/small** — unchanged (IN/OUT/COST rows, chart).
3. **Empty/stale** — no tool rows → section hidden (not a "no data" line;
   today's metrics still render). Remote server mode → tools always empty →
   section hidden.
4. **Unavailable card** — unchanged (OpenBox, "No opencode data").

### Back face (settings — Deck app tab)

- **Tools section**: `Toggle("Show tool usage", isOn: $settings.showTools)`
  default on; `Stepper("Tools: \(settings.toolCount)", in: 1...10)` default 5,
  disabled when toggle off. No new control types; OpenBoxSettings already has
  tolerant decode (PR #8) — zero migration risk.

## Data source

Extends the existing agent-pumped path — no new sampler, no cadence change:

1. **Query** (verified on the real DB, `~/.local/share/opencode/opencode.db`):
   ```
   SELECT json_extract(data,'$.tool') as tool, COUNT(*) as count
   FROM part
   WHERE json_extract(data,'$.type')='tool'
   GROUP BY tool ORDER BY count DESC LIMIT 10
   ```
   Tool calls are JSON in `part.data` (`{type:"tool", tool:"bash", …}` —
   confirmed: 15,900 calls total, 7+ distinct tools, query runs in ms).
   All-time window (interview-resolved), consistent with the all-time MODELS
   section.
2. **Snapshot**: `OpenCodeSnapshot` gains `tools: [ToolCount]` where
   `ToolCount: Codable, Equatable { let tool: String; let count: Int64 }`.
   `OpenCodeReader.load()` fills it from the query via the existing
   `rows(_:sql:)` helper (OpenCodeReader.swift:101).
3. **Old-snapshot decode**: `tools` is a new non-optional key — old
   `opencode.json` would throw with synthesized Codable. Add a tolerant
   `init(from:)` to `OpenCodeSnapshot` (`decodeIfPresent(tools) ?? []`), the
   PR #8 pattern. Self-heals anyway (agent rewrites every 60s), but no
   regression on update.
4. **Remote mode degrade**: `RemoteOpenCodeLoader`'s aggregates (Remote
   OpenCodeLoader.swift:98-151) gain `tools: []` — the HTTP API doesn't
   expose tool events; the widget hides the empty section. Never breaks the
   card.
5. **Agent/app**: `DeckAgent/main.swift` and DeckApp's refresh path are
   unchanged — they call `OpenCodeReader.load()` / save the snapshot, so
   tools flow automatically.

## Shell fit

- Touches: `native/Shared/OpenCodeSnapshot.swift` (ToolCount + tolerant
  init), `native/Shared/OpenCodeReader.swift` (one SELECT), `native/Shared/
  RemoteOpenCodeLoader.swift` (two aggregate call sites get `tools: []`),
  `native/Shared/DeckSettings.swift` (OpenBoxSettings gains two fields —
  covered by PR #8 decode), `native/DeckApp/DeckApp.swift` (toggle + stepper
  in OpenBox tab), `native/DeckWidgets/OpenBoxWidget.swift` (entry + TOOLS
  list view).
- **No shell invariant is touched**: same widget file, same agent snapshot
  path, same 60s cadence, same list-row visual language as MODELS.
- **TDD**: the pure parts are (a) the row → `ToolCount` mapping and
  top-N/formatting and (b) the SQL string shape — developed in a scratch
  SwiftPM package (`Sources/OpenBoxToolsCore` + `Tests/OpenBoxToolsCoreTests`,
  `swift test`), the DevBox/LiveBox precedent, then ported and the scratch
  removed pre-merge. The JSON-query itself is verified against the live DB
  (already done in Phase 2; result counts recorded in this PRD).

## Non-goals

- No tool history/chart, no per-tool token counts, no tool call duration,
  no "today's tools" window (all-time only).
- No changes to remote server API, no fetching tool data over HTTP.
- No changes to medium/small faces, models section, or chart.

## Decisions (resolved in interview)

- All-time window (consistent with MODELS).
- TOOLS section on large only, below MODELS.
- Defaults: showTools on, toolCount 5; names raw, count monospaced trailing.

## Open questions

- None — schema and counts verified against the real DB in Phase 2.
