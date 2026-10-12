# PRD: spotlight-shell-checks (ROADMAP M10 follow-up)

Source: `dbf task spotlight-shell-checks`, handed off by `deck-next`
(2026-10-12) from `ROADMAP.md:1110-1114` and
`docs/planning/spotlight-shell/verification.md:60-72`.

## Ask

Close the Search shell's verification debt: run its five unrun lifecycle checks
against the installed v1.53 build, driving each one with a reusable raw-`CGEvent`
harness where it can and a numbered human checklist where it cannot, record the
evidence, and fix whatever the run reveals. **If nothing breaks, the deliverable
is evidence, not code.**

This is a `task`, not a feature: the shell already shipped (v1.49) and its
*logic* is unit-pinned. What was never done is proving the delegate wires that
logic correctly **at runtime**, on a signed build in `/Applications`.

## What is deliberately NOT in scope (already covered)

Re-testing the pure rules is wasted effort — they are pinned and green:

- `TrayLifecyclePolicy` (`Shared/TrayLifecyclePolicy.swift`) — every quit reason,
  tray-only, no-tray, cold-vs-running URL launch
  (`SharedTests/TrayLifecyclePolicyTests.swift`).
- `LoginItemState` raw-value mapping + `.needsApproval` copy
  (`SpotlightShortcut.swift:75-109`, `SpotlightShortcutTests.swift:82-112`).
- `ShortcutRegistrationCopy` (`TrayLifecyclePolicyTests.swift:107-128`).

A failure found here is therefore almost never a wrong rule — it is the delegate
mapping the wrong `QuitReason`, or macOS doing something the rule never saw.

## The five checks

Each is **Auto** (the harness drives and observes it), **Semi** (harness can
assert a proxy, a human confirms the visible result), or **Human** (only a person
at the screen can do it). Every check ends with the same classification question:
*measured with a recorded command/result*, or *handed back as a numbered human
step*.

### C1 — Open Deck at login — **Human** (no external auto half — see critique)

`SMAppService.mainApp` registers **only from an approved location**, so this is an
installed-copy check (`MainAppLoginItem.swift`, `SpotlightSettingsView.swift:241-279`).

- **No external auto half.** `SMAppService.mainApp` is the *calling process's own*
  main-app registration; a standalone CLI/probe is its own app, so it cannot
  read or toggle **Deck's** login item. `sfltool dumpbtm` can, but it prompts for
  an admin password and blocks. So C1 is driven entirely from the settings UI.
- **Human:** toggle *Open Deck at login* in General → Menu bar and confirm the
  toggle reflects the OS (off 0 / on 1 / needsApproval 2 / notFound 3 — the
  mapping is already pinned); a "Deck" row exists in System Settings → General →
  Login Items;
  switching it off there and reopening General shows
  *"Turned off in System Settings → General → Login Items. Turn it back on
  there."* (`.needsApproval` note) with the toggle still on; `.off`/`.on` show no
  note.
- **Trap (recorded):** replacing the bundle resets the veto. Order is
  **install → toggle on → veto in System Settings → relaunch**. Test the veto
  from a build already installed, never a fresh `cp`.

### C2 — Widget-URL click, Deck running and stopped — **Auto**

There is **no `CFBundleURLTypes`** and there must not be (CLAUDE.md trap), so a
widget URL reaches the app through `application(_:open:)`
(`DeckApp.swift:58-86`). Stand-in for a WidgetKit click: `open -a
/Applications/Deck.app "<url>"` (LaunchServices sends the same open-URL event).

**Positive control, required (see critique).** "The browser opened" proves
nothing about *Deck*: if Deck does not claim http, LaunchServices can open the
URL itself. So the harness must first prove the delegate consumed the URL:

- **Cold case is self-proving:** `open -a` launches Deck regardless, and Deck
  only quits after a cold launch if `launchedToOpenAURL` was set — which happens
  **only** when `application(_:open:)` received a usable http(s) URL
  (`DeckApp.swift:66-73,78-84`). *Process started then gone ⇒ the callback
  fired.* If Deck stays running after a cold `open`, the callback did **not**
  fire for a usable URL.
- **Running case needs a diagnostic.** A resident Deck stays running whether or
  not it received the URL, so add **one OSLog line** in `application(_:open:)`
  (`Logger(subsystem: "com.deck.app", category: "url")`) recording the forwarded
  URLs, and read it with `log show --last 2m --info --debug --predicate
  'subsystem == "com.deck.app"'`. (`log show` without `--info --debug` is silent
  for this app — CLAUDE.md — so prove the log answers with a cold case first.)
  This is the smallest host change that makes the run honest; it is a diagnostic,
  not a behaviour change.

- **Stopped:** `pgrep -lf "MacOS/Deck$"` empty → `open -a … "https://example.com/deck-url-check"`
  → assert Deck's process started and quit, the browser opened, and no Deck
  settings window was created.
- **Running:** Deck up (**tray-only OFF**, stated) → same `open` → assert the log
  line fired, the browser opened, the process persists, and no **second** settings
  window appeared (`.handlesExternalEvents(matching: [])`, `DeckApp.swift:27`).
  Deck's window count is observed from outside via `CGWindowListCopyWindowInfo`
  filtered by Deck's PID, not `NSApp.windows` (the harness is another process).
- **Honest limit:** this exercises LaunchServices' open path, which is the same
  delegate callback WidgetKit uses, not WidgetKit's own delivery. Say so in
  `verification.md`; a true gallery click stays a human step.

### C3 — Click-away dismissal, real mouse — **Human**

Mechanism: `SpotlightKeyPanel.resignKey()` → `onResignKey` → `hide()`
(`SpotlightPanel.swift:23-28,285`).

- **Human:** open the panel (⌥Space), then click a *different* app's window with
  the real mouse → the panel dismisses **and the clicked app receives the click**
  (Deck never activates).
- A synthesized `CGEvent` click outside the panel may drive it; if it reliably
  does, record that as a bonus, but the real-mouse line stays.

### C4 — Panel over a full-screen app / another Space — **Semi**

`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `.floating`
level (`SpotlightPanel.swift:277-279`). Phase 0 proved this for the *probe*, never
the real panel (`verification.md:70-71`).

- **Semi:** with a full-screen app frontmost, post ⌥Space; the harness reports
  `panel.isVisible`, `panel.isKeyWindow`, and the frontmost app name/model.
- **Human:** the panel is drawn **above** the full-screen app and takes typing;
  repeat on a second Space.

### C5 — The Dock menu's own Quit — **Human**

Only an AppleScript `quit` has ever been used; the real Dock menu was never
clicked. The substantive risk is `isSystemQuit()`
(`DeckApp.swift:126-131`): it reads `kAEQuitReason`, and if a real Dock Quit
carried that attribute it would be classified `.system` and **always terminate**,
breaking tray-only mode.

- **Human (tray-only OFF):** Dock icon → right-click → Quit → the process exits.
- **Human (tray-only ON):** Dock icon → right-click → Quit → the window and Dock
  icon go, but the process, the tray item and the shortcut stay.
- AppleScript `quit` is an accepted stand-in only if the real menu click is also
  done once, because the two are *believed* identical and that belief is the
  thing under test.
- **Measurable half:** apple-scripted `quit` (no `kAEQuitReason`) has already
  behaved as `.dockQuit`; the harness re-confirms it under both tray-only states
  so the only remaining unknown is whether the **real Dock menu** differs — the
  one human line. Note that Cmd-Q and Dock Quit both map to `.dockQuit` on the
  real app (`DeckApp.swift:112`); the `.settingsCmdQ` enum case is currently set
  by nothing and is therefore not a distinct path to test.

### Cross-cutting — the two lifecycle traps, observed throughout

- **Agent liveness (`LegacyAgentCleanup` guard).** Every check launches and
  relaunches Deck. After each relaunch, `processes.json` and
  `agent-heartbeat.json` mtimes must keep advancing — proof a launch did not boot
  the agents out. An unchanged mtime is the tell (CLAUDE.md).
- **No browser registration.** Confirm Deck declares no http(s)
  `CFBundleURLTypes` after the build (`plutil -p` on the installed Info.plist).

## Deliverables

1. `docs/planning/spotlight-shell-checks/probe/main.swift` — a reusable,
   **committed** raw-`CGEvent` harness: **posts** ⌥Space (and any recorded
   shortcut) rather than registering it (a second process registering Deck's
   combination gets status 0 — CLAUDE.md), automates both C2 URL cases via `open`
   + `pgrep` + the `com.deck.app` log, samples Deck's window count via
   `CGWindowListCopyWindowInfo`, samples the two agent-witness mtimes, and has a
   **`--selftest` positive control** that posts an event to a known-good receiver
   before the panel is trusted (the trap that made the first helper look like "the
   panel never opens"). It must print `AXIsProcessTrusted()` — untrusted posting
   can silently do nothing — and prove the log is answering before its silence is
   read (CLAUDE.md). Precedent: `docs/planning/spotlight-shell/probe/main.swift`.
2. `docs/planning/spotlight-shell-checks/verification.md` — the run: per-check
   pass/fail, the exact command, the raw result.
3. **Fixes, only if a check fails.** Any new pure rule goes in `Shared/`, pinned
   in `DeckSharedTests`; the delegate keeps applying. No speculative refactor.
4. Ticks in `ROADMAP.md:1110-1112` and an update to the *Not verified* section of
   `docs/planning/spotlight-shell/verification.md`, per repo convention.

## Shell fit / invariants (CLAUDE.md)

- **`.handlesExternalEvents(matching: [])` stays** — C2 observes that no extra
  window appears.
- **`LegacyAgentCleanup` guard stays** — proven by the agent-mtime observation.
- **No `CFBundleURLTypes` for http(s)** — C2 and the cross-cutting check.
- **Harness posts raw `CGEvent`s, never `System Events keystroke`** — the
  keystroke tool activates the target and dismisses the non-activating panel.
- **No widget-extension changes:** `grep -rn "\.enabled\|serverURL"
  native/DeckWidgets/` must stay clean.
- Repo is **xcodegen + xcodebuild**; a new `.swift` file needs `xcodegen generate
  --spec native/project.yml` or it silently is not compiled and the suite passes.

## Pass criteria

- Each of C1–C5 is **either** measured with a recorded command/result **or**
  handed back as a numbered human step — none left unclassified.
- The cross-cutting agent-liveness observation is recorded for at least the
  relaunches the run performs.
- If code changed: `xcodebuild test … -scheme DeckSharedTests` green with a
  **non-zero executed count ≥ 1665** (the count rises if a fix adds a test).
- If no code changed: the suite is still run once to confirm green, and that is
  stated.

## Non-goals

- No new Search features, providers, prefixes or result actions.
- No re-testing the pure lifecycle/login/shortcut rules already pinned.
- No attempt to reproduce the two one-off oddities (settings window once not
  shown; examples page once opened without a click) — not reproducible, no
  failure to plan against (interview, 2026-10-12).
- No change to `SMAppService` agent registration (M7's agent-liveness work).
- No change under `native/DeckWidgets/`.
- No app redesign; a fix is a bug fix, not an opportunity.

## Decisions (interview, 2026-10-12)

- **Deliverable:** committed reusable harness + run every automatable check
  against the installed build + precise manual checklist for the human-only
  checks + fixes if broken. (Not evidence-only; not a `scripts/` helper — the
  planning-folder probe is the precedent.)
- **The two oddities are out of scope.**
- **Execution:** build and run the automatable checks now; the human runs C1's
  UI/veto, C3, C4's visible half, and C5's real Dock click and reports back.

## Open questions

None outstanding — the three scope forks were resolved in the interview above.

## Self-critique (2026-10-12)

Pressure-tested before planning. Two gaps were substantive enough to change the
spec above; the rest are recorded so the plan does not walk into them.

🔴 **C2 had no proof the URL ever reached Deck — a false-pass machine.** "The
browser opened" is consistent with LaunchServices opening the URL *directly*
(Deck declares no http scheme), so the original C2 could have "passed" while
`application(_:open:)` never fired. **Fixed:** the cold case is now self-proving
(Deck quits after a cold `open` *only* if `launchedToOpenAURL` was set, i.e. the
callback fired), and the running case requires a **one-line OSLog** in
`application(_:open:)` read back with `log show --info --debug`. → *Review-gate
decision: approve that diagnostic log line, or downgrade C2's running case to a
human gallery click.*

🟡 **C1's "auto" half was impossible.** `SMAppService.mainApp` is scoped to the
*calling* process, so no standalone probe can read or toggle Deck's own login
item; `sfltool dumpbtm` blocks on an admin prompt. **Fixed:** C1 is Human, with
that reason stated, so the plan does not build a probe that cannot work.

🟡 **The harness could silently do nothing.** `CGEvent` posting can be inert
without Accessibility trust, and a helper that keeps `⌥Space` registered would
fight Deck's own registration. **Fixed:** the harness prints
`AXIsProcessTrusted()`, **posts** rather than registers, and proves itself with
`--selftest` against a known-good receiver first.

🟡 **Window-count observation was unspecified.** A second settings window is the
`handlesExternalEvents` symptom, but the harness is a separate process and cannot
read `NSApp.windows`. **Fixed:** observe Deck's windows externally via
`CGWindowListCopyWindowInfo` filtered by PID.

🟡 **"Done" was ambiguous for a human-dependent task.** Pass criteria now say
each check is *measured or handed back as a numbered human step*; the ROADMAP
tick (`ROADMAP.md:1110-1112`) and the final verdict are gated on the human
results for C1's veto, C3, C4's visible half and C5's real Dock click — the agent
does not tick a check it could not observe.

🟡 **C2's running case needed a fixed settings state.** Run it with **tray-only
OFF** and say so; a tray-only Deck responds to reopening differently.

**Not gaps (checked):** no shell invariant is touched (
`.handlesExternalEvents`, `LegacyAgentCleanup`, no `CFBundleURLTypes`, no
`DeckWidgets/` change); the pure rules are already pinned, so no re-test; the two
oddities are out of scope by decision. The `.settingsCmdQ` enum case is set by
nothing on the real app — noted under C5, not a path to plan for.

