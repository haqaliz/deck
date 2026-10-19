# azure-multi-org (inline brief)

Source: `dbf feat azure-multi-org`, handed off by `deck-next` (2026-10-18).

## Brief

One Azure DevOps account should span **more than one organization**, so TaskBox
and PRBox can pull from two orgs in one list. This is the recorded "natural next
slice" from `docs/planning/azure-multi-project/prd.md:185-187` (where multi-org
was a deliberate non-goal) and the last surviving follow-up in that family —
still open in `ROADMAP.md:165` (TaskBox), `:212` (PRBox) and `:433`
(azure-multi-project). Every sibling has shipped: multi-project (`:401`), the
five→eight cap (`:907`), review state (`:194`), custom WIQL (`:926`) and presets
(`:957`).

## Scope to settle in the PRD

The obvious design was **declined**, so the PRD must choose a mechanism:

- `azure-multi-project/prd.md:186` — *"a slot that binds several accounts … was
  interviewed and deliberately not chosen."*
- Candidate designs to weigh: (A) an organization list on the account,
  symmetric to the project list that shipped; (B) org→projects groups (each org
  carries its own project list); (C) the declined multi-account slot.

## Caveat from the recommender

This org has **one** Azure organization, so the work is unit-testable only —
the live two-org run is a recorded follow-up, exactly as the team picker's was
(`ROADMAP.md:975-977`). Reuse the accounts shell and both widgets; do not invent
a new data path.
