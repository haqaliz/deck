# spotlight-shell-checks (inline brief)

Source: `dbf task spotlight-shell-checks`, handed off by `deck-next` (2026-10-12).

## Brief

Close out the M10 Search (Spotlight) shell verification debt left by v1.49.
The shell shipped, but its lifecycle checks were never run:

- **Open Deck at login** — the General toggle (`SMAppService.mainApp`), the
  Login Items row, and the veto note.
- **A widget-URL click** with Deck **running** and **stopped** (it should open
  the page and stay / open and quit).
- **Click-away dismissal** with a real mouse.
- **The panel over a full-screen app** and on another Space.
- **The Dock menu's own Quit** (only an AppleScript `quit` stands in for it).

Either build a small reusable key-event probe harness (raw `CGEvent`s from a
**non-activating** helper, never `System Events keystroke`) and drive the checks
with it, or — where a human is genuinely required — hand back a precise manual
checklist. Fix whatever the checks reveal.

Watch the two documented lifecycle traps while doing it:

- `DeckAppDelegate` terminates after a widget-URL launch, which must **not** fire
  for a resident Deck (`docs/planning/spotlight-shell/prd.md`).
- Deck must keep the `LegacyAgentCleanup` guard (a launch must never boot out the
  running agents; `CLAUDE.md`).

## Why this and not something else

- The M10 follow-up list is explicit (`ROADMAP.md:1110-1114`) and matches the
  "Not verified (needs a human at the screen, or the installed copy)" section of
  `docs/planning/spotlight-shell/verification.md:60-72`.
- This pass has already caught real bugs — the Dock-quit-takes-the-tray-down
  bug and the empty-field Esc bug (`verification.md:48-58`).
- Unblocked and testable with no external dependency, unlike M9 (gated on the
  not-yet-bought Apple Developer Program) and M8's remaining locked-keychain
  item (needs a scratch account).

## Caveat (from the recommender)

The checks need a human at the screen and the installed `/Applications` copy.
The tray lifecycle resists naive automation: `System Events keystroke` activates
the target and dismisses the non-activating panel, so any harness must post raw
`CGEvent`s from a process that does not activate — and prove the harness first
against a known-good receiver (`CLAUDE.md` trap). The buildable form is a probe
harness plus fixes for whatever breaks; anything the harness cannot drive is
owed back as a manual checklist.
