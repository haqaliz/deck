---
name: deck-end-fast
description: Use when finishing local work on a Deck widget or feature after the PR is merged and you want to clean up without generating a completion report. Triggers on "deck-end-fast", "def", "def feat netbox", "end fast".
arguments: "type id"
---

# Deck End (Fast Track)

## Overview

Closes out a unit of work's local state after the PR has merged:
**master → pull → remove worktree → delete branch → release**. No report (use
`deck-end` for that).

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

### Phase 4 — Release

Ship the merged work as a GitHub Release. The CI workflow (`deck.yml`) builds,
signs, and uploads `Deck-macos.zip` + SHA256 to a GitHub Release when a `v*`
tag is pushed (README.md → "Releases"). One release per feature cluster — not
per commit. Skip only for pure-internal work with no user-facing change (e.g.
tests-only milestones still deserve one when a release is overdue).

```bash
# 1. Decide the version: patch bump from the latest tag (small fixes) or a
#    minor bump (new widgets/features):  git tag --sort=-v:refname | head -1

# 2. Bump the bundle versions in native/project.yml — it is the single source
#    of truth: xcodegen regenerates BOTH native/DeckApp/Info.plist and
#    native/DeckWidgets/Info.plist from its info.properties. Version = tag
#    without the "v" (v1.4 → "1.4"), CFBundleVersion = the same integer.
xcodegen generate --spec native/project.yml
git add native/project.yml native/DeckApp/Info.plist native/DeckWidgets/Info.plist
git commit -m "release: bump to v1.4"
git push

# 3. Tag + ship (v* tags trigger the signed Release build)
git tag v1.4 && git push origin v1.4

# 4. Verify the release landed
gh run list --workflow deck.yml --limit 1    # wait for green
gh release view v1.4                         # Deck-macos.zip + .sha256 present

# 5. Install the signed build locally
cp -R native/build.noindex/Build/Products/Release/Deck.app /Applications/
open /Applications/Deck.app                  # re-registers widgets via pluginkit
```

**Version numbering rule**: `CFBundleShortVersionString` = tag without the `v`
(v1.4 → "1.4"); `CFBundleVersion` = the same integer. Never tag without
bumping first — the installed app must report the released version.

If the release run fails, check `gh run view <id> --log`: the workflow needs
the signing secrets (`APPLE_CERT_P12_BASE64`, `APPLE_APP_SPECIFIC_PASSWORD`,
…) and only tag pushes sign — PR builds are unsigned compile checks.

## Common mistakes

| Mistake | Fix |
|---|---|
| `-D` on an unmerged branch | Stop; surface the PR state first |
| `--force` on worktree remove | Go back to Phase 0 — clean up first |
| Forgetting ROADMAP/README updates | Phase 3 exists for a reason |
| Tagging without bumping project.yml | The installed app would report the old version — bump first |
| Tagging a version with no signing secrets | The workflow fails; only the cert-secreted runner signs |
