# ClipBox — understanding note (Phase 2 dig)

## What the work is really asking

A sixth widget, fully agent-pumped (clipboard is another app's data, so the
sandboxed widget can't touch it). One metric story: recent copies, with
previews. Reuses the exact GitBox/DevBox agent-pump pipeline.

## Affected files (all in `native/`)

| File | Change |
|---|---|
| `Shared/ClipBoxSnapshot.swift` (new) | `ClipBoxSnapshot` (Codable) + `ClipBoxSnapshotStore` + `HostClipBoardSampler` (pasteboard read + history merge) |
| `Shared/DeckSettings.swift` | `ClipBoxSettings` (tolerant decode, PR #8 pattern): showList, historyCount, colors |
| `DeckAgent/main.swift` | call `HostClipBoardSampler.snapshot(maxCount:)`; save if changed |
| `DeckApp/DeckApp.swift` | `DeckWidget.clipbox` case (title/systemImage/tab), `ClipBoxSettingsView`, `refreshClipBox()` in onAppear + 60s timer |
| `DeckWidgets/ClipBoxWidget.swift` (new) | copy GitBox widget shell; small/medium/large; unavailable view |
| `DeckWidgets/DeckWidgets.swift` | register `ClipBoxWidget()` |
| `README.md`, `ROADMAP.md` | register widget; tick M3 ClipBox `[x]` |

## Key mechanics

- Agent is a CLI that runs every 60s and exits (`DeckAgent/main.swift:1-44`);
  it already loads settings itself, so ClipBox history **accumulates in the
  snapshot file**: sampler loads prior snapshot, compares pasteboard
  `changeCount`/content, appends a `ClipItem` when changed, trims to
  `historyCount`, writes back. Widget renders the snapshot (same staleness
  window as GitBox: `writtenAt > -300`).
- Pasteboard types: `.string` (text preview), `.fileURL` (name preview),
  `.tiff`/`.png` (image → type label + byte size), fallback `.other`. Pure
  mapping logic is TDD-able in a scratch SwiftPM package.
- Settings tab mirrors `GitBoxSettingsView` (`DeckApp.swift:373`); sidebar
  enum at `DeckApp.swift:205-233`; widget registration `DeckWidgets.swift:6-13`.
- Refresh wiring: `onAppear` + 60s timer `DeckApp.swift:48-64`; host refresh
  funcs `DeckApp.swift:105-125`.

## Ambiguities / open questions (for the PRD interview)

1. **Granularity**: 60s tick means copies within the same minute collapse to
   the newest — accepted in the brief, but confirm v1 behavior (timestamp
   dedupe vs. changeCount dedupe).
2. **Content storage**: store full text content per item (real history, more
   storage/privacy) or only previews (lighter, still glanceable)?
3. **Preview scope**: images/files — store nothing beyond metadata, or inline
   image thumbnail (widget can't render NSImage from snapshot? it can — SwiftUI
   Image(uiImage:) via data)? Keep v1 to text + type-labeled rows.
4. **Clear action**: settings tab "Clear history" button? (widgets can't
   mutate) — agent/host-side delete.
5. **Pasteboard read from a CLI**: NSPasteboard.general is readable from an
   unsandboxed CLI in the user session; verify with an empirical probe during
   Phase 6 (first agent tick must produce a snapshot, not nil).

## Invariants (from CLAUDE.md) — none broken

- Agent-pumped path for sandbox-blocked data ✓ (matches OpenBox/GitBox/DevBox)
- 60s cadence, no fighting WidgetKit throttling ✓
- Settings app-only with tolerant decode ✓
- Pure logic TDD'd in scratch package, removed pre-merge ✓
