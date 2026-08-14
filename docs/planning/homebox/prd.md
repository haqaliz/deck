# PRD: HomeBox — weather + world clock

Slug: `homebox` · Type: widget · Source: deck-next handoff + deck-prd interview (2026-08-14)

## Ask

A seventh Deck widget showing current weather for a configured location plus a
few world-clock timezone rows, delivered through the existing agent-pumped
snapshot path.

## User-visible spec

### Front face (all three sizes, Widget Center)

**Small** — at a glance:
1. Location name (resolved by wttr.in, e.g. "De Wallen") — secondary, tracked.
2. Condition icon (SF Symbol from WW weatherCode) + temperature (big, monospaced digits).
3. Feels-like line.
4. Current time (HH:MM) — the local clock row.

**Medium** — small content + timezone rows (city/time label + HH:MM), one
row per configured zone; local row first.

**Large** — medium content + 3-day forecast strip (day label, WW icon,
maxtemp/mintemp) and, when the snapshot is stale, a last-updated hint. Small
"wttr.in" attribution line at the bottom.

**Degrade states** (GitBox pattern, GitBoxWidget.swift:114-126), by snapshot age:
- **< 5 min**: fully fresh — no hint.
- **5–30 min**: stale hint — "· HH:mm" appended to the location row (weather
  data still shown; it is slow-moving by nature).
- **> 30 min**: unavailable view — "No weather data — waiting for Deck agent…".
- No snapshot file / decode failure → unavailable view.

Timezone rows and the local clock always render (zero fetch) even when the
weather section is unavailable.

### Back face (Deck app settings, "HomeBox" tab)

| Control | Default | Notes |
|---|---|---|
| Location (text field) | empty | Free-text city or `lat,lon`; empty → wttr.in auto-locates (IP). |
| Units (picker C/F) | °C | Metric default. |
| Timezones (text field) | `local, UTC` | Comma-separated TimeZone identifiers; `local` = current zone. Invalid entries dropped; max 3 kept; if none valid → zones section hidden. Row label = last identifier path component (e.g. `Europe/Amsterdam` → "Amsterdam"). |
| Show forecast (toggle) | on | Large-face 3-day strip. |
| Show zones (toggle) | on | Timezone rows on medium/large. |

All settings via `HomeBoxSettings` with tolerant `init(from:)` decode
(pattern: LiveBoxSettings, DeckSettings.swift:95-107).

## Data source

- **Weather**: wttr.in `?format=j1` (verified contract 2026-08-14):
  `current_condition[0]` → temp_C/temp_F (strings!), FeelsLikeC/F, weatherCode
  (WW code), weatherDesc[0].value (trim trailing spaces), humidity,
  winddir16Point, windspeedKmph; `nearest_area[0].areaName[0].value` +
  `country[0].value` → resolved place name; `weather[]` (3 days) →
  maxtempC/F, mintempC/F, weatherDesc[0].value. Unknown/empty WW code → generic
  cloud symbol fallback. URL shape: `https://wttr.in/{location}?format=j1`
  (location empty → `https://wttr.in/?format=j1`).
- **Fetch home**: the unsandboxed **DeckAgent** (every 60s tick,
  DeckAgent/main.swift), using the proven `RemoteOpenCodeLoader` URLSession
  transport (RemoteOpenCodeLoader.swift:307-336). **The widget sandbox has no
  network entitlement** (DeckWidgets.entitlements) — widget-side HTTP is
  impossible; agent-side is the only path. Snapshot written to
  `DeckSettings.containerDirectory/weather.json` via a
  `WeatherSnapshotStore` (GitBoxSnapshot.swift:30-48 pattern). **Always write
  after a successful fetch** (ClipBox precedent, DeckAgent/main.swift:40-44) so
  `writtenAt` stays honest; a failed fetch skips the write so the old snapshot
  ages into the stale affordance.
- **World clock**: local-only — `TimeZone` identifiers rendered at entry-build
  time (60s timeline refresh floors at ~1 min, so HH:MM is ≤60s stale).
- **Refresh cadence**: agent every 60s; widget timeline `after(60s)`; staleness
  windows above.
- **Unavailable**: no snapshot file / decode failure / fetch failure → widget
  shows the degrade view. Agent fetch failure just skips the write (old
  snapshot survives → stale affordance).

## Shell fit

Reuses: agent-pump loop (DeckAgent/main.swift:11-47), snapshot+store pattern
(Shared/GitBoxSnapshot.swift), settings struct + tolerant decode
(Shared/DeckSettings.swift), settings tab (DeckApp/DeckApp.swift:217-246 +
detail switch + settings view), widget bundle registration
(DeckWidgets/DeckWidgets.swift), directory-based xcodegen sources (regenerate
project). **No panel invariant touched** (CLAUDE.md conventions).

Net-new: `HomeBoxWidget.swift`, `HomeBoxSnapshot.swift` (Shared, incl.
`HostWeatherLoader` using the URLSession transport + wttr parser), `HomeBoxSettings`,
app tab, README/ROADMAP registration.

## Critique log (deck-prd critique, 2026-08-14)

- 🟡 Fixed: contradictory staleness windows (5 min unavailable vs 30 min stale
  hint) → three clean windows: fresh <5 min, stale hint 5–30 min, unavailable
  >30 min; timezone rows always render even when weather is unavailable.
- 🟡 Fixed: redundant zone count stepper vs free-text list → dropped the
  stepper; the text field is the list (max 3, invalid dropped, none → hidden).
- 🟡 Fixed: agent write semantics → always write on success (ClipBox
  precedent), skip on failure, so `writtenAt` drives staleness honestly.
- 🟡 Fixed: WW code → SF Symbol needs a fallback for unknown/empty codes →
  generic cloud symbol; empty `weatherDesc` tolerated.

## Non-goals

- No hourly forecast strip (weather[] hourly is ignored beyond day aggregates).
- No multi-location weather (one location only).
- No rain/precip probability metrics on the face.
- No network in the widget itself (agent-only, by entitlement).
- No history/chart of weather.

## Open questions

None blocking — interview answered: units = C/F toggle; large face = 3-day
strip; location = free text, empty auto; zones = free-text identifiers,
default local+UTC, cap 3.
