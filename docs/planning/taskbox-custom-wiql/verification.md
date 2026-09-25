# Verification — TaskBox custom WIQL (2026-09-25)

Installed build of `feat/taskbox-custom-wiql/aliz` (`06e1de1`) at
`/Applications/Deck.app`, `scripts/lsclean.sh` run. Deck quit and the launchd
jobs down after the bundle swap, so every snapshot write below is one direct run
of `/Applications/Deck.app/Contents/MacOS/DeckAgent`. `settings.json` was backed
up first and restored afterwards.

| Case | `taskbox.query` | Status | Snapshot |
|---|---|---|---|
| C1 | empty | ok | 12 rows, `isCustomQuery: false`. The old fixed query sent directly also returns 12 |
| C2 | `[System.State] = 'Active'` | ok | 0 rows, custom. This project has no `Active` state (the P4 shape) |
| C2b | `[System.CreatedBy] = @Me AND [System.ChangedDate] >= @Today - 30` | ok | 82 rows, **all** `ForesightManifold`. The same condition probed directly: 82 |
| C3 | `[Custom.Nope] = 'x'` | `queryRejected` | **mtime unchanged** |
| C4 | `[System.State] = 'Active') OR ([System.Id] > 0` | `queryRejected` | **mtime unchanged**. Rejected locally, before any request, by code path (`fetch` validates before the fan-out; pinned by `WiqlClauseValidationTests`) |
| C5 | `[System.Id] > 0` | ok | 200 rows, `totalIsLowerBound: true`. Full agent tick 7.9s |
| C6 | `[System.State] = 'Doen'` | ok | 0 rows, custom |

Restored: original `settings.json`, one agent run (`ok`, 12, default), Deck
reopened. The heartbeat was 22s old and `processes.json` 4s old 75s later, so
both agents are running again.

Probe P15 returned 91 for the C2b condition earlier the same day, and 82 when
re-probed alongside C2b. That's data drift, not a code difference.

## Not verified here

- **The widget face** (re-add from the gallery, all three sizes; "N items" /
  "200+ items" / "No matches" / the "Check the query" chip). The wording is
  unit-pinned (`TaskHeaderTests`), but nobody has looked at the rendered face.
- **The settings Query section by hand** (typing doesn't change the widget,
  Apply does, and Test shows a count, Azure's message, or the local caption).
  The summary line is unit-pinned (`WiqlTestSummaryTests`). The view compiles
  but hasn't been clicked through.
