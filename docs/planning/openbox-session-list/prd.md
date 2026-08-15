# PRD: openbox-session-list

> Critique (2026-08-15): no 🔴 (no shell invariant touched; data source
> verified live). 🟡 fixed: SQL `LIMIT ?` dropped (reader has no parameter
> binding — mapper caps, keeping top-N testable); relative-time column pinned
> to a fixed 48pt width; empty-string titles filtered; placeholder rows
> added so the gallery preview renders the section.

## 1. The ask

Add a **SESSIONS** section to OpenBox's large face: the top sessions of the
last 14 days by total tokens, one line each (title + tokens + relative time),
capped by a settings count. It is a follow-on slice of the shipped OpenBox
widget (ROADMAP.md:73) — data already flows via the agent's opencode snapshot.

## 2. User-visible spec

### Front face (large only)

A new optional section on the large face, below MODELS/TOOLS sections, above
the "All time" footer:

```
SESSIONS
Refactor deck-next handoff        412K  2h ago
NetBox interface picker spike      96K  1d ago
Fix remote token degrade           31K  3d ago
```

- Section title "SESSIONS": 10pt bold rounded, secondary, tracking(1) — the
  established section-title style (`tracking(1)`).
- One row per session: `title` (primary, 11pt semibold rounded, lineLimit 1,
  truncation tail), `Spacer()`, right-aligned `tokens` (11pt semibold,
  monospacedDigit, `inputColor`), then relative time (9pt medium, secondary)
  pinned to a fixed `frame(width: 48, alignment: .trailing)` so all rows'
  time labels align down the column.
- Visible only when `showSessions` is on AND the list is non-empty. Hidden
  when off, empty, or stale (snapshot unavailable state already covers
  staleness).

### Settings (Deck app → OpenBox tab)

- `Toggle("Show sessions", isOn: $settings.showSessions)` — default **off**
  (per user decision: large face unchanged until enabled).
- `Stepper("Sessions: \(settings.sessionCount)", value: $settings.sessionCount,
  in: 1...5)` — default **3**, disabled when the toggle is off. Range 1...5
  (one-line rows are cheap; 3 default matches the tool-usage count).

## 3. Data source

- **Local path**: `OpenCodeReader` reads `~/.local/share/opencode/opencode.db`
  every 60s in `DeckAgent`. New `sessionsSQL`:

  ```sql
  SELECT title, tokens_input, tokens_output, time_created
  FROM session
  WHERE time_created > (strftime('%s','now','-13 days')*1000)
    AND title IS NOT NULL
  ORDER BY (tokens_input + tokens_output) DESC
  ```

  The `session` table has `title, directory, model, tokens_input,
  tokens_output, cost, time_created, time_updated` (verified against the live
  DB). No `LIMIT` in SQL — the reader's `rows(_:sql:)` has no parameter
  binding, so the pure mapper caps to `sessionCount` (also keeps top-N
  purely testable). The mapper additionally drops empty-string titles.
- **Remote path**: `RemoteOpenCodeLoader` returns remote sessions without
  `title`/`directory` → `sessionList` degrades to `[]`; the section hides.
  Stated, not silent.
- **Unavailable**: section hides when the list is empty; the existing
  snapshot-staleness empty state already covers a dead DB.
- **Cadence**: 60s (agent + widget timeline) — unchanged, per the shell
  invariant; do not fight WidgetKit throttling.

## 4. Shell fit

- Reuses the full OpenBox shell: snapshot (`OpenCodeSnapshot`), store
  (`OpenCodeSnapshotStore`), entry/provider, settings struct + tab, tracked
  section-title + row styling from `modelsList`/`toolsList`.
- One deviation to flag: none — the large face only gains one optional
  section; the settings gain one toggle + one stepper (the tool-usage
  pattern, `OpenBoxSettingsView`).
- Tolerant decode (`decodeIfPresent ?? []`) keeps old snapshots valid —
  PR #8 pattern.

## 5. Non-goals

- No interactive drill-down / tap-through (WidgetKit on macOS has no in-widget
  navigation; only whole-widget links exist — out of scope).
- No per-session detail (message counts, diffs, folder tree).
- No session list on small/medium faces.
- No per-session chart or cost display in rows (cost is a non-goal for rows).
- No changes to remote mode's snapshot shape.

## 6. Open questions

All resolved with the user (2026-08-15):
1. Ordering → total tokens desc. 2. Window → 14 days. 3. Row → title + tokens
+ relative time. 4. Default → off, count 3, range 1...5.

## 7. Tests (DeckSharedTests)

- Extend the `OpenCodeSQLTests` fixture `CREATE TABLE session` (and its
  INSERT helper) with `title` and `time_created` rows; assert `sessionList`
  ordering by total tokens, the 14-day window filter, and the mapper's
  top-N cap + empty-title filtering.
- `OpenBoxCore` (or the new parser location): relative-time formatter
  (seconds → "2h ago", "3d ago", "just now"), row mapping with nil-title
  filtering.
- Snapshot tolerant decode: decode a fixture JSON without `sessionList` → `[]`.
- Widget placeholder entry gets `sessionList` rows so the large-face preview
  renders the section in the gallery.
