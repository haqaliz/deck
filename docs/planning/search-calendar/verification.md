# Verification: search-calendar

Status: **complete and verified** — automated suite green, signed build
installed, and the live panel steps run by the user (see "Live run" below).

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

## Live run (user-driven, 2026-10-11)

The panel needs a human at the screen — there is no computer-use tooling here —
so these steps were run by the user on the installed build and reported back. All
four behaved as expected:

1. Settings → Search → **Calendar events** on → the macOS access prompt appeared
   **in context, with Deck frontmost** (the fix). Allowed.
2. ⌥Space → `cal <a real event word>` → a **CALENDAR** section with real events
   and `date · calendar` subtitles.
3. Enter on an event with a meeting link → browser opened it; Enter without one →
   title copied; Cmd-Return → copied.
4. Denied path (Deck switched off under Privacy & Security → Calendars) → the
   one-line reason showed and **no prompt appeared**.

**Attribution.** These are the user's observations, not the assistant's — the
assistant cannot see the panel. They are recorded as such rather than restated as
independently measured.

**Not separately measured:** the read cost of a broad prefix-free query (time
from stop-typing to the section filling). It was not reported, so no number is
claimed; the prefix-free decision is unaffected.

