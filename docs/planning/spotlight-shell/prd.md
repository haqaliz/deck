# PRD: spotlight-shell (ROADMAP M10, first item)

## Ask
Deck becomes a resident tray app. A global shortcut opens a floating
Spotlight-style panel that searches local data and groups results by section.
Later M10 items (TaskBox, PRBox, GitBox/CalBox, ShipBox/MarketBox) plug in as
providers; this slice ships the shell plus four local providers and **no
network code**.

## User-visible spec
**Tray icon** (`NSStatusItem`, owned by the app delegate, not `MenuBarExtra`):
menu items Search, Settings, Quit.

**Panel**: floating non-activating `NSPanel`, centered on the active screen,
one text field, results grouped by section, arrow keys + Enter, Esc dismisses,
click-away dismisses. Empty query shows nothing (no browse mode).

**Prefixes** narrow to one provider: `clip `, `port `, `time `, `oc `. No
prefix queries every enabled provider.

**Providers (all local):**
| Provider | Searches | Enter does |
|---|---|---|
| ClipBox (opt-in, off) | clip text/preview/file path | copy back to pasteboard |
| DevBox | port, process/command, container name, image | copy port / container name |
| ClockBox | city -> time, relative day, offset | copy the local time |
| OpenBox | recent session titles from the snapshot | copy the title |

**Settings: new sidebar item "Spotlight" beside General.** Controls (defaults):
- Shortcut recorder (default ⌥Space)
- Keep Deck in the tray only (off)
- Open Deck at login (off)
- Per-provider toggles: ClipBox (off), DevBox, ClockBox, OpenBox (on)

## Data source
Snapshots already in the container (`clipbox.json`, `devbox.json`,
`opencode.json`) read at query time; ClockBox is pure `TimeZone`/`Date`. No new
fetches, no new agent work. Missing snapshot = that provider yields nothing and
its section is omitted (never an error row).

## Shell fit
- New: `SearchProvider` protocol + pure matching/ranking in `Shared/` (unit
  tested), panel + hotkey + tray in `DeckApp/`, `SpotlightSettings` in
  `DeckSettings` (tolerant `decodeIfPresent`, plus a top-level section).
- Touches the app lifecycle, the one place CLAUDE.md lists many traps:
  1. Refreshes/timers/settings `@State` live in `ContentView`; the panel reads
     settings and snapshots itself and does not duplicate the refresh loop.
  2. `DeckAppDelegate` terminates after a URL-only cold launch; a resident or
     tray-mode Deck must not (decision below).
  3. Keep the `LegacyAgentCleanup` guard; add no new caller of `legacyCleanup()`.
  4. Result URLs, if any, go through `DeckLink.webURL`.
  5. "Open Deck at login" is a third SMAppService registration
     (`SMAppService.mainApp`); BTM traps apply (replacing the bundle resets the
     veto; `.requiresApproval` is the user-off state, not `.notRegistered`).
- Widgets and snapshots are untouched, so no widget version bump is needed.

## Non-goals
Network providers, any-age search, secondary result actions, browse mode,
search history/frecency, a separate helper binary, `MenuBarExtra`, searching
NetBox/BatBox/LiveBox/WeatherBox.

## Decisions from critique (approved 2026-10-10)
- Cold URL launch: a freshly launched Deck still quits after forwarding a
  widget URL; only an already-running Deck is exempt. Quitting from the tray is
  an explicit exit.
- Only the tray Quit, Cmd-Q from the settings window and the Dock Quit
  terminate; closing the window does not (tray-only mode).
- The accessory (no Dock icon) policy applies only after the status item
  exists; tray-only refuses to enable until then.
- A shortcut registration failure is shown in the Spotlight settings tab.
- "No results" is a visible state; a provider with no snapshot omits its
  section. OpenBox is recent sessions only, and the copy says so.

## Gating probe (red)
Carbon `RegisterEventHotKey` + non-activating key `NSPanel` over a full-screen
app, on a signed hardened-runtime build: no entitlement, no new permission
prompt. Unproven until measured; if it fails, an `NSEvent` global monitor needs
Accessibility and this PRD must be revisited before any further work.
