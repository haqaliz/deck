---
name: deck-end-fast
description: Use when finishing local work on a Deck widget or feature after the PR is merged and you want to clean up without generating a completion report. Triggers on "deck-end-fast", "def", "def feat netbox", "end fast".
arguments: "type id"
---

# Deck End (Fast Track)

## Overview

Closes out a unit of work's local state after the PR has merged:
**master → pull → remove worktree → delete branch**. No report (use `deck-end`
for that).

**Invocation:** `def <type> <id>` — e.g. `def feat netbox`.

- Branch: `<type>/<id>/aliz`; worktree dir: `.claude/worktrees/<type>-<id>`.

## Pipeline

### Phase 0 — Safety check

- **Worktree clean?** `git -C <worktree> status --porcelain` must be empty. If
  not, stop — commit or stash first.
- **Branch merged?** Confirm the PR is merged (`gh pr view <PR> --json state,mergedAt`
  if reachable). `git branch -d` refuses unmerged branches on purpose; do not use
  `-D` without explicit user OK.
- **You may be inside the worktree being removed.** Resolve the primary checkout
  first and run all commands from there.

### Phase 1 — Master, pulled

```bash
PRIMARY=$(git worktree list | head -1 | awk '{print $1}')
git -C "$PRIMARY" checkout master
git -C "$PRIMARY" pull --ff-only origin master
```

### Phase 2 — Remove worktree, delete branch

```bash
WORKTREE_NAME="<type>-<id>"     # e.g. feat-netbox
BRANCH="<type>/<id>/aliz"       # e.g. feat/netbox/aliz

git -C "$PRIMARY" worktree remove ".claude/worktrees/$WORKTREE_NAME"
git -C "$PRIMARY" branch -d "$BRANCH"
```

If `worktree remove` refuses (uncommitted/untracked files) or `branch -d` refuses
(not merged), stop and surface the message — do not force silently.

### Phase 3 — Release note

- Update `README.md` widget list if the work added/changed a widget.
- Mark the milestone checkbox in `ROADMAP.md` if applicable.
- Commit + push these doc updates.

## Common mistakes

| Mistake | Fix |
|---|---|
| `-D` on an unmerged branch | Stop; surface the PR state first |
| `--force` on worktree remove | Go back to Phase 0 — clean up first |
| Forgetting ROADMAP/README updates | Phase 3 exists for a reason |
