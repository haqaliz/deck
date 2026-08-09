---
name: deck-end
description: Use when finishing local work on a Deck widget or feature after the PR is merged and you also need a completion report on Desktop. Triggers on "deck-end", "de", "de feat netbox", "end full".
arguments: "type id"
---

# Deck End (Full Track)

## Overview

Same cleanup as `deck-end-fast`, **plus** a completion report at the end via
`deck-report`.

## Pipeline

1. Phases 0–2 identical to `deck-end-fast` (safety → master pulled → remove worktree/branch).
2. Phase 3 — ROADMAP/README updates (same as fast).
3. Phase 4 — completion report: use `deck-report` to save a short, friendly,
   non-technical note on Desktop (what changed, a screenshot, the PR link).

## When to use full vs fast

- Full (`de`): user-facing features and new widgets — the team wants a note.
- Fast (`def`): small fixes and internal polish.
