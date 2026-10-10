# Verification: spotlight-shell

Run 2026-10-10 on the `build.noindex` Release build (hardened runtime, Apple
Development identity), driven with synthesized key events and the
accessibility tree. The installed v1.48 was quit for each run and restored
afterwards from a copy of `settings.json` and the saved window frame.

## Automated
`DeckSharedTests`: 1474 tests, 0 failures. New: query parsing, matching and
ranking, the four providers, the engine, `SpotlightSettings` (including "an old
`settings.json` with no `spotlight` key keeps everything else"), the lifecycle
policy, shortcut display, and login-item state mapping.

Phases 1 and 2 and the pure parts of 4 were written test-first (red run, then
green). The providers' ClockBox expectations were checked against the real
curated list.

## Measured on the running app
| Check | Result |
|---|---|
| Hotkey under hardened runtime, no entitlement | registers, fires, no prompt (probe.md) |
| Option-Space opens the panel | yes; the previous app stays frontmost |
| Type "tokyo", Enter | pasteboard becomes Tokyo's local time (08:04), panel closes |
| Esc | closes the panel, including with an empty field (fixed: `cancelOperation`) |
| Tray icon | the Deck "D" mark (monochrome template cut from `docs/deck.svg`, 36px at 18pt); confirmed in a screenshot of the real menu bar, tinted like the system icons |
| Tray menu | Search, Settings…, Quit Deck; Search shows the live shortcut ("⌥ Space"), checked in a screenshot of the open menu and via accessibility; it follows a re-recorded shortcut (Ctrl-Option-K) |
| Tray Quit Deck | process exits |
| Tray-only on, window closed | app becomes `UIElement` (no Dock icon), shortcut still works |
| Tray Settings… with Dock icon hidden | window returns, app becomes `Foreground` |
| Recorder: press Ctrl-Option-K | saved as key 40 / modifiers 6144; Option-Space stops, Ctrl-Option-K starts, no relaunch |
| Recorder armed, then Esc | shortcut released while armed, restored after |
| Spotlight tab shows an example search per source (`clip invoice`, `port 3000`, `time tokyo`, `oc refactor`) with what it finds and what Enter does | confirmed in a screenshot and the accessibility text; a test pins that each example scopes to its own source |
| General has Menu bar, Spotlight has the shortcut and sources | confirmed from on-screen text |
| Launch to usable shortcut | ~7s before, **1.5-2.3s** after GitBox/DevBox moved off the main actor |

## Quit behaviour (installed copy, tray-only on)
| Action | Result |
|---|---|
| Dock-style Quit (AppleScript `quit`, the same event the Dock menu sends) | process stays, tray stays, Dock icon goes, shortcut still opens the panel |
| Cmd-Q with the settings window open | process stays, tray stays, Dock icon goes |
| Tray → Quit Deck | process exits |
| Tray-only **off**, Dock-style Quit | process exits |

The real Dock menu was not clicked: AppleScript `quit` stands in for it. A
system logout was not exercised either; it is recognised by the quit event's
reason attribute.

## Found and fixed here
- Quitting from the Dock with tray-only on took the tray down too. The approved
  rule had said it should (see prd.md); it contradicted the feature. Found by
  the user while using the installed build.
- `OpenCodeReader.load()` ran on the main actor against a 5 GB database: ~10s
  launch freeze. Now detached.
- `HostGitBoxSampler` (~2.5s of `git log`) and `HostDevBoxSampler` also ran on
  the main actor. Now detached, with a per-source in-flight guard.
- Esc did nothing on an empty field.
- Carbon reports a shortcut conflict only inside one process (see CLAUDE.md);
  the settings copy no longer claims to detect another app.

## Not verified (needs a human at the screen, or the installed copy)
- **Open Deck at login.** `SMAppService.mainApp` registers only from an approved
  location. Install to `/Applications`, then: toggle on, check Login Items,
  switch it off there, reopen General and confirm the note appears; remember
  that replacing the bundle resets a veto.
- A widget URL click: Deck not running (should open the page and quit) and Deck
  running (should open the page and stay).
- Click-away dismissal with a real mouse (Esc and app-switching were tried).
- Clicking the tray-only switch itself (the behaviour was verified through
  `settings.json`).
- Over a full-screen app and on another Space: reported working from a Finder
  launch of the probe, not re-run against the real panel.
- Recording a shortcut another app already holds: macOS gives no signal.

## Not reproduced
Once, the settings window was created off-screen and neither launch nor tray
Settings… showed it for over a minute; a saved frame on a disconnected display
was the suspect. A later run with the same frame came up on screen in about a
second, with and without a recentering fix, so the fix was discarded unshipped.
The first occurrence also coincided with the launch freeze above.

## Testing traps
- `System Events keystroke` activates the target and moves focus, which
  dismisses a non-activating panel. Post raw key events from a process that
  does not activate.
- The first key-event helper activated itself and read as "the panel never
  opens". A positive control (the probe's own self-test) located the fault.
- Dev and installed copies share one container and one `settings.json`: quit
  the installed Deck first and restore the file afterwards.
