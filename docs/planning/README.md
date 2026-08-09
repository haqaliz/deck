# Planning artifacts

One folder per unit of work, named by a descriptive kebab-case slug:

```
docs/planning/
├── README.md                 ← this file
├── _card/issue.md            ← source brief / issue dump (worktree-local, id-free)
└── {slug}/
    ├── prd.md                ← deck-prd (interview + critique)
    ├── proposal.md           ← deck-begin only (non-technical + mock)
    ├── spec.md               ← optional aspect specs
    └── plan_YYYYMMDD.md      ← deck-plan (phased, verified)
```

Workflow: `deck-next` (pick) → `deck-begin-fast` / `deck-begin` (plan) →
implement (TDD) → `deck-end-fast` / `deck-end` (cleanup).

**Deferrals must record the blocker** in `{slug}/prd.md` (e.g. "no local data
source", "needs Apple signing") so `deck-next` never re-recommends them blindly.
