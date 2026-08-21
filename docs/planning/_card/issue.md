# CalBox — inline brief (source: ROADMAP.md M5)

Type: feat | Slug: calbox

- [ ] **CalBox** — calendar: next event + countdown, today's agenda.
      Target is **Google Calendar**. Three routes, to be settled in the PRD:
      1. **EventKit** — reads whatever macOS Calendar syncs (Google via
         Internet Accounts, plus iCloud/Exchange/CalDAV) with one TCC grant
         and no OAuth. *Verified caveat: `~/Library/Calendars/` is empty on
         the dev machine — no account is configured today, so this route
         renders nothing until the user adds their Google account to
         System Settings → Internet Accounts.*
      2. **Secret ICS URL** — Google's private iCal address, agent-fetched
         over HTTP exactly like HomeBox/wttr.in. No OAuth, no TCC; read-only
         and Google caches it (freshness measured in hours). The URL is a
         bearer secret and must be stored like the ShipBox token.
      3. **Google Calendar API (OAuth)** — freshest and richest, but the
         first OAuth flow in the repo: PKCE, browser round-trip, refresh
         token in the Keychain. Heaviest; a later slice unless the PRD
         proves 1 and 2 both fail.
      Shell caveat (verified): `DeckAgent` is `type: tool` with **no
      Info.plist** (project.yml), so an EventKit TCC prompt needs an
      embedded `__TEXT,__info_plist` section (a project.yml change) or the
      read must move to DeckApp / the widget extension.

---

## Phase 2 — verified understanding (2026-08-22)

### ROADMAP CORRECTION

The roadmap's "verified caveat" for route 1 is **wrong**. An EventKit probe on
this machine (`requestFullAccessToEvents` from a signed CLI) returned:

```
granted: true      calendars: 11      events next 7d: 61
  [Google] aliz@foresightanalytics.ca        [Google] Holidays in Canada
  [Google] Holidays in Iran                  [iCloud] Work / Home / Calendar / Family
  [AOL] Ali Alizade / Apple Event            [Subscribed Calendars] US Holidays
  [Other] Birthdays
```

`~/Library/Calendars` reports "Operation not permitted" — a TCC denial to the
probing shell, *not* an empty directory. That denial was misread as "no account
configured". Google Calendar is already synced via Internet Accounts today.

### Decisions taken (user, 2026-08-22)

1. **Route: EventKit.** Covers Google + iCloud + AOL + subscribed + birthdays
   with one TCC grant, no OAuth, no secret bearer URL, minutes-fresh.
   Routes 2 (secret ICS) and 3 (OAuth) are not pursued.
2. **Calendar selection: picker with sensible defaults.** All calendars listed
   in the settings tab; real calendars default ON, Holidays / Birthdays /
   Subscribed default OFF so they cannot dominate the countdown.
3. **Faces: countdown + today's agenda.** Small = next event + live countdown;
   medium = countdown + next 3–4 events; large = rest of today + tomorrow's
   first few. All-day events on a separate pinned row, never the countdown.

### Shell blocker (verified)

`DeckAgent` is `type: tool` in `native/project.yml` with **no Info.plist**, so
it cannot declare `NSCalendarsFullAccessUsageDescription` and the TCC prompt
would fail. Fix: `CREATE_INFOPLIST_SECTION_IN_BINARY: YES` + `INFOPLIST_FILE`
on the DeckAgent target (embedded `__TEXT,__info_plist`). Precedent: DeckAgent
already raises the "access data from other apps" prompt for its `ps` read, so a
TCC prompt from the LaunchAgent does reach the user.

### Affected files

| Concern | File |
|---|---|
| Snapshot + pure formatters/agenda logic | `native/Shared/CalBoxSnapshot.swift` (new; pattern: `ShipBoxSnapshot.swift`) |
| Host sampler (EventKit read) | same file, `HostCalendarLoader` (host/agent only) |
| Sampling cadence | `native/DeckAgent/main.swift` |
| Failure reasons | `native/Shared/FetchStatus.swift` — new `FetchSource.calbox` + copy |
| Settings | `native/Shared/DeckSettings.swift` (`CalBoxSettings`, tolerant decode) |
| Settings tab + calendar list | `native/DeckApp/DeckApp.swift` |
| Face | `native/DeckWidgets/CalBoxWidget.swift` (new) |
| Registration | `native/DeckWidgets/DeckWidgets.swift`, `README.md`, `ROADMAP.md` |
| TCC plumbing | `native/project.yml` (+ `native/DeckAgent/Info.plist`) |
| Tests | `native/SharedTests/` — agenda selection, countdown formatting, all-day partition |

### Open questions for the PRD

- Does `FetchOutcome` need a fifth case for "calendar access denied", or does
  `.authOrTarget` carry it with CalBox-specific copy? (Prefer the latter — no
  schema change, and the copy layer already varies per source.)
- Countdown liveness: the snapshot is 60s-old, but the countdown must tick.
  LiveBox re-samples on a `TimelineView` tick; CalBox can compute the countdown
  from the snapshot's event start date against `TimelineView`'s current date —
  no re-read needed, and it stays correct between agent runs.
- Horizon: how far ahead does the agent sample (today only? +48h so "tomorrow's
  first few" on the large face works, and so a late-evening next-event is not
  blank)?
- Snapshot `Equatable` + the agent's "skipped (unchanged)" write-avoidance: an
  agenda that only shifts by elapsed time must not churn the file every tick.
