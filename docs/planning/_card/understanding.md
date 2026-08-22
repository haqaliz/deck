# WeatherBox + ClockBox split — Phase 2 understanding

## What the work is really asking

Two units of work bundled in one card:

1. **Rename** HomeBox -> WeatherBox and drop its world-clock half.
2. **New widget** ClockBox: up to 4 analog world-clock faces, user-picked cities.

ClockBox is the *only* widget so far that needs **no data path at all** —
not agent-pumped, not even a syscall sampler. It is pure `TimeZone` +
`Date`, resolved at render. That makes it the cheapest widget in the set
and removes the whole snapshot/FetchStatus layer from its design.

## Affected files

| File | Change |
|---|---|
| `Shared/HomeBoxSnapshot.swift` | drop `ZoneRow`/`ZoneRows` (moves to ClockBox core) |
| `Shared/DeckSettings.swift` | `homebox` -> `weatherbox` + legacy fallback; add `clockbox`; FIX missing `calbox` decode |
| `DeckWidgets/HomeBoxWidget.swift` | -> `WeatherBoxWidget.swift`, clock rows removed |
| `DeckWidgets/ClockBoxWidget.swift` | NEW |
| `Shared/ClockBoxCore.swift` | NEW — pure city/zone/offset/hand-angle logic |
| `DeckWidgets/DeckWidgets.swift` | bundle registration |
| `DeckApp/DeckApp.swift` | rename tab; new ClockBox tab with city picker |
| `native/project.yml` | version bump (new widget -> gallery re-enumeration) |
| `SharedTests/ClockBoxTests.swift` | NEW |
| `README.md`, `ROADMAP.md`, `CLAUDE.md` | widget roster is documented in all three |

Snapshot file needs **no** rename: it is already `weather.json`.

## Findings that change the design

1. **`calbox` is dropped on decode** (`DeckSettings.swift:45` vs `init(from:)`).
   Pre-existing bug, not caused by this work, but this work edits that exact
   initializer and must not repeat the omission. Fix it here.

2. **Widget `kind` rename is destructive.** WidgetKit keys a placed widget by
   its `kind` string. Changing `"HomeBoxWidget"` -> `"WeatherBoxWidget"`
   orphans any HomeBox the user has on the desktop. Mitigated in this case:
   a full uninstall/reinstall is already planned separately, and every widget
   is being re-added by hand anyway.

3. **The offset label is relative to LOCAL, not UTC.** In the reference
   screenshot Tehran reads `+0HRS` while Toronto reads `-7:30` — so the user's
   own zone is the zero point. Naming it "UTC offset" would be wrong.

4. **Second-hand sweep is the main technical risk.** CLAUDE.md: WidgetKit
   floors timeline regeneration at ~60s. LiveBox already beats this with
   `TimelineView(.periodic)` re-rendering inside one entry, so a ticking
   second hand is *possible* — but at 1s it is far more expensive than
   LiveBox's 15s default, on a widget whose whole appeal is that it is cheap.

## Open questions for the PRD

- Second hand: sweep at 1s, or minute-resolution only (no second hand)?
- City picker: curated city list with real names ("Toronto, Canada"), or raw
  `TimeZone.knownTimeZoneIdentifiers`? The native widget shows city names,
  and IANA ids give "America/Toronto" -> "Toronto" but no country.
- Does ClockBox need small/medium/large, or medium+large only? Four faces
  will not fit a small square.
- Keep `showZones` in WeatherBox settings as a dead key, or drop it?
