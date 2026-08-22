# WeatherBox + ClockBox split — PRD

## Ask

Split `HomeBox` into two widgets: **WeatherBox** (conditions + 3-day forecast,
the existing weather half, renamed) and a new **ClockBox** showing up to four
world clocks for user-selected cities. Slug: `weatherbox-clockbox-split`.

Source: inline brief -> `docs/planning/_card/issue.md`; code map in
`docs/planning/_card/understanding.md`.

### Design decision that overrides the brief

The brief and its reference screenshots show the native macOS World Clock
widget's **analog** faces. In the requirements interview the user chose
**digital only** — "no need to show visual clock! just numbers are enough".
ClockBox therefore renders no dial. It keeps the native widget's *information*
(city name, relative day, offset from local) and drops its *form*.

Consequences: no hand-angle geometry, no sub-minute tick problem, and the
widget sits comfortably on the plain 60s timeline. This is the single largest
simplification in the design and the reason ClockBox needs no `TimelineView`.

## User-visible spec — ClockBox

### Front face

Per city, four elements:

| Element | Example | Notes |
|---|---|---|
| City name | `Toronto` | from the curated list; bold |
| Time | `05:27` | 24h, monospaced digits, the largest element |
| Relative day | `Today` | `Yesterday` / `Today` / `Tomorrow` vs the local date |
| Offset from local | `-7:30` | **relative to the user's own zone, not UTC** |

The offset zero case renders `+0HRS`, matching the native widget's own label
for the user's home city.

- **Small** — one city (the first selected). Large time, city, day, offset.
- **Medium** — up to 4 cities in a row, each a stacked column.
- **Large** — up to 4 cities, same columns with more vertical breathing room.

Empty state (no cities selected): "No cities selected" + a hint to open Deck
settings. Never a blank widget.

### Back face (Deck settings window, ClockBox tab)

| Control | Default |
|---|---|
| City list (add / remove / reorder, max 4) | `["local", "UTC"]` migrated from `homebox.timezoneIDs` |
| Show relative day | on |
| Show offset | on |
| Time color | `.primary` |

City picker is a **curated list** of major cities with display names
("Toronto, Canada") mapped to IANA identifiers, so names match the native
widget rather than showing raw `America/Toronto`.

## User-visible spec — WeatherBox

No functional change beyond the removal. Same location field, same units
toggle, same forecast toggle, same 3-day forecast. The world-clock rows and
the `showZones` toggle are gone.

Display name in the gallery becomes "WeatherBox"; description drops the
clock mention.

## Data source

**ClockBox: none.** Pure `TimeZone` + `Date`, resolved at render inside the
widget. This is the first Deck widget on neither data path — not agent-pumped,
not even a syscall sampler. No snapshot file, no `FetchStatus`, no staleness
chip, no DeckAgent work at all. Unavailable-source case does not exist; an
invalid saved IANA id is simply dropped from the list.

Refresh: the standard 60s timeline. Minute-resolution display means a 60s
cadence is exactly right — no sub-minute need.

**WeatherBox:** unchanged — DeckAgent fetches wttr.in every 60s and writes
`weather.json`. Note the snapshot file is *already* named `weather.json`, so
the rename touches no snapshot path.

## Migration

Three renames, each of which can silently destroy user data if done naively:

1. **Settings key** `homebox` -> `weatherbox`. Decode `weatherbox` first,
   fall back to a legacy `homebox` key when absent, so an existing
   `settings.json` keeps its location and units.
2. **`homebox.timezoneIDs` -> `clockbox.cityIDs`.** Carried over on first
   decode so a user's existing zones become their ClockBox cities. Capped at
   4 (the old cap was 3, so nothing is ever truncated).
3. **Widget `kind`** `"HomeBoxWidget"` -> `"WeatherBoxWidget"`. WidgetKit keys
   a placed widget by `kind`, so this orphans any HomeBox already on the
   desktop; the user must re-add it. Accepted: a full uninstall/reinstall is
   already planned separately and every widget is being re-added by hand.

### Pre-existing bug fixed here

`DeckSettings.swift:45` declares `var calbox = CalBoxSettings()` but the
custom `init(from:)` never assigns it — every other section has a
`decodeIfPresent` line and `calbox` does not. Encoding writes it, decoding
discards it, so CalBox settings reset to defaults on every load. Not caused by
this work, but this work edits that exact initializer and must not repeat the
omission. Fixed as part of the settings phase.

## Shell fit

Reuses the shell unchanged: rounded system fonts, monospaced digits, section
titles tracked 1pt, `containerBackground(for: .widget) { Color.clear }`,
three families. No panel invariant is touched.

Two shell obligations from CLAUDE.md apply:

- **Version bump** in `native/project.yml` — adding a widget without raising
  `CFBundleShortVersionString`/`CFBundleVersion` leaves it invisible in the
  Widget Center because WidgetKit caches the descriptor set per version.
- **`xcodegen generate`** after adding source files — xcodegen enumerates
  files at generation time, so a new test file is silently not compiled and
  the suite still reports success.

Widget roster is documented in `README.md`, `ROADMAP.md` and `CLAUDE.md`;
all three need the rename and the new entry.

## Non-goals

- No analog clock face (explicit user decision above).
- No alarms, timers, or stopwatch.
- No automatic city detection from location.
- No per-city 12h/24h override — one format for all faces.
- No DST-transition warnings.
- More than 4 cities.

## Open questions

None blocking. Two judgement calls taken by default, flag if wrong:

- 24h time format, matching the existing `ZoneRows` formatter (`HH:mm`).
- `showZones` is dropped rather than kept as a dead key, since the settings
  decoder tolerates unknown keys and the value has no remaining meaning.

---

# Self-critique (Phase 4)

## 🔴 Red

**R1 — "60s timeline is exactly right" is wrong; the clock would be visibly
late.** A `.after(now + 60)` policy is not phase-aligned to the minute
boundary. Regenerate at :17 past and every face shows the previous minute for
43 more seconds. A clock that displays the wrong minute for most of every
minute is a broken clock, and this is the widget's only job.
*Fix:* prefer SwiftUI's self-updating `Text(date, style: .time)` with
`.environment(\.timeZone, zone)` per face — WidgetKit keeps it current with no
timeline work. Verify that first (see R1-spike); if it does not honour the
environment timeZone, fall back to a multi-entry timeline with one entry per
minute boundary via `Calendar.nextDate(after:matching: second == 0)`.
*R1-spike:* confirm `Text(_:style:)` respects `\.timeZone` inside a widget
before committing the layout to it. This is the one real unknown in the design.

**R2 — the legacy `homebox` fallback as written does not compile.**
`DeckSettings` decodes with *synthesized* `CodingKeys` (`DeckSettings.swift:61`).
Renaming the property to `weatherbox` deletes the `homebox` case, so
`decodeIfPresent(..., forKey: .homebox)` has no key to reference. Adding
`homebox` to the main `CodingKeys` instead breaks the synthesized *encoder*,
which would then try to write a property that no longer exists.
*Fix:* explicit `CodingKeys` covering the current schema only (encode path
stays synthesized-equivalent), plus a separate `private enum LegacyCodingKeys`
used for a second keyed container read purely for the `homebox` fallback.

**R3 — settings persistence has no regression guard, and the `calbox` bug
proves the gap is real.** The PRD says to fix `calbox` and to add `clockbox`,
but nothing stops the next widget from repeating the same one-line omission.
*Fix:* make it an acceptance criterion — a round-trip test that encodes a
`DeckSettings` with every section set to non-default values, decodes it, and
asserts equality. That single test catches `calbox` today and `clockbox`
tomorrow. Add it in the settings phase, before the rename.

## 🟡 Amber

**A1 — `"local"` is not an IANA identifier.** It is the existing sentinel in
`timezoneIDs` (default `["local", "UTC"]`) and migration carries it straight
into `cityIDs`, but a curated city list keyed by IANA id has nowhere to put it.
*Fix:* keep `"local"` as an explicit sentinel; resolve to `TimeZone.current`,
label it with that zone's city name, always render offset `+0HRS`.

**A2 — offsets must be computed per-date, not statically.** Use
`secondsFromGMT(for: date)` for both zones and subtract; a fixed offset is
wrong for half the year across DST boundaries, and the two zones can shift on
different dates. Non-hour zones (Kathmandu `+5:45`, Chatham `+12:45`) must
format exactly — `±H:MM` covers them, but state that minutes are never rounded.

**A3 — small size can render a useless widget.** "Small shows the first
selected city" plus the migrated default `["local", "UTC"]` means small shows
your own time labelled `+0HRS` — a clock that tells you nothing.
*Fix:* small shows the first **non-local** city, falling back to local only
when that is the only entry.

**A4 — existing tests move, and the xcodegen trap can hide it.**
`ZoneRowsTests` (7 assertions) lives inside
`SharedTests/HomeBoxSnapshotTests.swift`. Extracting `ZoneRows` into a ClockBox
core means moving them. Per CLAUDE.md, a new `ClockBoxTests.swift` added
without re-running `xcodegen generate` is silently not compiled **and the suite
still reports success** — so the rename must be verified by asserting the test
count went up, not just that the suite is green.

**A5 — the widget count is written into three docs.** "eleven" at
`README.md:28`, `ROADMAP.md:4`, `CLAUDE.md:36`, and "11 widgets" at
`CLAUDE.md:46`. Twelve after this work.
