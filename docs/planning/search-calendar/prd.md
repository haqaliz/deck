# PRD — search-calendar

Status: draft (Phase 3). Slug: `search-calendar`. Type: `task`.

## Restate the ask

Enable Deck's calendar **Search** source and verify its live EventKit read against
a real calendar — the one Search data path never exercised — and fix the one
problem the dig already exposes: today the macOS access prompt can only fire from
the non-activating panel, so it should move to the Settings toggle that turns the
source on.

## Background (what already exists)

The source is built end-to-end and its pure logic is pinned by tests
(`EventSearchTests`): matching over title/location/notes/calendar, ranking,
nearest-first tie-break, subtitle, all-day, the meeting-link action, the unsafe
link guard, the cap and the window; plus the four `EKAuthorizationStatus`
mappings. It is off by default (`DeckSettings.swift:724`) because event titles
would show in a panel that can be on screen while sharing.

What is unexercised (`spotlight-more-sources/verification.md:49-53`): the **live
EventKit read** (`HostEventSearch.events`, `EventSearch.swift:94`), the **access
prompt**, and the **meeting-link action** end to end.

## The problem this must fix

The toggle lives in Settings, but nothing there requests calendar access — unlike
the CalBox tab, which prompts in context (`DeckApp.swift:2806-2817`). Access is
instead requested lazily by the source itself (`EventSearch.swift:104-106`) the
first time a query reaches it. Two consequences:

1. `.event` has no required prefix (`SpotlightCore.swift:46-53`), so the prompt
   fires as a **side effect of typing an ordinary ≥2-character query**.
2. The panel is a `.nonactivatingPanel` and never activates Deck
   (`SpotlightPanel.swift:275-276,324`), so the prompt is raised by an app that is
   **not frontmost**.

Deck's own convention is to ask in context, from the active settings window
(`DeckApp.swift:2806`, "this is the in-context place to ask"). The fix is to
follow it.

## User-visible spec

**Settings → Search → Calendar events** (the row already exists,
`SpotlightSettingsView.swift:112,132-133`):

- The toggle still defaults **off**.
- When the user switches it **on**, if macOS has never been asked, Deck requests
  access **there and then**, from the active settings window — one system prompt,
  in context, attributable to a frontmost Deck.
- The row's note copy is corrected to match: macOS asks **when you turn this on**
  (it currently says "the first time", which describes the old path).
- Switching it **on** when access is already granted (the common case, because
  CalBox has usually prompted) requests nothing and shows nothing.
- No grant-state line is added (decision: static copy only).

**The Search panel** changes only in that it **never prompts**:

- With access granted, a matching query shows the **CALENDAR** section with real
  events; Enter opens the meeting link (via `CalendarLink`) or copies the title;
  Cmd-Return copies.
- With access denied or never granted, the section shows the existing one-line
  reason ("Deck can't read your calendars. Allow it in System Settings →
  Privacy → Calendars.", `RemoteSearchPolicy.swift:146`) and nothing else — no
  prompt, no crash.

## Data source

EventKit, in the **host app** (`HostEventSearch.events`), over a year either side
of now, limited to the calendars CalBox reads (`CalendarDefaults.resolve` reuses
CalBox's selection so search and widget agree). Local: nothing leaves the Mac.
Off by default. No new fetch, no agent change.

- Delegated off the main actor via `Task.detached` (`EventSearch.swift:110`), as
  today.
- Unavailable/unreadable → `SearchSourceFailure(.calendarAccess)` → the section's
  one-line reason. Nothing else changes.

## Shell fit

- Reuses the deferred-source shell (`AsyncSearchSource`/`SourceRunner`) and the
  panel unchanged; no new source, no new provider id.
- The only behaviour change is **where the access prompt is raised**: from
  `HostEventSearch.events` (remove the `shouldPrompt` branch) to the Settings
  toggle (one `requestAccess()` on an off→on transition).
- `CalendarAccess.shouldPrompt` stays; it is what the Settings side now consults.
- No prompt on the tab's `onAppear`: access is only ever requested by the act of
  enabling the source, so a re-visit never re-asks. (The only way the source is
  on without a resolved status is a hand-edited `settings.json`, which the docs
  already treat as an unsupported seam — `CLAUDE.md`.)
- No deviation from the panel invariants.

## Non-goals

- No new prefix requirement. `.event` stays prefix-free (decision), reasoned as
  "calendar never leaves the Mac". The per-query read cost is **measured** in
  verification, not bounded by a prefix.
- No grant-state line on the row (decision: static copy only).
- No default-on. No change to the failure message's wording unless the live run
  proves it wrong.
- No calendar write, no event creation, no CalBox widget change.

## Panel invariants to respect (CLAUDE.md)

- `grep -rn "HostEventSearch" native/DeckAgent native/DeckWidgets` must stay
  empty: calendar **search** is a panel source; the widget reads its snapshot.
- Only full access (raw `3`) reads; write-only (`4`) is a denial; never pass an
  empty `calendars:` array to `predicateForEvents`.
- The grant belongs to **Deck.app**, separate from DeckAgent's; both carry the
  usage-description key in `project.yml`.
- `xcodegen generate` after adding any new source file.

## Verification (what "done" claims, and what it does not)

Observable here and recorded in `verification.md`:

- The toggle-on prompt fires **once, from Settings**, and grants.
- A live query returns real events; Enter opens a meeting link; Enter with no
  link copies the title; Cmd-Return copies.
- The denied/undetermined path shows the one-line reason and never prompts.
- The read cost of a broad query is measured.
- `DeckSharedTests` green, 0 failures; the grep invariant empty.

Explicitly bounded: driving the panel needs a human at the screen (no computer-
use tooling), so the panel steps are executed by the user and recorded, not
automated. The unit suite cannot exercise the live read (the test runner has no
calendar grant), so `HostEventSearch.events`'s live behaviour is claimed only
from a real Deck.app run.

## Open questions

None outstanding — the three forks (scope, prefix, grant-state) were answered
during the interview: verify **plus** the in-context prompt fix; keep the source
prefix-free; static copy only.

## Self-critique (Phase 4, deck-prd critique mode)

**🔴 Red — none.** No shell invariant is broken: the deferred-source shell, the
panel, the snapshot path and the host/agent split are all unchanged; the only
edit is *where* one prompt is raised. The data source is real, local and already
used by CalBox.

**🟡 Amber, and the fixes taken:**

1. **A prompt on the tab's `onAppear` was over-reach.** It would re-ask whenever
   the user re-visited Settings → Search without having decided, and it is not
   needed: the toggle is the only way to enable the source, so every real
   `eventEnabled == true` already passed through the toggle. **Cut** (PRD now
   prompts on the off→on transition only).
2. **A side effect in a SwiftUI `Binding` setter is a smell.** It is the smallest
   change that keeps the request where the intent happens, but it must be a
   guarded, fire-and-forget call (check status first, then `Task { await
   requestAccess() }`) so a re-render cannot re-prompt. Named here so the plan
   pins it with a test on the *pure decision*, not the view.
3. **The panel's failure message does not distinguish "denied" from "never
   asked".** After the fix the common panel-reachable case is *denied*, for which
   the existing line ("Allow it in System Settings → Privacy → Calendars") is
   exactly right; the never-asked case is reachable only via the unsupported
   hand-edit. **Keep the single line** (a section may not grow), and record the
   choice.
4. **Prefix-free means a full two-year read per distinct query.** This is the
   user's decision, not a defect — but it is the one number that could change the
   verdict, so verification **measures** the broad-query read cost rather than
   assuming it is fine.

**Gap deliberately left to verification, not the PRD:** whether the live read
returns anything at all, and whether a real meeting link opens. Those are the
things the unit suite structurally cannot answer (no grant under the test
runner); the PRD claims them only from a real Deck.app run, and `verification.md`
is where the claim is earned or withdrawn.

