# Understanding — spotlight-shell-checks

## What the work is really asking

Close the **verification debt** on the Search shell (shipped v1.49), not add a
feature. The shell's *logic* is already pure and unit-pinned; what was never
done is running its five **lifecycle checks against the installed app**
(`ROADMAP.md:1110-1114`, `docs/planning/spotlight-shell/verification.md:60-72`).
The work is: drive each check where a harness can, hand back a precise manual
checklist where a human is required, and fix whatever breaks. If nothing breaks
— a real and acceptable outcome — the deliverable is evidence, not code.

## What is already covered (do not re-test; do not rewrite)

The lifecycle decisions are pure functions with tests, so the *rules* are not in
question — only that the delegate **wires them as intended at runtime**.

- `Shared/TrayLifecyclePolicy.swift` — `shouldTerminate(reason:keepInTrayOnly:trayReady:)`,
  `activationPolicy(...)`, `canEnableTrayOnly`, `quitsAfterForwardingURL(alreadyRunning:)`.
  Pinned by `SharedTests/TrayLifecyclePolicyTests.swift` (every quit reason,
  tray-only, no-tray, cold vs running URL launch).
- `LoginItemState` raw-value mapping (`SpotlightShortcut.swift:75-109`) is pinned
  by `SpotlightShortcutTests.swift:82-112` (off 0 / on 1 / needsApproval 2 /
  notFound 3), including `.needsApproval` wording.
- `ShortcutRegistrationCopy` (the "-9878 only means a same-process duplicate"
  honesty) is pinned (`ShortcutRegistrationCopyTests`).

So a "failure" here is almost never a wrong rule; it is the delegate mapping the
wrong `QuitReason`, or the OS doing something the rule never saw.

## Where the runtime wiring lives

| Concern | Site |
|---|---|
| URL delivery → forward → maybe quit | `DeckApp.swift:58-74` (`application(_:open:)`), `:76-86` (`applicationDidFinishLaunching`), `TrayLifecyclePolicy.quitsAfterForwardingURL` |
| Quit classification | `DeckApp.swift:109-131` (`applicationShouldTerminate`, `isSystemQuit()` reading `kAEQuitReason`); `.settingsCmdQ` exists in the enum but **nothing on the real app sets it** — Cmd-Q and Dock Quit both map to `.dockQuit` (policy treats them identically) |
| Dock icon / accessory policy | `DeckApp.swift:183-193` (`applyDockPolicy`) |
| Tray + Quit item | `TrayController.swift` |
| Panel, click-away (`resignKey`), Esc (`cancelOperation`) | `SpotlightPanel.swift:9-29`, controller `:264-346` |
| Hotkey | `SpotlightHotKey.swift` |
| "Open Deck at login" | `MenuBarSettingsSection` (`SpotlightSettingsView.swift:241-279`) + `MainAppLoginItem.swift` (`SMAppService.mainApp`) |

## The five checks, decomposed by what can actually drive them

1. **Open Deck at login.** `SMAppService.mainApp` registers **only from an
   approved location** (`/Applications`), so this is an installed-copy check.
   *Scriptable:* toggle via `MainAppLoginItem.set` (or the UI), read
   `LoginItemState` raw status back. *Not scriptable:* the Login Items **row**,
   the **veto** (`.requiresApproval`) and the in-app note — `sfltool dumpbtm`
   prompts for an admin password and blocks, so BTM inspection is a human step.
   Test trap already recorded: **replacing the bundle resets the veto**, so
   install → toggle → (veto in System Settings) → relaunch.
2. **Widget-URL click, Deck running and stopped.** There is **no
   `CFBundleURLTypes`** and there must not be (CLAUDE.md trap), so the delivery
   path is the app delegate's `application(_:open:)`. Stand-in for a widget
   click: `open -a /Applications/Deck.app "<url>"` — LaunchServices sends the
   same open-URL event. *Scriptable end-to-end:* `pgrep` before/after + whether a
   browser opened. **Two things to observe beyond the policy:** no **extra
   settings window** appears (the `.handlesExternalEvents(matching: [])` trap,
   `DeckApp.swift:27`), and a *stopped* Deck that forwards quits **without
   leaving a window**.
3. **Click-away dismissal, real mouse.** Mechanism is `resignKey()` →
   `onResignKey` → `hide()` (`SpotlightPanel.swift:23-28,285`). A synthesized
   `CGEvent` mouse click outside the panel *may* drive it, but this is exactly
   the "needs a real mouse" gap; treat a synthesized click as a bonus and keep a
   human line for it.
4. **Panel over a full-screen app / another Space.** `collectionBehavior =
   [.canJoinAllSpaces, .fullScreenAuxiliary]`, `.floating` level
   (`SpotlightPanel.swift:277-279`). Phase 0 proved it for the *probe*, not the
   real panel (`verification.md:70-71`). Needs a full-screen app present to test
   against — semi-automatable, human-confirmed.
5. **The Dock menu's own Quit.** Only an AppleScript `quit` has been run; the
   real Dock menu was never clicked. The substantive risk: `isSystemQuit()`
   reads `kAEQuitReason`, and if a real Dock Quit carried that attribute it would
   be misread as `.system` → always terminate, breaking tray-only. AppleScript
   `quit` is believed to be the same Apple event, but that is the unproven half.

Also outstanding but **not reproducible** (`ROADMAP.md:1113-1114`): the settings
window once failed to show; an examples page once opened without a click.
Recommend **out of scope** — nothing to plan against.

## Shell invariants checked (CLAUDE.md)

- **`.handlesExternalEvents(matching: [])` must stay** — otherwise a URL open
  manufactures a settings window (check 2 observes this). ✅ unchanged by this task.
- **`LegacyAgentCleanup` guard must stay** — a launch must never boot out the
  running agents. Every check here launches/relaunches Deck, so this is a live
  risk: confirm `processes.json` / `agent-heartbeat.json` mtimes keep advancing
  across a quit/relaunch during the run.
- **`System Events keystroke` is the wrong tool** — any harness posts **raw
  `CGEvent`s from a non-activating process**, and proves itself first against a
  known-good receiver. `docs/planning/spotlight-shell/probe/main.swift` is the
  existing (throwaway) raw-`CGEvent` precedent.
- **No widget-extension code touched** — `grep -rn "\.enabled\|serverURL"
  native/DeckWidgets/` must stay clean.

## Build / test facts for the plan

- Repo is **xcodegen + xcodebuild**, not SwiftPM. Any new `.swift` file (harness
  under a target, or a test) needs `xcodegen generate --spec native/project.yml`
  or it is silently not compiled and the suite still passes.
- Test command: `xcodebuild test -project native/Deck.xcodeproj -scheme
  DeckSharedTests -derivedDataPath native/build.noindex CODE_SIGNING_ALLOWED=NO`.
- Build only into `native/build.noindex`; `scripts/lsclean.sh` after a release
  build; install only by replacing the bundle in `/Applications`.
- Quit a running Deck (`pgrep -lf "MacOS/Deck$"`) before anything that reads or
  writes `settings.json` — the app overwrites the file from memory.
- Current test count is **1665** (`credentials-legacy-fallback`, 2026-10-12).

## Open questions for the PRD interview

1. **Deliverable shape.** (A) evidence-only: run the checks, write
   `verification.md`, fix nothing that passes; (B) build a **committed** reusable
   probe harness under `docs/planning/spotlight-shell-checks/probe/` (like the
   shell's) *plus* fixes; (C) a script the maintainer re-runs. Recommendation:
   (B) but **only for the checks a harness can genuinely drive** (URL forwarding
   both ways, and panel visibility/hotkey), with a crisp manual checklist for
   the login-item UI, click-away, full-screen and the real Dock menu.
2. **Does anything in `DeckApp/` change?** Only if a check fails. If it does,
   the fix goes through TDD: any new pure rule → `Shared/`, pinned in
   `DeckSharedTests`; the delegate keeps applying.
3. **The two oddities** — confirm out of scope (not reproducible).
4. **Where does the harness live** — a throwaway under `docs/planning/…/probe/`
   (precedent) or a `scripts/` helper? Precedent favours the planning folder.
5. **Definition of done** — every one of the five checks is either *measured with
   a recorded command/result* or *explicitly handed back as a human step*, with
   `verification.md` updated; no check left unclassified.
