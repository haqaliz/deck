# search-calendar — understanding note (Phase 2)

## What the work is really asking

The calendar Search source is fully **built** and its *pure* logic is
**unit-tested**. What is not exercised is the live EventKit read and the panel's
interaction with the macOS calendar-access prompt. The verification record says
so plainly: "off by default and not enabled in testing, so macOS was not asked
for calendar access and no calendar was read. The EventKit path, the access
prompt and the meeting-link action are unexercised"
(`docs/planning/spotlight-more-sources/verification.md:49-53`).

So the unit of work is: **enable it, read it live, and fix what the live read
contradicts** — with the honest possibility that it just works and the output is
a verification record. The one place a *code change* is already implied by the
existing design is the access-prompt path (below).

## Affected code (all of it exists)

- `native/Shared/EventSearch.swift` — `EventSearch` (pure matching/window) +
  `CalendarAccess` + `HostEventSearch.events` (the untested seam: the live read).
- `native/DeckApp/AsyncSearchCoordinator.swift:249` — `EventSearchSource`, the
  `AsyncSearchSource` the panel drives.
- `native/DeckApp/SpotlightPanel.swift:297` — registers it; the panel is a
  `.nonactivatingPanel` and **never activates Deck** (`:275-276`, `:324`).
- `native/Shared/DeckSettings.swift:724` — `eventEnabled`, default `false`.
- `native/DeckApp/SpotlightSettingsView.swift:112` / `:132-133` — the toggle and
  its copy.
- `native/DeckApp/DeckApp.swift:2806-2817` — the **CalBox** tab's in-context
  prompt (`requestAccess()` from the active settings window), the pattern to
  compare against.
- `native/Shared/RemoteSearchPolicy.swift:146` — the `calendarAccess` wording.
- `native/SharedTests/EventSearchTests.swift` — what is already pinned (matching,
  ranking, subtitle, action, unsafe-link, cap, window, truncation, and the four
  authorization-status mappings).

## The load-bearing risk: the prompt fires out of context, from a non-active app

`HostEventSearch.events` prompts when the status is `notDetermined`
(`EventSearch.swift:104-106`). The toggle lives in Settings, but nothing prompts
there — unlike CalBox's tab, which asks in context
(`DeckApp.swift:2806-2807`). And `.event` **does not require a prefix**
(`SpotlightCore.swift:48-53`), so as soon as the toggle is on, the first ordinary
≥2-character query (`RemoteSearchPolicy.minimumLength`) reaches the source and
triggers the system prompt — **from a non-activating panel, while some other app
is frontmost**. That is:
- a prompt appearing as a side effect of typing, not of a deliberate action;
- attributed to Deck.app, which is not the active app at that moment.

The clean fix, matching Deck's own convention, is to request access **when the
Calendar toggle is switched on in Settings** (an active, in-context moment) and
let the panel only ever *read*. This is the concrete "enable" half of the brief.

## Second risk: cost per query

`HostEventSearch.events` re-reads the **whole two-year window** on every distinct
query (no snapshot reuse), then matches in memory. A year either side on a busy
calendar can be thousands of events; EventKit's `events(matching:)` is
synchronous and runs in a `Task.detached` (`EventSearch.swift:110`). The runner
debounces (300 ms) and floors (500 ms) per source, so it is not per-keystroke,
but the read cost is unmeasured. Worth measuring live.

## Third risk (smaller): the store crosses actors

`store: EKEventStore = EKEventStore()` is the default argument, evaluated at the
`@MainActor` call site, then captured into `Task.detached`
(`EventSearch.swift:98-136`). `EKEventStore` is not `Sendable`; under Swift 5.10
this compiles. It may be benign (the store is used only inside the detached
task) but it is a latent concurrency smell worth a look, and CalBox's own
`fetch` has the same shape.

## Ambiguities / open questions (for the interview)

1. **Scope.** Verification-only, or verification **plus** moving the access
   prompt into the settings toggle (the in-context fix above)? The brief's word
   is "enable"; the honest reading of "enable" that matches CalBox is the fix.
2. **Grant state on the row?** The CalBox tab shows whether access is granted;
   the Search row carries only static copy. Should the Calendar row say when
   access has not been granted, so the user knows what the prompt was?
3. **Prefix.** Should calendar also be prefix-only (like `pr`/`commit`/`mkt`),
   since an unscoped query now reads the whole calendar? The existing decision
   is deliberately "no — calendar never leaves the Mac" (`SpotlightCore.swift:46`),
   but that was written before anyone measured the read cost.
4. **Default state.** Stays off by default (the sharing-panel rationale).
5. **What can actually be observed here.** The panel needs a human at the
   screen; the EventKit read can be driven, but only by a process that holds the
   grant (Deck.app via its settings/panel, or DeckAgent). This bounds what the
   verification can claim.

## Panel invariants to respect (CLAUDE.md)

- **Host-app only.** `grep -rn "HostEventSearch" native/DeckAgent native/DeckWidgets`
  must stay empty. Calendar *search* is a panel source; the CalBox *widget* reads
  its own snapshot and never touches EventKit.
- **EventKit access.** Only full access (raw `3`) may read; write-only (`4`) is a
  denial; never pass an empty `calendars:` array to `predicateForEvents`.
- The grant belongs to **Deck.app** (defer/panel), separate from DeckAgent's own
  grant; both carry `NSCalendarsFullAccessUsageDescription` (`project.yml`).
- Type steps: `xcodegen generate` after any new source file, or it is silently
  not compiled.
