# search-calendar (inline brief)

Source: `dbf task search-calendar`, handed off by `deck-next` (2026-10-11).

## Brief

Enable calendar search in the Search panel and verify it against a live calendar
— it shipped off by default with the EventKit path, the macOS access prompt and
the meeting-link action all unexercised
(`docs/planning/spotlight-more-sources/verification.md:49-53`). Turn the source
on, run real searches over the user's synced calendars, and fix whatever the live
read contradicts; record a `verification.md`.

Respect the panel invariants: host-app-only loaders (no new search caller in
`DeckAgent` or `DeckWidgets`), and reuse CalBox's `CalendarLink` for the meeting
link.

Caveat (from the recommender): this may be verification-only if EventKit works
first try — the deliverable is then a verification record plus any corrected
copy, not a feature.

## Why this and not something else

- Search is the newest, largest surface (M10, `ROADMAP.md:1062-1156`); calendar is
  its only never-exercised data path.
- The data source exists and is local-first (EventKit — the same transport CalBox
  already uses).
- The M10 follow-up names it directly (`ROADMAP.md:1089-1090`) and it is
  unblocked, narrow and testable.

## What is already built (do not rebuild)

- `native/Shared/EventSearch.swift` — pure matching + `HostEventSearch.events`.
- `native/DeckApp/AsyncSearchCoordinator.swift:249` — `EventSearchSource`.
- `native/DeckApp/SpotlightPanel.swift:297` — registration.
- `native/Shared/DeckSettings.swift:724` — `eventEnabled`, default `false`.
- `native/Shared/SpotlightCore.swift:147` — examples / copy.
- `native/SharedTests/EventSearchTests.swift` — pure-logic + access-status tests.

## Definition of done

- Calendar search enabled on the installed build and driven live.
- The EventKit read, the access prompt and the meeting-link action observed (or a
  fix shipped for whatever does not work).
- `docs/planning/search-calendar/verification.md` records what was measured and
  what was not.
- Panel invariant grep stays empty; `DeckSharedTests` green.
