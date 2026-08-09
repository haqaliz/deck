---
name: deck-worktrees
description: Isolate parallel work in the Deck repo using the Claude Code worktree layout. Use when starting a new widget/feature that should not collide with another running session, or when running two widgets from different branches at once. Covers branch naming, worktree placement under .claude/worktrees, and cleanup.
allowed-tools: Bash, Read, Write, Edit, Glob
---

# Deck Worktree Workflow

## When to Use

- Another session is running on a different branch in deck and you want to start
  a new widget/feature without colliding.
- You want to run two widgets from different branches side by side
  (`.build` lives per-checkout, so `swift build` in each worktree is independent).

## Layout

```
.claude/worktrees/
├── feat-netbox/        ← branch feat/netbox/aliz
└── fix-openbox-remote/ ← branch fix/openbox-remote/aliz
```

Branch naming: `<type>/<id>/aliz` (e.g. `feat/netbox/aliz`).
Worktree dir: `.claude/worktrees/<type>-<id>` (slashes → dashes).

## Creating

From the primary checkout, based on `origin/master`:

```bash
git fetch origin
git worktree add .claude/worktrees/feat-netbox -b feat/netbox/aliz origin/master
```

Then build to verify the toolchain in the new worktree:

```bash
cd .claude/worktrees/feat-netbox
swift build
```

Note: `.build/` is gitignored, so each worktree builds independently — no shared
artifacts to clash over.

## Inside a worktree

- All planning artifacts (`docs/planning/...`) and code changes happen inside the
  worktree — never in the primary checkout.
- Commit per task on the worktree's branch; push when ready
  (`git push -u origin <branch>`), then open a PR with `gh`.

## Cleanup

See `deck-end-fast`: remove the worktree, delete the branch (never `-D` silently),
pull master in the primary checkout. The branch's PR must be merged first.

## Common mistakes

| Mistake | Fix |
|---|---|
| Branching from `master` instead of `origin/master` | `git worktree add ... origin/master` |
| Building in the primary checkout while a worktree is active | Work in the worktree |
| Removing a worktree with uncommitted changes | Phase 0 safety check in deck-end-fast |
