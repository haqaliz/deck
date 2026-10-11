# Brief: spotlight-shell (ROADMAP M10, first item)

Add a Spotlight-style search shell to Deck.

- Deck.app stays resident as an `NSStatusItem` tray icon with menu items
  Search, Settings, Quit (not `MenuBarExtra`).
- A global shortcut, set with a recorder, opens a floating non-activating
  `NSPanel`.
- A new settings item beside General holds the shortcut and a "keep Deck in
  the tray only" toggle. With it on, closing the window or quitting from the
  Dock leaves the tray running.
- The panel fans out to local `SearchProvider`s and shows results grouped by
  section, with prefix scoping (`clip `, etc.). Providers in this slice:
  ClipBox (opt-in), DevBox, ClockBox, OpenBox sessions. No network code.
- Anything a result opens goes through `DeckURLForwarding`.

Caveats to design around:
- Timers, refreshes and the settings `@State` live in `ContentView`, so a
  window-less tray Deck needs its own settings read and loop.
- `DeckAppDelegate` terminates after a widget-URL launch; that must not fire
  for a resident Deck.
- Keep the `LegacyAgentCleanup` guard.
- Probe the hotkey API and the `NSStatusItem` + `NSPanel` combination under
  hardened runtime before committing to a design.

Later M10 items (TaskBox, PRBox, GitBox/CalBox, ShipBox/MarketBox search) are
out of scope here; they plug into this shell as providers.

Source: discussion on 2026-10-10, recorded in ROADMAP.md M10. No GitHub issue.
