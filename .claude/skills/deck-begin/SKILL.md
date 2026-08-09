---
name: deck-begin
description: Use when starting work on a Deck widget or feature and you need stakeholder proposals (technical + non-technical PDFs with diagrams) before planning. Triggers on "deck-begin", "db", "db feat netbox", "begin full".
arguments: "type id"
---

# Deck Begin (Full Track)

## Overview

Same pipeline as `deck-begin-fast`, plus a **proposal phase**: after the PRD is
approved, produce a short diagram (excalidraw/sketch of the widget's front and
back faces) and a one-page proposal note, get approval, then plan.

## Pipeline

Same as `deck-begin-fast` through Phase 4 (isolate → gather → dig → PRD → review gate).

### Phase 4b — Proposal

- Produce `docs/planning/{slug}/proposal.md`: a non-technical one-pager
  (what the user sees, the flip-card settings, why it matters) + a widget mock
  diagram (front face + back face layout) via the `excalidraw` skill.
- **Wait for explicit approval** before Phase 5 (plan).

### Phases 5–6

Identical to `deck-begin-fast` (plan → TDD implementation).

## When to use full vs fast

- Full (`db`): a NEW widget, or a feature that changes the shared shell, or when
  the user wants a visual proposal first.
- Fast (`dbf`): small features, fixes, internal polish.
