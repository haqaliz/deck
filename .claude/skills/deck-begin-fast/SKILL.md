---
name: deck-begin-fast
description: Use when starting work on a Deck widget or feature (an inline brief or a GitHub issue id) and you want the fast path straight to an implementation plan. Triggers on "deck-begin-fast", "dbf", "dbf feat netbox", "begin fast".
arguments: "type id"
---

# Deck Begin (Fast Track)

## Overview

Turn a single unit of work (new widget, new feature, fix) into shipped code. The
fast track is: **isolate → gather → dig → PRD → plan → implement (TDD)**. No
proposal/diagram deliverables (use the full `deck-begin` when you need those).

**Invocation:** `dbf <type> <id>` — e.g. `dbf feat netbox`, `dbf fix openbox-remote`.

- `type` ∈ `feat | widget | fix | task | chore`
- `id` = a short descriptive **slug** (e.g. `netbox`, `openbox-remote`) or a
  GitHub issue number if one exists.

## Task source

Deck's tracker is GitHub Issues on `haqaliz/deck`, but work is often an inline
brief. Degrade gracefully:

- If `id` is numeric and `gh issue view <id>` succeeds → use it (Phase 1).
- Otherwise → ask the user for a one-paragraph inline brief; skip the `gh` fetch.

## Pipeline

### Phase 0 — Isolate in a worktree

**REQUIRED SUB-SKILL:** Use `deck-worktrees`.

- Branch: `<type>/<id>/aliz` (e.g. `feat/netbox/aliz`).
- Worktree dir: `.claude/worktrees/<type>-<id>`.
- Create from `origin/master`; run `swift build` in the worktree to verify the toolchain.

### Phase 1 — Gather context

Save the issue body or inline brief to `docs/planning/_card/issue.md` in the
worktree (id-free name on purpose — the id lives in the branch/PR).

### Phase 2 — Deep dig

- Read the dump and CLAUDE.md (the shell invariants).
- Map the code: `Sources/<Widget>/` for existing widgets; if this is a new
  widget, study LiveBox's shell files as the template.
- Produce a short "understanding" note: what the work is really asking, affected
  files, ambiguities, open questions.
- If the work would break a panel invariant in CLAUDE.md, flag it before planning.

### Phase 3 — Requirements interview

**REQUIRED SUB-SKILL:** Use `deck-prd` (interview mode).

- Feed it the Phase 1 dump + Phase 2 understanding.
- Confirm a descriptive kebab-case slug (e.g. `netbox`) — never `<type>-<id>`.
- Output: `docs/planning/{slug}/prd.md` (+ `spec.md` if decomposed).

### Phase 4 — Self-critique the PRD

**REQUIRED SUB-SKILL:** Use `deck-prd` (critique mode). Surface the 🔴/🟡 gaps.

### ⛔ Review gate — STOP

Present the PRD and flagged gaps. **Wait for explicit approval** before planning.

### Phase 5 — Implementation plan

**REQUIRED SUB-SKILL:** Use `deck-plan`.

- Output: `docs/planning/{slug}/plan_YYYYMMDD.md` (phases + verification steps).

### Phase 6 — Implement (TDD)

Start only after the plan is approved.

- **REQUIRED SUB-SKILL:** Use `superpowers:test-driven-development` — RED → GREEN → REFACTOR.
  Add/use an XCTest target (`swift test`) for pure logic (parsers, formatters,
  loaders with injected data). UI/shell code is verified by `swift build -c release`
  + `swift run <Widget> --debug-flip` + window-bounds checks.
- Commit per task on the branch. Keep it green: `swift build` after each task.

## Artifact layout (inside the worktree)

```
docs/planning/
├── _card/issue.md              ← gh dump or inline brief (Phase 1)
├── {slug}/prd.md               ← deck-prd
└── {slug}/plan_*.md            ← deck-plan
```

Phase 6 produces code commits — not documents.

## Common mistakes

| Mistake | Fix |
|---|---|
| Working in the primary checkout | Always create the worktree first |
| Slug = `feat-12` | Use a descriptive slug; id lives in the branch/PR |
| Breaking a panel invariant (material card, dynamic height, corner mask) | Re-read CLAUDE.md before touching the shell |
| Skipping the review gate | PRD must be approved before planning |
| No tests for parsers/formatters | TDD the pure logic with XCTest |
