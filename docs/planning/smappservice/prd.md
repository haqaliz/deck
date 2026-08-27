# SMAppService — launch agents registered via the Service Management framework

Slug: `smappservice`
Type: feature (M7 launch readiness)
Status: drafted 2026-08-27 (deck-prd interview + dig)

## Restated ask

Replace the hand-written `~/Library/LaunchAgents` plists (written by
`DeckApp/DeckApp.swift:431-494` and bootstrapped with `launchctl bootstrap`)
with `SMAppService.agent(plistName:)` registrations, so Deck's two background
agents (`com.deck.agent` 60s full, `com.deck.agent.processes` fast) appear in
**System Settings → General → Login Items** — the modern, user-auditable
surface (ROADMAP.md:480-481, M7). The agents' behavior is unchanged; the
plists move into the signed app bundle and the OS owns registration.

## User-visible spec

**General tab (Deck settings window), "Background refresh" section:**

- Toggle "Refresh in background (launch at login)" — **unchanged label and
  default (on)**. New behavior: it mirrors the *actual* registration state,
  not just a persisted intent. Resolved in interview: if the user disables the
  agent in System Settings → Login Items, Deck's toggle flips off on the next
  launch and stays off (no re-registration fight). If the user *enables* it
  there, the toggle flips on.
- Caption under the toggle (currently "Runs the Deck agent at login…"):
  point at System Settings → Login Items as the place the agent is listed.
- "Remove background agents" button (Uninstall section): unregisters both
  SMAppService services, then boots out and deletes any legacy
  `~/Library/LaunchAgents/*.plist` leftovers. Caption updated to not say
  "deletes their LaunchAgent files" as the only mechanism.
- "Erase Deck data…" (destructive): unchanged — it calls the same unregister
  path as the button above.

**Nothing else changes for the user.** No widget faces, no settings keys, no
snapshot formats. LiveBox's process refresh interval setting (5–60s stepper,
`DeckApp/DeckApp.swift:799`) keeps its full range.

## Behavior spec (what "registered" means)

### The two agents

| Service | plist in bundle | Launchd schedule | Runs |
|---|---|---|---|
| `com.deck.agent` | `Contents/Library/LaunchAgents/com.deck.agent.plist` | RunAtLoad + StartInterval 60 | `Contents/MacOS/DeckAgent` (full refresh) |
| `com.deck.agent.processes` | `Contents/Library/LaunchAgents/com.deck.agent.processes.plist` | RunAtLoad + StartInterval **5** | `Contents/MacOS/DeckAgent` with `DECK_AGENT_ROLE=processes` env var |

Key choices (all grounded in the dig):

1. **`BundleProgram` instead of `ProgramArguments`.** Per Apple's migration
   guidance ("Updating helper executables from earlier versions of macOS"),
   agents and daemons inside the bundle address their executable **relative to
   the bundle root**: `<key>BundleProgram</key><string>Contents/MacOS/DeckAgent</string>`.
   This is move-proof — the current code hardcodes
   `/Applications/Deck.app/Contents/MacOS/DeckAgent` (`DeckApp/DeckApp.swift:467`),
   which breaks silently if the user relocates the app. The current code only
   self-heals because every settings change rewrites the plist.
2. **The `--processes` argument becomes an environment variable.**
   `BundleProgram` carries no arguments. The fast agent's plist sets
   `<key>EnvironmentVariables</key><dict><key>DECK_AGENT_ROLE</key><string>processes</string></dict>`;
   `DeckAgent/main.swift` accepts the env var **or** the existing `--processes`
   flag (either selects fast mode; manual CLI runs unchanged). Resolved in
   interview.
3. **No `StandardOutPath` / `StandardErrorPath` in the bundle plists.**
   launchd does **not** expand `~` or `$HOME` in those keys (Apple forums
   thread 120784, launchd man pages), and a static, signed plist cannot carry
   the user's per-user absolute path. The agent's diagnostics are already
   OSLog-only — `DeckAgent/main.swift` logs exclusively via
   `Logger(subsystem: "com.deck.agent")` (M4's documented path,
   ROADMAP.md:53-56) — so the file logs were empty in practice. **Behavior
   change (flagged):** the per-tick agent file logs are dropped; diagnostics
   come from the unified log (`log show --predicate 'subsystem ==
   "com.deck.agent"'`). The app still creates `~/Library/Logs/Deck` (0700) at
   launch so the documented layout and the cask/README uninstall cleanup
   (`homebrew/deck.rb:74`, `README.md:377`) stay truthful.
3. **Fixed StartInterval in the sealed plist + agent-side self-throttle.**
   The bundle is signed; the plist cannot be rewritten when the user changes
   `livebox.processRefreshInterval` (5–60s, default 15). The fast plist pins
   the **minimum (5s)** — the setting's full range stays meaningful — and the
   agent samples only when the configured interval has elapsed. Pure policy,
   unit-pinned:
   `ProcessRefreshPolicy.shouldSample(lastSampleAt:configuredInterval:now:)`.
   Resolved in interview. (Known launchd behavior, unchanged from today: the
   process agent's plist already writes 5s StartIntervals today; if launchd
   floors sub-10s ticks, the self-throttle is unaffected for every configured
   interval above the floor.)
4. **Processes snapshot is now always written.** The throttle needs a last-
   sample timestamp; today `sampleProcesses()` skips the write when the list
   is unchanged (`DeckAgent/main.swift:24-32`), so `writtenAt` is the last
   *change* time. Always-write (the clipbox pattern,
   `DeckAgent/main.swift:137-141`) makes `writtenAt` the last sample time and
   fixes a real quirk: on a quiet machine `writtenAt` ages past
   `ProcessSnapshot.maxAgeSeconds(for: interval)` and the LiveBox process rows
   render **empty** (`LiveBoxWidget.swift:81-89`) until the list changes. The
   M4 "single writer" invariant (only the fast agent writes processes.json) is
   untouched — same owner, more frequent writes.
5. **The toggle becomes authoritative.** Today `onAppear` calls
   `installAgentIfNeeded()` unconditionally (`DeckApp/DeckApp.swift:154`), so
   relaunching Deck reinstalls agents the user switched off. New reconcile-on-
   launch: register only when the toggle is on and the service is not
   `.enabled`; unregister when the toggle is off and the service is `.enabled`;
   and adopt the OS status into the toggle when they disagree the other way
   (mirror reality, resolved in interview). `.notFound` / `.notRegistered` /
   `.requiresApproval` each have a defined action (see Failure behavior).
   **Registration happens only at launch and on the toggle's `onChange`** —
   today `applyAgent()` also runs from the blanket `onChange(of: settings)`
   (`DeckApp/DeckApp.swift:185-189`), which rewrites plists on every settings
   change; that call must be removed so a settings keystroke does not
   register/unregister the services.

### Failure behavior

- **Registration errors** (`SMAppServiceError`): surface as a short caption
  under the toggle, and log to the `com.deck.agent` subsystem via OSLog.
  Registration is retried on the next launch — SMAppService is idempotent by
  design, and most errors (wrong app location, LaunchServices not seeing the
  app yet) are transient.
- **App not in an approved location** (dev build in `build.noindex`): register
  throws `.registrationDenied`-class errors. Deck tolerates this — the toggle
  shows the failure caption and stays on so an install into `/Applications`
  self-heals. This is inherent to SMAppService; dev-machine verification
  happens through the installed copy (the repo's standard flow).
- **`.requiresApproval`**: leave the service alone; the OS owns the prompt.
  The toggle stays on and the caption notes the pending approval.
- **User disables in System Settings**: status reads `.notRegistered`; on the
  next launch Deck adopts that into the toggle (off) and does **not**
  re-register.
- **Fast agent launchd tick (5s) with a longer configured interval**: the
  agent process wakes every 5s but does no sampling and no writes between
  configured ticks (pure policy gate; see tests).

### Migration (one-release courtesy)

On every launch, before registering: `launchctl bootout gui/uid/com.deck.agent`
(and `.processes`) and delete the legacy plists from `~/Library/LaunchAgents`.
The old and new registrations share **labels**, so a stale bootstrap would
collide with the SMAppService registration; cleanup must precede registration.
The legacy files exist only for installs upgraded from ≤1.32; the courtesy can
be removed after this release ships, like the `DeckSecret` fallback.

## Data source

No new data sources. The agent binaries, snapshot stores, and widget faces are
untouched except for the two changes above (env-var role selection + always-
write processes snapshot with its throttle). The plists become static repo
files instead of runtime-generated strings; they carry **no** log paths (see
choice 3 — launchd cannot expand a user-home path in a signed plist, and the
agent's diagnostics are OSLog). The app still creates the 0700
`~/Library/Logs/Deck` directory at launch so the documented layout and the
cask/README uninstall cleanup stay truthful.

## Shell fit

This feature touches the **host app's agent plumbing**, not the widget shell:
no `DeckWidgets/` face files, no panel invariants, no snapshot schema. It
deletes the plist-writing machinery (`installAgent`, `plistValue`,
`currentStartInterval`, `currentLogPath`, `runLaunchctl`) and replaces it with
a small `AgentService` wrapper. The only widget-adjacent change is the
processes-snapshot write cadence, which improves LiveBox (process rows no
longer go empty on quiet machines) and keeps its settings range honest.

### Version bump

New bundle contents (two plists) ship in a release: bump to 1.33 / build 33
in `project.yml` (also required by the release process).

## Non-goals

- Not moving `DeckAgent` itself out of `Contents/MacOS` (it stays where the
  post-build script puts it; `BundleProgram` addresses it there).
- Not migrating the widget extension or any snapshot store.
- Not the notarization / bundle-identifier work — those are separate M7 items
  that will ride the same release; this PRD does not rename anything.
- Not dropping the `processRefreshInterval` setting; not changing its range.
- Not converting the two agents into one (the 60s/15s cadence split is
  deliberate, M4).
- Not switching to `SMAppService.mainApp` — the login item is the *agent*,
  not the app; Deck.app itself must not launch at login.

## Resolved decisions (from the dig + interview)

1. BundleProgram + relative path — move-proof helper addressing (Apple docs).
2. `DECK_AGENT_ROLE=processes` env var replaces the plist's `--processes` arg.
3. No StandardOut/Err paths in the bundle plists (launchd won't expand `~`);
   diagnostics are OSLog-only; the app still creates the 0700 log directory.
4. Fast plist StartInterval pinned at 5s; agent self-throttles via pure policy.
5. Processes snapshot always written (fresh writtenAt every sample).
6. Toggle mirrors actual registration status; reconcile at launch; no fight;
   registration only at launch and on the toggle's onChange, not on every
   settings change.
7. Legacy plist bootout + deletion runs before registration, this release only.
8. Plists embedded by extending the existing post-build script (XcodeGen has
   no `launchAgents` copyFiles destination — verified in the ProjectSpec).

## Open questions

None — all forks resolved in the interview above. The one residual risk is
environmental, not design: whether macOS 15 in practice auto-approves the two
agent registrations from a non-notarized Developer ID-signed app in
`/Applications` (dev-signed today). It is expected to (the app is in an
approved location), but it is the first thing the implementation plan's
verification phase checks on the installed copy.
