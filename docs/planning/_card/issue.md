# Brief — taskbox-custom-wiql

Let TaskBox run a user-supplied WIQL filter instead of the fixed
`[System.AssignedTo] = @Me` query. This is the open follow-up from the TaskBox and
azure-multi-project entries (ROADMAP M8). Only the query builder, the settings
tab and the parser should change. Board lanes, the widget face and the
multi-project fan-out stay as they are.

Caveats to design around:
- A project-scoped WIQL URL does not filter by project. `[System.TeamProject] =
  @project` must always be enforced regardless of what the user types, or rows
  leak across projects.
- Tree/one-hop queries answer `workItemRelations`, not `workItems`. Reject them
  clearly or parse them.
- Cap the returned ids before `workitemsbatch`.
- A malformed query gets its own fetch outcome, not "auth or target".

Probe a few real queries against the live org before writing the PRD.

Source: deck-next pick (2026-09-25), from ROADMAP.md M8.
