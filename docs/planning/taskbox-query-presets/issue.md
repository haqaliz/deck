# Card: taskbox-query-presets (feat)

Inline brief (from `deck-next`, 2026-10-07; no GitHub issue).

Add a presets menu to TaskBox's Query settings section
(`native/DeckApp/DeckApp.swift:2343`) — assigned to me, created by me, current
sprint — that inserts the condition into the existing draft and never applies
it (Apply stays the only writer, `docs/planning/taskbox-custom-wiql/prd.md` A1).
Then close the recorded team-context follow-up: `@CurrentIteration` resolves
against each project's default team today (probe P7), so add a team segment for
non-default teams. Probe Azure's team-macro syntax and project teams endpoint
live first — that is the one unproven part. Every preset must go through
`WiqlClause.validate` and compose via `WiqlClause.query(for:)`, with unit tests
in DeckSharedTests; no new fetch, no snapshot fields, and the widget extension
must read nothing new.

Sources:

- ROADMAP.md M8 "TaskBox: custom WIQL" open follow-ups (ROADMAP.md:939-941):
  presets (assigned / created / current sprint), a team segment for
  `@CurrentIteration`.
- `docs/planning/taskbox-custom-wiql/prd.md` Q4 (line 28, presets declined in
  v1), §7 non-goals (lines 169-173), §9 open questions (line 196).
- `docs/planning/taskbox-custom-wiql/probe.md` P7 (line 15): no-team
  `@CurrentIteration` resolves against each project's default team.
- deck-next handoff, 2026-10-07.

Caveat: `@CurrentIteration('[Project]\Team')` and the teams-list endpoint need
a live probe before shipping; presets must insert into the draft only.
