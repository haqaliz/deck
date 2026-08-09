---
name: deck-next
description: Use when deciding what to build next in Deck and you want the single highest-leverage widget or feature picked from the repo's own roadmap and planning files (not invented), grounded in the shell value and in what has already shipped or been deferred, ending with a ready-to-run handoff. Triggers on "deck-next", "dn", "what's next", "next widget", "pick next".
arguments: ""
---

# Deck Next (pick the most important widget/feature)

## Overview

Read the repo's own roadmap and planning files, rank the real candidate widgets
and features against the shell value and against what has shipped or been
deferred, and recommend the single highest-leverage one to build next. End with a
ready-to-paste `deck-begin-fast` invocation so the next session can start.

This skill RECOMMENDS and hands off. It does NOT create a worktree or start
`deck-begin-fast` itself.

## When to use

- "what should I build next", "pick the next widget", at the start of a session.
- After a merged feature, when choosing the next unit of work.
- Not for: executing a chosen feature (use `deck-begin-fast`).

## The candidate set is the FILES, never invented

Read in this order:

- `ROADMAP.md`: milestones, the M3 widget candidates, and the feature backlog.
  Markers: [x] shipped / [ ] pending.
- `docs/planning/*/`: in-flight, completed, and DEFERRED work. A feature deferred
  for a real blocker must not be re-recommended as a quick win.
- `CLAUDE.md`: the shell invariants and conventions the pick must obey.
- `README.md` + `git log`: what actually shipped. Trust this over prose.

## How to rank

1. **Reuse the shell.** Widgets that copy the proven shell and only add a data
   source are cheap; work that touches the shell is expensive — prefer shell
   reuse unless the shell itself is the gap.
2. **Fits the deck identity.** Small, glanceable, native-looking cards with a
   flip settings face. A candidate that can't fit that shape is a bad widget.
3. **Data source exists and is local-first.** mach APIs, ps, sqlite, system
   frameworks. A widget with no reliable local data source is a blocker — name it.
4. **Respect shipped and deferred state.** Don't re-recommend shipped work or
   blocker-deferred work (name the blocker).
5. **Follow-on slices count.** A shipped widget's next slice (e.g. OpenBox
   remote mode) is a valid, often high-leverage candidate.
6. **Unblocked and testable beats broad.** Prefer a candidate with a clear first
   slice over one with an unresolved feasibility question.

## Process

1. Read the files above; build the candidate list (pending widgets, backlog
   features, follow-on slices, demand-pulled ideas).
2. For each: shipped-state (cite the file), shell-reuse cost, data-source risk,
   any known blocker from the docs.
3. Rank by the rules; pick ONE plus one or two alternates.
4. Sanity-check against the shell invariants in CLAUDE.md.
5. Produce the handoff.

## Output format

- **The pick**: one line naming the widget/feature and a kebab-case slug.
- **Why**: 2–3 bullets tying it to the shell value and to what shipped, each citing a file.
- **Alternates**: one or two lines.
- **Known caveat**: the nearest data-source or shell risk, stated honestly.
- **Handoff prompt** (ready to paste): a `dbf <type> <slug>` line plus a 3–5
  sentence inline brief including the caveat. The user runs it to start the
  worktree; this skill does not.

## Honesty rules

- Ground every shipped/pending/deferred claim in a named file.
- If the strongest-looking candidate has a real blocker, say so and rank it
  accordingly.
- Recommend only what the files support; if the files are thin, say the pick is
  based on discussion.

## Common mistakes

| Mistake | Fix |
|---|---|
| Inventing a widget not in the docs | The candidate set is the files; cite each |
| Re-recommending shipped work | Check ROADMAP markers + git log first |
| Recommending a widget with no local data source | Name the blocker; rank it down |
| Starting the worktree from this skill | Only recommend; the user runs `dbf` |
