# ClipBox PRD

Slug: `clipbox` · Type: `feat` · Source: `deck-next` handoff (2026-08-13) + interview.

## 1. The ask

ClipBox is a clipboard history widget: it shows the last copies with previews,
local only. Clipboard is another app's data — the sandboxed widget cannot read
it — so the unsandboxed DeckAgent samples `NSPasteboard` on its 60s tick and
pumps a history snapshot into the widget container, exactly like GitBox/DevBox.

## 2. User-visible spec

### Front face (the widget card)

- **Header row**: "CLIPBOX" section title + item count ("7 items").
- **History list** (the metric story): most-recent-first rows, each with:
  - a colored dot (item kind: text / image / file / other),
  - a preview: text → truncated first line (1 line small, up to 2 lines
    medium/large); image → `Image · 1.2 MB`; file → `report.pdf`; other →
    `Other`;
  - a relative time ("2m ago").
- **Sizes**: small → newest 2 rows + count; medium → up to 3 rows + count;
  large → up to `historyCount` rows (default 5) with a two-line preview per
  text row.
- **Empty/unavailable states**: no snapshot or stale (`writtenAt` > 300s old)
  → the standard unavailable card ("No clipboard data — check that the Deck
  agent is running."). Empty history → "No copies yet".

### Back face (Deck app settings, ClipBox tab)

- **Show list** toggle (default on) — hide the history list, keep the count.
- **History count** stepper (default 5, range 3–20) — max rows kept in the
  snapshot and shown on the large face.
- **Text / image / file / other** color pickers (defaults: text = indigo,
  image = pink, file = blue, other = gray) — dot colors.
- **Clear history** button — deletes the snapshot file (host-side).

## 3. Data source

- **Source**: `NSPasteboard.general` in `DeckAgent` (unsandboxed CLI, user
  session). No permissions prompt expected (pasteboard reads don't gate on
  Accessibility), but first-run verification is required (Phase 6 probe).
- **Cadence**: agent tick every 60s (`com.deck.agent` LaunchAgent). The
  sampler loads the prior snapshot, reads the pasteboard `changeCount` +
  content, appends a new `ClipItem` when the top content changed, trims to
  `historyCount`, saves. **The snapshot is re-written every tick** (cheap
  file) so `writtenAt` stays fresh even when nothing changed — otherwise the
  widget's 300s staleness window would wrongly flip it to "unavailable".
  Rapid consecutive copies within one minute collapse to the newest — a named
  v1 limitation (see 6.3).
- **Dedupe**: consecutive identical content does not duplicate; timestamp
  updates to the latest copy time.
- **Unavailable**: `snapshot()` returns `nil` when the pasteboard is
  unreadable at all (widget shows the unavailable card, DevBox nil precedent
  `DevBoxSnapshot.swift:76`); a readable-but-empty pasteboard yields an empty
  items snapshot → "No copies yet". Distinguishes "agent broken" from
  "nothing copied".
- **Capture scope** (interview decision): text items store full content
  bounded by `historyCount` and a **per-item text cap (4 KB)** so a giant
  paste can't balloon the snapshot JSON; image/file items store metadata only
  (kind, name, best-effort byte size) — no thumbnails in v1.
- **Background-read risk (named)**: `NSPasteboard` reads from a background
  CLI normally deliver text; some data-provider-backed types (TIFF) can return
  empty to a non-foreground process. Classification uses the *types list*
  (always readable); byte size is best-effort and falls back to no-size on
  empty data. First slice must empirically probe the agent's read (Phase 6).

## 4. Shell fit

Reuses the agent-pumped pipeline end-to-end — no shell invariant touched:

| Shell piece | Reuse |
|---|---|
| `GitBoxSnapshot`/`DevBoxSnapshot` (snapshot + store) | `ClipBoxSnapshot` + `ClipBoxSnapshotStore` (new file `Shared/ClipBoxSnapshot.swift`) |
| `HostGitBoxSampler` (host-only sampler) | `HostClipBoardSampler` in the same file |
| `GitBoxWidget.swift` (copy-start template) | `ClipBoxWidget.swift` — provider, entry, unavailable view, small/medium/large |
| `DeckSettings.swift` tolerant-decode structs (PR #8) | `ClipBoxSettings` with `decodeIfPresent` defaults |
| `DeckApp.swift` sidebar/tab/refresh pattern | `DeckWidget.clipbox` case + `ClipBoxSettingsView` + `refreshClipBox()` |
| `DeckAgent/main.swift` | one extra sampler call |

## 5. Non-goals (v1)

- No clipboard writes from the widget (sandbox forbids; no "copy back").
- No image thumbnails, no rich-text rendering (RTF/HTML shown as plain text
  preview).
- No filtering/search, no pinning, no sync or sharing of history.
- No faster-than-60s granularity (agent cadence is a shell invariant).
- No history in the widget itself — settings app only.

## 6. Open questions (resolved)

1. **Storage depth** — full text for text items, metadata for images/files.
   (interview, 2026-08-13)
2. **Non-text previews** — type-labeled rows, no thumbnails. (interview)
3. **Clear history** — settings-tab button that deletes the snapshot. (interview)
4. **Staleness** — reuse GitBox's 300s window (`GitBoxWidget.swift:50`).
5. **Dedupe key** — normalized top pasteboard content, not `changeCount`
   alone (changeCount also bumps on transient app-side set operations).
6. **Storage guard** — 4 KB per-item text cap (critique round, 2026-08-13).
7. **`writtenAt` freshness** — snapshot re-written every tick, not only on
   change (critique round, 2026-08-13).

## 7. Constraints

- 60s cadence everywhere; do not fight WidgetKit throttling (CLAUDE.md).
- Settings app-only, tolerant decode (PR #8 precedent).
- Pure logic (pasteboard classification, preview formatting, history merge,
  trim) TDD'd in a scratch SwiftPM package, ported into `Shared/`, removed
  pre-merge (DevBox/OpenBoxTools precedent).
- Register in `README.md`, `ROADMAP.md` (tick M3 ClipBox `[x]`).
