# OpenBox tool usage — inline brief

Source: `deck-next` handoff (2026-08-12), pick: `openbox-tool-usage`.

Add a tool usage section to OpenBox: bash/edit/read counts per tool from the
opencode DB, shown as a top-N list with a settings toggle (default on) and
count stepper in the OpenBox tab. Follow the OpenCodeReader pattern exactly —
one new prepared SELECT with the existing `rows()`/`int64()`/`string()`
helpers (OpenCodeReader.swift:72-101), aggregation + top-N + formatting as
pure functions TDD'd in a scratch SwiftPM package (DevBox precedent, removed
pre-merge).

## Caveats to resolve in the PRD

- **Schema verification**: confirm the real opencode DB has a queryable tool
  column before planning — Phase 2 must run the SELECT against the actual DB.
- **Remote mode degrade**: in remote server mode (OpenBox auto-switch, M2) tool
  stats degrade to an empty section, never a broken widget.
- Register in README/ROADMAP, OpenBox backlog item line 68.

## Constraints from the pick

- Shell untouched in behavior: agent-pumped snapshot path (OpenBox snapshot
  via DeckAgent), 60s cadence, settings via the tolerant-decode structs (PR #8).
- Pure aggregation logic unit-tested in a scratch package, ported into
  `native/Shared/`, removed pre-merge.
