---
name: deck-report
description: Use when a Deck unit of work (widget, feature, fix) is done and you want a brief, friendly, non-technical completion note saved on Desktop to share. Triggers on "deck-report", "dr".
allowed-tools: Read, Grep, Glob, Bash, Write
arguments: "type id"
---

# Deck Completion Note

A short, friendly, non-technical heads-up that a unit of work is done. Written
like a teammate would write it — no jargon, no commit hashes, no checklists. One
plain-English paragraph about what changed, plus the PR link and a screenshot
(`screencapture` of the widget).

## Arguments

- `type` ∈ `widget | feat | fix`
- `id` = the slug or issue number

## Steps

1. Gather: the PR/commit summary, and (for widgets) a screenshot of the widget
   running (`screencapture -x /tmp/<slug>.png`).
2. Write the note to
   `~/Desktop/deck-<type>-<id>-<YYYYMMDD>.md`:
   - One paragraph: what the user can now do/see.
   - "How to try it": `swift run <Widget>` (or the install path for native widgets).
   - PR link.
   - Screenshot embedded (relative path or inline image reference).
3. Keep it under ~15 lines. No internal terms (panel, milestone, PRD).

## Example shape

```markdown
# NetBox is here

You can now keep an eye on your network from the desktop: NetBox shows your
current upload/download speed as a live chart, right next to your other widgets.

**Try it:** `swift run NetBox` — drag it anywhere, or flip it to pick colors.

[PR #42](https://github.com/haqaliz/deck/pull/42) · screenshot: netbox.png
```
