# Understanding: openbox-session-list

## What the work is really asking

OpenBox's large face already shows today's IN/OUT/COST, a 14-day chart
(tokens or cost-per-day), top models and tool usage. The missing metric
story is *per-session*: which opencode sessions burned the most tokens.
This slice adds a top-sessions list to the large face, capped by a settings
count — mirroring the shipped tool-usage slice (`b97ae65`, `1d78a42`).

## Affected files (all in the worktree)

- `native/Shared/OpenCodeReader.swift` — new `sessionsSQL` (session table has
  `title, directory, model, tokens_input, tokens_output, cost, time_created,
  time_updated` — verified against the live DB) + a pure `mapSessionRows`.
- `native/Shared/OpenCodeSnapshot.swift` — new `sessionList` field +
  tolerant decode (`decodeIfPresent ?? []`, PR #8 pattern).
- `native/Shared/OpenBoxCore.swift` — relative-time formatter + row mapping
  (pure, tested).
- `native/DeckWidgets/OpenBoxWidget.swift` — entry field, placeholder rows,
  `sessionsList` section on the large face (copy the `modelsList`/`toolsList`
  pattern: tracked section title, rows with truncation).
- `native/Shared/DeckSettings.swift` + `native/DeckApp/DeckApp.swift` —
  `showSessions` toggle + `sessionCount` stepper (reuse the tool stepper
  pattern, `in: 1...5`).
- `native/SharedTests/` — extend the fixture schema (session table in
  `OpenCodeSQLTests.swift` only has the count columns: needs `title`,
  `directory`, `time_updated` added) + parser/top-N/formatter tests.
- `README.md`, `ROADMAP.md` — register the slice.

## Data source (verified, zero risk)

Local opencode DB, already read by the agent every 60s. The `session` table
has everything needed. The 14-day window pattern already exists
(`dailySQL`/`costDailySQL`).

## Ambiguities / open questions

1. Ordering: "top sessions" by tokens (ROADMAP wording) vs cost (models list
   orders by cost). Propose total tokens (in+out), matching the ROADMAP line.
2. Window: 14 days (matches the chart) vs today only. Propose 14 days.
3. Row content: title + tokens + relative time; directory as secondary line?
   Model badge? Propose title (primary) + tokens right + relative time.
4. Default toggle state and count range (toolCount is 1...3; sessions may
   need 1...5).
5. Remote mode: `RemoteOpenCodeLoader` fetches `/session` but the remote
   `RemoteSession` has no title/directory → `sessionList` degrades to `[]`
   and the section hides. Must be stated in the PRD, not silently empty.

## Shell invariants

No shell change — one optional section on the OpenBox large face, hidden when
empty. Tolerant decode keeps old snapshots valid.
