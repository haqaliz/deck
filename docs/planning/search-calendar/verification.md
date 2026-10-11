# Verification: search-calendar

Status: **code complete and tested; the live run is not observed** (the user left
before driving the panel — see "Still to observe").

## Automated

- `DeckSharedTests`: **1675 tests, 0 failures** (baseline 1673; +2 new).
  New suite `CalendarSearchAccessTests`:
  - `testSettingsAsksOnlyWhenMacOSHasNeverBeenAsked` — prompt only for status `0`.
  - `testThePanelReadsOnlyWithFullAccess` — read only for status `3`.
- **RED→GREEN watched**: the two tests first failed to compile
  ("cannot find 'CalendarSearchAccess' in scope"), then passed after the type was
  added.
- Builds: `xcodebuild … -configuration Release` succeeds both unsigned
  (`CODE_SIGNING_ALLOWED=NO`) and signed (Apple Development).

## Code changes

- `native/Shared/EventSearch.swift` — added `CalendarSearchAccess`
  (`shouldRequestOnEnable` / `panelCanRead`, both delegating to the pinned
  `CalendarAccess`). **Removed the `requestAccess` branch from
  `HostEventSearch.events`**: the panel now only reads, or throws
  `SearchSourceFailure(.calendarAccess)`.
- `native/Shared/CalBoxSnapshot.swift` — `HostCalendarLoader.authorizationStatus`
  (raw `EKAuthorizationStatus`), so callers can decide without importing EventKit.
- `native/DeckApp/SpotlightSettingsView.swift` — the Calendar events toggle now
  requests access **on the off→on transition, only when macOS has never been
  asked**, from the active settings window; the row copy is corrected to "macOS
  asks for calendar access **when you turn this on**."

## Invariant

`grep -rn "HostEventSearch" native/DeckAgent native/DeckWidgets` — **empty**.
Calendar search remains host-app only; the widget reads its snapshot.

## Installed for the live run

Release build installed over `/Applications/Deck.app` (v1.51), `scripts/lsclean.sh`
run, app relaunched. `settings.json` still has `spotlight.eventEnabled: false`, so
the live test starts from a clean, off state.

## Still to observe (not claimed)

The panel needs a human at the screen; there is no computer-use tooling here.
Run these on the installed build and record the results:

1. Settings → Search → toggle **Calendar events** on → the access prompt should
   appear **in context, Deck frontmost** (the fix). Allow. (No prompt at all is
   also meaningful: it would mean Deck.app already held the grant.)
2. ⌥Space → `cal <a real event word>` → a **CALENDAR** section with real events
   and `date · calendar` subtitles.
3. Enter on an event with a meeting link → browser opens it; Enter without one →
   title copied; Cmd-Return → copies.
4. Denied path: revoke Deck under System Settings → Privacy & Security →
   Calendars, search again → the one-line reason shows and **no prompt appears**.
5. Read cost of a broad query (time from stop-typing to the section filling).

Until these are run, this file claims **nothing** about the live EventKit read,
the prompt, or the meeting link — only that the decision logic that gates them is
tested and the build is green.
