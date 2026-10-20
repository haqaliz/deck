# Verification: spotlight-shell-checks

Run 2026-10-13 on the installed **Deck v1.53** (`/Applications/Deck.app`,
Release, hardened runtime, Apple Development identity), quit and relaunched by
the harness. Harness: `probe/main.swift` (compile below). Plan:
`plan_20261012.md`. PRD: `prd.md`.

The shell's *rules* were already unit-pinned (`TrayLifecyclePolicyTests`,
`SpotlightShortcutTests`); this run proves the **delegate wires them at runtime**.

## Build / harness

```bash
xcodegen generate --spec native/project.yml
# Release build, lsclean, install by replacing the bundle only
swiftc -O docs/planning/spotlight-shell-checks/probe/main.swift -o /tmp/deck-probe
/tmp/deck-probe --selftest      # positive control: raw CGEvent reaches a key field
```

`--selftest`: **PASS** — `AXIsProcessTrusted: true`, a posted `a` reached the
field. (First attempt FAILED against a non-activating panel that never became
key; the control was corrected to a normal key window — the mechanism had to be
proved before any panel result was trusted.)

## Results

| # | Check | Method | Result |
|---|---|---|---|
| C2a | Widget-URL click, Deck **stopped** | auto | **PASS** |
| C2b | Widget-URL click, Deck **running** | auto | **PASS** |
| C4 | Panel opens on the shortcut, previous app stays frontmost, Esc dismisses (proxy) | auto | **PASS** |
| — | Agent liveness across a relaunch (`LegacyAgentCleanup` guard) | auto | **PASS** |
| C5a | `quit` with tray-only **ON** is vetoed | auto (AppleScript stand-in) | **PASS** |
| C5b | `quit` with tray-only **OFF** terminates | auto (AppleScript stand-in) | **PASS** |
| C1 | Open Deck at login (toggle / Login Items row / veto note) | **human** | PASS (owner) |
| C3 | Click-away dismissal with a real mouse | **human** | PASS (owner) |
| C4h | Panel visibly over a full-screen app, and on a second Space | **human** | PASS (owner) |
| C5h | The **real Dock menu** → Quit, both tray-only states | **human** | PASS (owner) |
| C2h | A true WidgetKit gallery click (not the `open -a` stand-in) | **human** | PASS (owner) |

No product defect was found. Phase 4 (fixes) is therefore skipped, by design
(a stated, acceptable outcome).

**2026-10-21 — the human half is closed.** The owner ran C1, C3, C4h, C5h and
C2h on the installed v1.57 build; all passed and no defect was filed (#79).
This is an owner attestation, not a recorded run — unlike the automated half
above, there is no log to cite.

## Raw evidence (automated)

**C2a — cold launch.** `pgrep` empty → `open -a /Applications/Deck.app "https://example.com/deck-url-check"`:

```
cold: Deck not running. launching via open -a with a URL…
cold: appeared=true exited=true goneNow=true maxOnScreenWindows=0 webLog=true
  log: [com.deck.app:url] open: received=1 forwarding=1 urls=https://example.com/deck-url-check
cold: PASS (expect forwarded, exited, 0 windows)
```

The log line is the arrival proof (the delegate consumed the URL); the process
started, forwarded, and exited, with **zero** on-screen Deck windows.

**C2b — running.** Deck up, one on-screen window:

```
running: deck up, on-screen windows=1. opening URL…
running: stillUp=true windowsBefore=1 windowsAfter=1 webLog=true
running: PASS (expect forwarded, process persists, no new window)
```

Forwarded, process persists, and the window count is unchanged — the
`handlesExternalEvents(matching: [])` invariant holds (no fabricated window).

**C4 — panel proxy.** Shortcut is **Ctrl+Option+Space**, not the default ⌥Space
(the user re-recorded it; `settings.json` `shortcutKeyCode: 49`,
`shortcutModifiers: 6144`):

```
panel-probe: Deck windows before=[]
panel-probe: frontmost before=Google Chrome
posting hotkey keyCode=49 flags=786432
panel-probe: Deck windows after=["3:640x54"]
panel-probe: added=["3:640x54"]
panel-probe: frontmost after=Google Chrome
panel-probe: appeared=true dismissedAfterEsc=true
panel-probe: PASS (a Deck window appeared on the shortcut)
```

A borderless floating window (layer 3) appeared, the previous app **stayed
frontmost**, and Esc dismissed it.

**Agent liveness.** `pkill` + `open -a` (a real relaunch):

```
agents: baseline processes.json=…21:46:11Z  agent-heartbeat.json=…21:46:13Z
  t+15s: processes=…21:46:31Z  <= advanced
  t+75s: …, heartbeat=…21:47:24Z  <= advanced
agents: PASS (processes.json must advance across a launch)
```

Both witnesses advanced after the relaunch → the launch did **not** boot the
agents out. `launchctl print` corroborated: `com.deck.agent.processes` runs
66965 / exit 0 / 5s, `com.deck.agent` runs 7764 / exit 0 / 60s.

**C5a/C5b — quit semantics (AppleScript `quit` = the Dock Quit Apple event
without a reason attribute).**

- tray-only **ON** → `osascript quit` returned `User canceled (-128)` and the
  process stayed (`applicationShouldTerminate` → `.terminateCancel`).
- tray-only **OFF** → `osascript quit` exited the process.
- State restored to the user's (tray-only ON) afterwards.

## Findings

1. **Product: none.** Every automatable check matched `TrayLifecyclePolicy`;
   no fix was needed.
2. **Shortcut is Ctrl+Option+Space**, not the documented default ⌥Space
   (settings, not code). The harness takes `--shortcut "49,6144"` for this.
3. **`handlesExternalEvents` and the non-activating panel both hold** — no
   fabricated settings window, and Deck never takes focus from the previous app.
4. **Harness trap (for the next probe).** `URL.resourceValues(forKeys:
   [.contentModificationDateKey])` **caches** the value for the life of the
   process: polling one `URL` reported frozen mtimes for files that were
   advancing. Confirmed in isolation — the URL read stayed identical while
   `FileManager.attributesOfItem(atPath:)` reflected the change. Read file
   attributes directly when polling mtimes.
5. **A graceful `quit` is vetoed under tray-only** (returns `-128` to the
   sender). This is the policy working; note it when scripting a quit.

## Handed back — numbered human checklist

Run these on the installed copy. Do them in this order; the login-item veto must
be tested **without** replacing the bundle first (a bundle copy resets it).

1. **C1 — Open Deck at login.** General → Menu bar → *Open Deck at login*:
   toggle it off and on and watch the toggle follow the OS. Open System
   Settings → General → Login Items and confirm a **Deck** row exists. Switch
   that row **off**, then reopen Deck's General tab and confirm the amber note
   *"Turned off in System Settings → General → Login Items. Turn it back on
   there."* appears with the toggle still on. Turn it back on there. Report: row
   present? note shown? toggle state each step?
2. **C3 — Click-away with a real mouse.** Focus another app, press
   Ctrl+Option+Space, then click a window of that other app. The panel should
   dismiss **and** the click should land in that app (Deck never activates).
   Report: dismissed? click received?
3. **C4 — Over a full-screen app.** Put an app full-screen, press the shortcut;
   the panel should draw **above** it and take typing. Repeat on a second Space
   (Ctrl+← / Ctrl+→). Report: visible over full screen? works on the other Space?
4. **C5 — The real Dock menu.** With tray-only **ON** (current), right-click the
   Dock icon → Quit: the window and Dock icon should go, the process, tray and
   shortcut should stay. Then turn tray-only **OFF** in General → Menu bar, and
   right-click Dock → Quit: the process should exit. Report both.
5. **C2h (optional) — A true gallery click.** Add a PRBox widget (or any with a
   link), click one of its rows, and confirm: the browser opens and Deck does not
   sprout a settings window (Deck running) — and, with Deck quit, the browser
   opens and Deck does not linger.

Record the answers against this table; the ROADMAP tick waits on them.
