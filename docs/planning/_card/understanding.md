# Understanding: HomeBox (weather + world clock)

## What the work is really asking

A seventh widget in the Deck shell: weather for a user-configured location plus
2–3 world-clock timezone rows. Pending M3 candidate (ROADMAP.md:47). Two halves:

1. **Weather (network)** — wttr.in `?format=j1` JSON: `current_condition[0]`
   (temp_C, FeelsLikeC, weatherCode WW, weatherDesc, humidity, wind), plus the
   3-day `weather[]` forecast (maxtempC/mintempC/weatherDesc per day) for the
   large face.
2. **World clock (local)** — timezone rows computed from `TimeZone` identifiers;
   zero fetch by design (per the brief).

## Shell mapping (grounded in files)

- **Widget template**: GitBoxWidget (agent-pumped snapshot + `available`/stale
  degrade, GitBoxWidget.swift:114-126; store via `DeckSettings.containerDirectory`,
  GitBoxSnapshot.swift:30-48; 5-min staleness window). NetBoxWidget for the
  list-row layout language (colored dot rows, tracked section titles).
- **Agent pump (the fetch home)**: `DeckAgent/main.swift` — add a HomeBox fetch
  that runs every 60s tick alongside gitbox/devbox/clipbox. **Critical finding:
  the widget sandbox has NO network entitlement** (DeckWidgets.entitlements has
  only app-sandbox), so weather HTTP *must* run in the unsandboxed agent, exactly
  like the proven openbox-remote pattern (`RemoteOpenCodeLoader` URLSession
  transport, RemoteOpenCodeLoader.swift:307-336, called from
  DeckAgent/main.swift:16). The deck-next handoff's "fetch inside the widget"
  assumption is wrong — agent-side only, which also dissolves the "verify widget
  timeline fetching" caveat.
- **Settings**: `HomeBoxSettings` struct + tolerant `init(from:)` decode
  (pattern: LiveBoxSettings, DeckSettings.swift:95-107), registered in
  DeckSettings.swift:34-42; tab in DeckApp.swift (DeckWidget enum:217-246 +
  detail switch:36-45 + settings view struct ~line 251+).
- **Registration**: `HomeBoxWidget()` in DeckWidgets.swift bundle; project.yml
  sources are directory-based → regenerate with xcodegen; register in README +
  ROADMAP (blueprint ROADMAP.md:8-21).

## wttr.in contract facts (verified against live j1 payload)

- Every numeric value is a **String** (temp_C "23", weatherCode "113") — parser
  must string→number; tolerate empty/missing.
- `weatherDesc[0].value` has **trailing whitespace** ("Clear ", "Partly Cloudy ") — trim.
- `weatherCode` is the WW code (113 clear, 116 partly cloudy, 176 patchy rain) →
  SF Symbol mapping is pure logic, TDD-able.
- Location via settings text: wttr.in accepts `/City`, `/52.37,4.90`. Empty →
  let wttr.in geolocate (no query). `nearest_area[0]` gives resolved place name.
- `weather[]` is 3 days; hourly rows are `time`-stamped since midnight in local
  time of the location.

## Ambiguities / open questions (for the PRD interview)

1. Units: metric (temp_C) vs imperial toggle, or follow system locale?
2. Large-face forecast: 3-day (maxtemp/mintemp + desc) vs hourly strip?
3. Location UX: free-text city field vs lat/lon vs both; what does "empty"
   mean (auto geolocate) and is auto-geolocate deterministic enough?
4. Timezone editing UX: free-text TimeZone identifiers vs picker of known
   cities; default ["local", "UTC"]; max count?
5. wttr.in attribution footer — include small "wttr.in" credit on large face?
6. Stale window: same 5-min `available` degrade as GitBox, plus last-update
   affordance when snapshot is old (e.g. >30 min)?

## Invariants check (CLAUDE.md)

No panel invariant is touched: new widget file, new snapshot + store in Shared,
new settings struct, new tab, agent append. All existing targets keep their
sources; Shared is already compiled into all three targets.
