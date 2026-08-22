# CalBox PRD

Slug: `calbox`
Source: ROADMAP.md M5 candidate + Phase 2 probe (`docs/planning/_card/issue.md`).
Date: 2026-08-22

## 1. The ask

A tenth Deck widget answering one question at a glance: **what is my next
event, and how long until it starts** — backed by today's remaining agenda.
Opens M5 (ROADMAP.md:100).

Route decided: **EventKit**, not the secret ICS URL and not Google OAuth.

### Why the roadmap's caveat was wrong

ROADMAP.md:104-108 records that `~/Library/Calendars/` is "empty on the dev
machine — no account is configured today". It is not empty; it is
TCC-protected, and `ls` reporting `Operation not permitted` was misread as
absence. A signed EventKit probe (`requestFullAccessToEvents`) on this machine
returned:

```
granted: true      calendars: 11      events next 7d: 61
  [Google] aliz@foresightanalytics.ca      [Google] Holidays in Canada / in Iran
  [iCloud] Work / Home / Calendar / Family [AOL] Ali Alizade / Apple Event
  [Subscribed Calendars] US Holidays       [Other] Birthdays
```

Google Calendar — the stated target — is already synced through Internet
Accounts, alongside iCloud and AOL. EventKit therefore delivers *more* than the
ICS route (which sees one calendar, cached by Google for hours) at a fraction of
the cost of OAuth. Routes 2 and 3 are dropped, with this as the recorded reason.

## 2. User-visible spec

### Front face (3 sizes)

Shell language throughout: rounded system fonts, monospaced digits, colored-dot
rows, section titles tracked 1pt, hidden axes.

- **Countdown block** (the headline, all sizes):
  - Next timed event's title, truncated to one line.
  - A **live** countdown beneath it — `in 42m`, `in 2h 05m`, `now`, or
    `12m in` once it has started. Rendered with `Text(_:style:)` so it ticks
    without a timeline reload (§5).
  - Start–end time in monospaced digits: `14:00 – 14:30`.
  - Dot in the event's own calendar color.
- **All-day row** (pinned above the agenda, medium/large; suppressed when
  empty): `Vitamin D · US Holidays` style, up to 2, then `+N`.
  All-day events **never** win the countdown (§4).
- **Agenda list** (colored-dot rows, chronological):
  - dot = source calendar color, time in monospaced digits, then title.
  - Events already finished today are dropped; an in-progress event stays and
    is marked `now`.
- **Header hint**: when the snapshot is older than 5 min, a muted `· HH:mm`
  last-update hint; the fetch-status chip (§6) sits on the same line.

Size split:

| Size | Content |
|---|---|
| Small | Countdown block only (title, countdown, times, dot). |
| Medium | Countdown block + all-day row + next `eventCount` events (default 4). |
| Large | Countdown block + all-day row + the rest of today (hard cap 8 rows, `+N more` when it overflows), then a `TOMORROW` section title and tomorrow's first 3. `eventCount` does not apply here. |

- **Empty states**:
  - No snapshot at all → unavailable view: "CalBox" / "No calendar data" /
    "Open Deck settings to pick your calendars."
  - Access not granted → unavailable view + chip "Allow calendar access".
  - No calendars selected → chip "Pick a calendar in settings".
  - Access fine, selected calendars, nothing left today → countdown block is
    replaced by "Nothing left today", and the large face still shows
    `TOMORROW`. This is a **success** state, not a failure — no chip.

### Settings (Deck app, CalBox tab)

| Control | Type | Default |
|---|---|---|
| Calendars | checkbox list of every `EKCalendar`, grouped by source title | writable calendars **on**, read-only ones **off** (§3) |
| `showAllDay` | toggle | true |
| `showAgenda` | toggle | true |
| `eventCount` | stepper 2–8 — governs the **medium** face only | 4 |
| `showTomorrow` | toggle (large face only) | true |
| `useCalendarColors` | toggle | true |
| `accentColor` | ColorPicker — used for every dot when `useCalendarColors` is off | `.blue` |

No color pickers per status: the calendars already carry meaningful colors, and
using them is both free and better than anything a picker would produce.

All settings tolerant-decode (pattern: `ShipBoxSettings`,
DeckSettings.swift:361-371).

## 3. Data source

- **API**: EventKit. `EKEventStore.requestFullAccessToEvents`, then
  `calendars(for: .event)` and `events(matching: predicateForEvents(...))`.
- **Transport**: **agent-side**. The read is a TCC-gated, other-apps' data read,
  which is exactly the "sandbox-blocked, agent-pumped" path (CLAUDE.md
  Architecture §2). `HostCalendarLoader` lives in `Shared/CalBoxSnapshot.swift`
  and is called from `DeckAgent/main.swift` and from the Deck app refresh, the
  same dual-pump as HomeBox/ShipBox.
- **Cadence**: 60s agent tick. Timeline rollover between ticks is handled by the
  provider, not the agent (§5) — a silent agent still shows a correct next
  event for the whole horizon.
- **Horizon**: `now → end of (today + 2 days)`, day-aligned so the window only
  moves at midnight rather than sliding every tick. Capped at 60 events.
- **Calendar defaults**: a calendar is **off** by default when
  `EKCalendar.allowsContentModifications == false`. Verified against this
  machine's 11 calendars — the flag is false for exactly `US Holidays`,
  `Holidays in Canada`, `Holidays in Iran` and `Birthdays`, and true for the
  seven real ones, including the Google account. This replaces an earlier
  title-prefix rule (`"Holidays…"`), which was locale-fragile and would have
  missed `Feiertage in Deutschland`; `sourceType` and `isSubscribed` were also
  rejected, as each catches only two of the four (see §10 C3).
  Persisted as a `[String]` of `calendarIdentifier`s plus a
  `hasChosenCalendars` flag, so the default rule applies once and a later
  deselection is never re-defaulted back on.
- **Recurring events**: `events(matching:)` expands a recurrence rule into one
  `EKEvent` per occurrence, so no rule evaluation is needed — but the
  occurrences **share one `eventIdentifier`** (verified: 17 events in +48h carry
  only 10 distinct identifiers). `CalEvent.id` is therefore
  `"\(eventIdentifier)@\(start.timeIntervalSince1970)"`, unique per occurrence
  and stable across ticks (§10 C1).
- **Duplicates**: events identical in `(title, start, end, calendarIdentifier)`
  collapse to one. Not hypothetical — `Aliz workout time` is genuinely present
  twice at 08:00 on two consecutive days in the Google calendar on this machine.
- **Declined events**: an event whose current-user `EKParticipant.participantStatus`
  is `.declined` is dropped. A meeting you said no to must never be the thing
  counting down.
- **Snapshot**:
  `CalBoxSnapshot { writtenAt, events: [CalEvent] }` written to
  `containerDirectory/calbox.json`. Access state is deliberately **not** a
  snapshot field — `FetchStatus` already carries it (§6), and two sources of
  truth for "can we read the calendar" is how they drift apart.
  `CalEvent { id, title, start, end, isAllDay, calendarTitle, color: RGBA }`.
  **Always written** on a successful read (matching ShipBox/HomeBox/ClipBox):
  `writtenAt` drives the staleness window and the "Agent hasn't run" chip, so a
  quiet calendar must still refresh it.
- **Privacy**: event titles land in the widget container in cleartext, which is
  the same posture as ClipBox (clipboard text) — local only, never sent
  anywhere. The agent's OSLog lines must log counts only, never titles.

## 4. Next-event selection (pure, TDD-able)

Given the snapshot's events and a reference `now`:

1. Partition into all-day and timed.
2. `next` = the timed event with the smallest `end > now`, i.e. an event already
   in progress beats one that has not started. Ties broken by earlier `start`,
   then by title, so the choice is stable across ticks.
3. All-day events are **excluded** from `next` entirely. An all-day "Holidays in
   Iran" must never be the thing counting down.
4. `agenda` = timed events with `end > now`, chronological, minus `next`.
5. `today` / `tomorrow` split by calendar day in the current time zone.

Countdown text from `next.start − now`:

| Condition | Text |
|---|---|
| `start − now > 1h` | `in 2h 05m` |
| `60s < start − now ≤ 1h` | `in 42m` |
| `|start − now| ≤ 60s` | `now` |
| started, not ended | `12m in` |

## 5. Liveness — the countdown must not lie

Three layers, none of which depend on the agent running:

1. `Text(next.start, style: .relative)` / `.timer` renders a ticking countdown
   in WidgetKit **without** a timeline reload.
2. The provider emits a **multi-entry timeline**: one entry now, plus one at
   each event boundary (`start` and `end`) inside the horizon, **plus the next
   midnight** so the today/tomorrow split on the large face turns over
   correctly. Boundaries are deduplicated, sorted, and capped at **24 entries**
   (a stated number, not "whatever WidgetKit allows"); past the cap the `.after`
   policy takes over. "Next event" therefore rolls over at the exact right
   second even if the agent is dead.
3. `.after(60s)` reload policy as the floor, matching every other Deck widget.

This is the reason the horizon is +48h rather than "today only": a countdown
that goes blank at 18:00 because nothing else is scheduled today is the failure
mode this widget exists to avoid.

## 6. Failure reporting

Reuses `FetchStatus.swift` with a new `FetchSource.calbox` and **no new
`FetchOutcome` case** — the outcome enum is a stable on-disk schema and the copy
layer already varies per source:

| Situation | Outcome | Face line | Settings hint |
|---|---|---|---|
| No calendars selected | `.notConfigured` | "Pick a calendar in settings" | "Nothing is read until at least one calendar is ticked." |
| TCC denied / restricted | `.authOrTarget` | "Allow calendar access" | "macOS is blocking calendar access. Grant it in System Settings → Privacy & Security → Calendars for Deck and DeckAgent." |
| EventKit threw | `.badResponse` | "Couldn't read the calendar" | "Reached the calendar store but couldn't read it. Retrying every minute." |
| Read succeeded | `.ok` | — | — |

`.unreachable` is unused: there is no network in this path.

## 7. Shell fit — and the one deviation

- **New files**: `Shared/CalBoxSnapshot.swift` (snapshot, store,
  `HostCalendarLoader`, selection + formatting logic),
  `DeckWidgets/CalBoxWidget.swift`, `DeckAgent/Info.plist`.
- **Touched, append-only**: `DeckSettings.swift`, `DeckApp.swift`,
  `DeckAgent/main.swift`, `FetchStatus.swift`, `DeckWidgets.swift`,
  `README.md`, `ROADMAP.md`.
- **🔴 Deviation — `project.yml` change (verified blocker).** `DeckAgent` is
  `type: tool` with no Info.plist (project.yml:75-88), so it cannot declare
  `NSCalendarsFullAccessUsageDescription` and the TCC request would be denied
  without ever prompting. Fix on the DeckAgent target:

  ```yaml
  settings:
    base:
      INFOPLIST_FILE: DeckAgent/Info.plist
      CREATE_INFOPLIST_SECTION_IN_BINARY: YES
  ```

  embedding `__TEXT,__info_plist`. `DeckApp/Info.plist` needs the same key.
  No panel invariant is touched — this is target configuration only.
- **Two TCC grants, by design.** DeckApp and DeckAgent are separately signed
  binaries, so macOS tracks them separately. DeckApp prompts in-context when the
  CalBox settings tab opens (that is where the calendar list is read); DeckAgent
  prompts on its next run. Precedent: DeckAgent already raises the "access data
  from other apps" prompt for its `ps` read (CLAUDE.md, Signing & install
  notes). The CalBox settings tab states plainly that both are needed.
- xcodegen regenerate required (new source files **and** the project.yml edit).

## 8. Non-goals

- **No writing.** Read-only: no creating, editing, accepting, or declining.
- **No OAuth and no ICS URL.** Recorded above with the reason; if a user has no
  account in Internet Accounts, the answer is "add it there", not a second
  transport.
- No join-meeting link extraction or tap-through (WidgetKit has no in-widget
  navigation — the ShipBox precedent, shipbox/prd.md:106).
- No reminders (`EKEntityType.reminder`) — that is TaskBox's job.
- No week or month grid; no attendee lists; no travel-time estimates.
- No per-calendar color overrides in settings (the calendars already have
  colors; one global accent is the only alternative offered).

## 9. Open questions

None blocking. Settled during the interview: EventKit route; calendar picker
with holidays/birthdays/subscribed defaulted off; countdown + today's agenda
across the three faces.

Deferred, with reasons:
- **Multi-day / week face** — no size left; large is already full.
- **Meeting-link surfacing** — blocked by the same no-navigation limit as
  ShipBox; a link you cannot tap is decoration.
- **Live countdown below 1 minute** (`in 45s`) — WidgetKit's `.timer` style can
  render it, but the value of second-precision on a desktop widget is low and it
  invites re-render churn. Revisit only if the minute granularity reads badly.

## 10. Critique log (self-critique pass, 2026-08-22)

Findings from pressure-testing this PRD. Everything below is **already applied
above**; it is recorded so the reasoning is not lost.

### 🔴 C1 — `eventIdentifier` is not unique per occurrence

The first draft used `EKEvent.eventIdentifier` as `CalEvent.id`. A probe of the
live store found **17 events in the next 48h sharing only 10 identifiers** —
recurring occurrences reuse the identifier. As a SwiftUI `ForEach` id that means
duplicate keys, dropped rows, and animation glitches.
**Fix applied (§3):** `id = "\(eventIdentifier)@\(start.timeIntervalSince1970)"`.

### 🔴 C2 — the `project.yml` Info.plist embed is unproven

§7 asserts `INFOPLIST_FILE` + `CREATE_INFOPLIST_SECTION_IN_BINARY` makes a
`type: tool` target carry `NSCalendarsFullAccessUsageDescription`. That is the
documented mechanism, but it is **not proven in this project**, and the whole
widget is dead if the TCC prompt never appears.
**Fix applied:** this becomes **task 1 of the plan** — a build-and-run spike that
regenerates the project, builds DeckAgent, checks the section is present
(`otool -s __TEXT __info_plist`), and confirms a real grant. Nothing else starts
until it passes. If it fails, the fallback (DeckApp does the read, agent does
not) is a face-preserving but cadence-losing plan B that must be re-approved.

### 🟡 C3 — the calendar-off default was locale-fragile

The draft defaulted a calendar off when its title began with `Holidays`. That
breaks in any non-English locale. Probing all 11 calendars showed
`allowsContentModifications` is false for exactly the four that should be off
and true for the seven that should be on — while `sourceType` and `isSubscribed`
each catch only two of the four (`Holidays in Canada` and `Holidays in Iran` are
plain calDAV Google calendars, indistinguishable by source).
**Fix applied (§2, §3):** default on writability, not on the title.

### 🟡 C4 — two sources of truth for calendar access

`CalBoxSnapshot.accessGranted` duplicated what `FetchStatus` already records,
and the two would drift (a snapshot written before a revocation keeps claiming
access).
**Fix applied (§3):** field removed; `FetchStatus` is the only authority.

### 🟡 C5 — duplicate events render twice

Verified in live data: `Aliz workout time` exists twice at 08:00 on consecutive
days inside one Google calendar.
**Fix applied (§3):** collapse on `(title, start, end, calendarIdentifier)`.

### 🟡 C6 — declined meetings could win the countdown

Nothing filtered them. The dev machine happens to have zero declined events in
the window, so this is a reasoned risk rather than an observed failure — but the
failure mode (counting down to a meeting you declined) is exactly the kind of
wrong the widget must not be.
**Fix applied (§3):** drop events where the current user's participant status is
`.declined`.

### 🟡 C7 — `eventCount` had undefined meaning on the large face

The stepper said 2–8 while the large face said "rest of today" — unbounded and
contradictory.
**Fix applied (§2):** `eventCount` governs medium only; large is a hard cap of 8
with `+N more`.

### 🟡 C8 — no midnight timeline entry

Entries were emitted at event boundaries only, so the today/tomorrow split on the
large face would stay wrong until the next agent tick or event start — which on a
quiet night is hours.
**Fix applied (§5):** the next midnight is always an entry.

### 🟡 C9 — "WidgetKit's practical entry budget" was hand-waving

**Fix applied (§5):** an explicit cap of 24 entries, with `.after(60s)` as the
documented fallback past it.

### Accepted as-is

- **Cleartext event titles in the container.** Same posture as ClipBox's
  clipboard text; local-only, never transmitted, and the alternative (encrypting
  a file both processes must read) buys nothing against a local attacker who can
  already read the calendar store.
- **Two TCC grants** (DeckApp + DeckAgent). Unavoidable for separately signed
  binaries; mitigated by saying so in the settings tab.
- **A snapshot is rendered however old it is.** Matches the M4 behaviour change
  for the agent-fetched widgets; the chip carries the honesty.

## 11. Revision — the face after first use (2026-08-22)

Shipping it and looking at it changed the design. Recorded here rather than
edited into §2 above, so the reasoning survives.

**The countdown is gone.** §2 made a live countdown the headline, and §5 argued
at length for a multi-entry timeline to keep it honest. Both were wrong:

- The countdown restated the row beneath it. `3:53:45 TO GO` and
  `20:00  Dinner time` are the same fact, and the row is the readable one.
- It sat in an unlabelled block above a `TOMORROW` heading, so the top half of
  the face read as belonging to nothing — the widget's worst legibility problem
  and one no amount of polish inside the block would have fixed.
- The multi-entry timeline that existed to serve it archived 24 full views into
  a **1.4 MB** timeline — 24x TaskBox's — which WidgetKit accepted, reported as
  `success`, and then drew as an empty widget. §5's premise was also simply
  false: the 60s reload re-runs the provider, which re-derives everything from
  the stored snapshot against the current time, so rollover already worked with
  the agent dead.

`NextEvent` (with its 90-minute in-progress grace rule) and `Countdown` were
deleted along with it rather than left as unused tested code.

**The face is now two labelled sections**, TODAY and TOMORROW, each with its own
show/hide toggle and row count (1–10, default 6 and 4). All-day events sit at
the top of TODAY and spend that section's budget first. Small and medium cap
lower than the setting, because past that the rows are clipped by the frame
rather than by the user — the TaskBox precedent.

**The widget name came off the face.** A widget's identity belongs in the
gallery, not in a header line that costs a row on every size.

**Settings migrate rather than reset**: `showAgenda` → `showToday` and
`eventCount` → `todayCount` are read once, clamped to 1–10, and dropped on the
next write. Covered by `CalBoxSettingsDecodeTests`.

**Operational lessons, both the hard way:**
- Adding a widget needs a `CFBundleVersion` bump or the Widget Center never
  re-enumerates it — the gallery caches descriptors per extension version.
- A widget instance placed while a broken build was live stays wedged: clearing
  the timeline cache does not unstick it, only removing and re-adding does.
