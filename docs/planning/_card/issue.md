# ClipBox — inline brief

Source: `deck-next` handoff (2026-08-13), pick: `clipbox` (M3 candidate,
ROADMAP.md:47).

ClipBox: clipboard history widget with previews, local only. The unsandboxed
DeckAgent reads NSPasteboard on its 60s tick (changeCount changed → snapshot
current item), writes a ClipBox snapshot to the widget container; the widget
reuses the GitBox/NetBox shell with text preview rows, history count and trim
in settings. One metric story: history of copies.

## Caveats to resolve in the PRD

- **60s granularity**: rapid consecutive copies within a minute collapse to the
  newest pasteboard state (one snapshot per agent tick, deduped by
  changeCount+content) — acceptable for v1, must be named in the PRD.
- **Plaintext history**: history lives as plaintext in the widget container
  (~/Library/Containers/com.deck.app.widgets/...); keep it local-only by
  default (no sync), clearable in settings.
- **Previews**: text items preview as truncated text; non-text items (images,
  files) preview as a type label — confirm scope in the PRD interview.

## Constraints from the pick

- Shell untouched in behavior: agent-pumped snapshot path, 60s cadence,
  settings via the tolerant-decode structs (PR #8).
- Pure logic (pasteboard change detection, dedupe, trim, formatting) unit-tested
  in a scratch SwiftPM package (DevBox/OpenBoxTools precedent, removed
  pre-merge).
