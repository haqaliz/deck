import SwiftUI
import WidgetKit
import AppKit

@main
struct DeckApp: App {
    @NSApplicationDelegateAdaptor(DeckAppDelegate.self) private var appDelegate

    /// Carry `settings.json` across the container move the bundle rename
    /// forces — **before** anything reads settings. `ContentView` loads them in
    /// a property initialiser, so this cannot be deferred to `onAppear`.
    /// Inert until the rename ships (both paths resolve to one directory), and
    /// idempotent afterwards. `DeckAgent` runs the same call for the same
    /// reason: it is registered at login and can start first.
    static let migration = ContainerMigration.run()

    var body: some Scene {
        WindowGroup("Deck") {
            ContentView()
        }
        .windowResizability(.contentSize)
        // Deck's settings window is not a document and must never be opened
        // *by* an external event. Without this, every widget URL delivered to
        // the app made SwiftUI manufacture another settings window on top of
        // the one already on screen. The URL is handled in the app delegate
        // instead, which forwards it to the browser.
        .handlesExternalEvents(matching: [])
    }
}

/// Exists for one reason: WidgetKit on macOS delivers a widget's URL to the
/// containing app rather than to the browser. Without this, clicking a PRBox
/// row launched Deck, dropped the URL on the floor, and — because the scene is
/// a plain `WindowGroup` — left a new settings window behind every time.
///
/// So Deck forwards the URL and gets out of the way: if it was launched purely
/// to carry that click, it opens the page and quits instead of leaving a
/// window nobody asked for.
final class DeckAppDelegate: NSObject, NSApplicationDelegate {
    /// True when the process was started to deliver a URL rather than by
    /// someone opening Deck. `application(_:open:)` runs before
    /// `applicationDidFinishLaunching`, so this is known in time to decide
    /// whether a window is wanted at all.
    private var launchedToOpenAURL = false
    private var finishedLaunching = false

    func application(_ application: NSApplication, open urls: [URL]) {
        let webURLs = DeckURLForwarding.webURLs(from: urls)
        for url in webURLs {
            NSWorkspace.shared.open(url)
        }

        // Nothing usable in the batch: behave exactly as before rather than
        // quitting an app the user may have opened deliberately.
        guard !webURLs.isEmpty else { return }

        if finishedLaunching {
            // Already running with a window on screen: the user gets their
            // page and keeps whatever they were doing.
            return
        }
        launchedToOpenAURL = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        finishedLaunching = true
        guard launchedToOpenAURL else { return }
        // The page is already opening in the browser; a settings window would
        // be pure noise.
        NSApplication.shared.windows.forEach { $0.close() }
        NSApplication.shared.terminate(nil)
    }

    /// Clicking the Dock icon of a running Deck should raise the window it
    /// already has, not manufacture another one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag
    }
}

struct ContentView: View {
    @State private var settings: DeckSettings = {
        _ = DeckApp.migration
        return DeckSettings.load()
    }()
    @State private var agentError: String?
    @State private var agentNotice: String?
    /// Whether the agents are actually *running*, as distinct from registered.
    /// A value rather than a pre-rendered string: the view varies both the
    /// wording and the presence of a repair button on it.
    @State private var liveness: AgentLiveness = .unknown

    /// Wording for the identifier change, or `nil` when there is nothing to
    /// say. A failure is reported even after the notice has been dismissed:
    /// dismissing acknowledges "re-add your widgets", not "my settings are
    /// gone".
    private var renameNotice: String? {
        switch DeckApp.migration {
        case .migrated:
            return settings.didShowRenameNotice
                ? nil
                : "Deck's identifier changed. Remove and re-add your widgets from the Widget Center."
        case .failed:
            return "Deck's identifier changed and your settings could not be carried over. "
                + "The previous copy is still at \(ContainerMigration.legacyDirectory.path)."
        case .skipped:
            return nil
        }
    }
    /// Accounts the keychain refused to hand over this launch — a locked
    /// login keychain, most likely. Kept apart from "never set", which is a
    /// different message and a different field to fix.
    @State private var unavailableAccounts: Set<String> = []
    /// The same, for the five pre-accounts items, until the migration runs.
    @State private var unavailableSecrets: Set<DeckSecret> = []
    @State private var selection: DeckWidget = .livebox
    @State private var timer: Timer?
    @State private var toolbarSweepTimer: Timer?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(DeckWidget.general)
                Label("Credentials", systemImage: "key.fill")
                    .tag(DeckWidget.credentials)
                Section("Widgets") {
                    ForEach(DeckWidget.allCases.filter { $0 != .general && $0 != .credentials }) { widget in
                        Label(widget.title, systemImage: widget.systemImage)
                            .tag(widget)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
        } detail: {
            switch selection {
            case .general: GeneralSettingsView(
                agentAtLogin: $settings.agentAtLogin,
                agentError: agentError,
                agentNotice: agentNotice,
                liveness: liveness,
                onRestartAgents: restartAgents,
                renameNotice: renameNotice,
                // Only a successful migration is dismissible. A failure keeps
                // reporting itself: dismissing acknowledges "re-add your
                // widgets", never "my settings are missing".
                onDismissRenameNotice: {
                    guard case .migrated = DeckApp.migration else { return nil }
                    return {
                        settings.didShowRenameNotice = true
                        settings.save()
                    }
                }(),
                onRemoveAgents: uninstallAgents,
                onEraseData: eraseDeckData
            )
            case .credentials: CredentialsSettingsView(
                settings: $settings,
                unavailableAccounts: unavailableAccounts,
                onSecretCommitted: accountSecretCommitted
            )
            case .livebox: LiveBoxSettingsView(settings: $settings.livebox)
            case .openbox: OpenBoxSettingsView(
                settings: $settings.openbox,
                accountID: $settings.openbox.accountID,
                accounts: settings.credentials.accounts,
                onManage: { selection = .credentials }
            )
            case .netbox: NetBoxSettingsView(settings: $settings.netbox)
            case .batbox: BatBoxSettingsView(settings: $settings.batbox)
            case .gitbox: GitBoxSettingsView(settings: $settings.gitbox)
            case .devbox: DevBoxSettingsView(settings: $settings.devbox)
            case .clipbox: ClipBoxSettingsView(settings: $settings.clipbox)
            case .weatherbox: WeatherBoxSettingsView(settings: $settings.weatherbox)
            case .clockbox: ClockBoxSettingsView(settings: $settings.clockbox)
            case .shipbox: ShipBoxSettingsView(
                settings: $settings.shipbox,
                accountID: $settings.shipbox.accountID,
                accounts: settings.credentials.accounts,
                token: settings.credential(for: .shipbox)?.token ?? "",
                onManage: { selection = .credentials }
            )
            case .taskbox: TaskBoxSettingsView(
                settings: $settings.taskbox,
                accountID: $settings.taskbox.accountID,
                accounts: settings.credentials.accounts,
                onManage: { selection = .credentials }
            )
            case .calbox: CalBoxSettingsView(settings: $settings.calbox)
            case .prbox: PRBoxSettingsView(
                settings: $settings.prbox,
                accounts: settings.credentials.accounts,
                onManage: { selection = .credentials }
            )
            case .marketbox: MarketBoxSettingsView(settings: $settings.marketbox)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 640, height: 500)
        .onAppear {
            DeckSettings.tightenPermissions()
            adoptKeychainSecrets()
            reconcileAgents()
            Task { await refreshOpenCode() }
            refreshGitBox()
            refreshDevBox()
            refreshClipBox()
            Task { await refreshWeather() }
            Task { await refreshShipBox() }
            Task { await refreshTaskBox() }
            Task { await refreshCalBox() }
            Task { await refreshPRBox() }
            Task { await refreshMarketBox() }
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                // Cheap (one small file decode), and it means the notice
                // appears — and clears after a repair — while the user is
                // watching the tab, which is when they are looking.
                evaluateLiveness()
                Task { await refreshOpenCode() }
                refreshGitBox()
                refreshDevBox()
                refreshClipBox()
                Task { await refreshWeather() }
                Task { await refreshShipBox() }
                Task { await refreshTaskBox() }
                Task { await refreshCalBox() }
                Task { await refreshPRBox() }
                Task { await refreshMarketBox() }
            }
            WidgetCenter.shared.reloadAllTimelines()
            toolbarSweepTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                removeSidebarToggleFromWindow()
            }
        }
        .onDisappear {
            toolbarSweepTimer?.invalidate()
        }
        .onChange(of: settings) { _ in
            settings.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: settings.agentAtLogin) { _ in
            applyAgent()
        }
    }

    /// Read opencode metrics (local DB or remote server) and push a snapshot
    /// into the widget container. Remote mode never passes a default token:
    /// without the user's own token nothing is fetched.
    private func refreshOpenCode() async {
        let snapshot: OpenCodeSnapshot?
        if settings.openBoxUsesRemoteServer {
            switch gate(.openbox) {
            case .fetch(let credential):
                do {
                    let (remote, _) = try await RemoteOpenCodeLoader.load(
                        serverURL: credential.serverURL, token: credential.token, state: nil
                    )
                    snapshot = remote
                    FetchStatusStore.record(.ok, for: .opencodeRemote)
                } catch {
                    snapshot = nil
                    FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .opencodeRemote)
                }
            case .unavailable:
                snapshot = nil
                FetchStatusStore.record(.credentialsUnavailable, for: .opencodeRemote)
            default:
                snapshot = nil
                FetchStatusStore.record(.notConfigured, for: .opencodeRemote)
            }
        } else {
            snapshot = OpenCodeReader.load()
            // Local mode shows no chip, but a stale remote failure must not
            // outlive the mode that produced it.
            if snapshot != nil {
                FetchStatusStore.record(.ok, for: .opencodeRemote)
            }
        }
        guard let snapshot else { return }
        if snapshot != OpenCodeSnapshotStore.load() {
            OpenCodeSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Sample git activity (host is unsandboxed) for the GitBox widget.
    private func refreshGitBox() {
        guard let snapshot = HostGitBoxSampler.snapshot(
            paths: settings.gitbox.repoPaths,
            scanDepth: settings.gitbox.scanDepth
        ) else { return }
        if snapshot != GitBoxSnapshotStore.load() {
            GitBoxSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Sample open ports and Docker containers (host is unsandboxed) for the
    /// DevBox widget.
    private func refreshDevBox() {
        guard let snapshot = HostDevBoxSampler.snapshot() else { return }
        if snapshot != DevBoxSnapshotStore.load() {
            DevBoxSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Sample the clipboard (host is unsandboxed) for the ClipBox widget.
    private func refreshClipBox() {
        guard let snapshot = HostClipBoardSampler.snapshot(maxCount: settings.clipbox.historyCount) else { return }
        if snapshot != ClipBoxSnapshotStore.load() {
            ClipBoxSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Fetch weather (host is unsandboxed) for the WeatherBox widget. Always
    /// written on success so writtenAt drives the staleness windows.
    private func refreshWeather() async {
        let snapshot: WeatherSnapshot
        do {
            snapshot = try await HostWeatherLoader.fetch(location: settings.weatherbox.location)
        } catch {
            FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .weather)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        WeatherSnapshotStore.save(snapshot)
        FetchStatusStore.record(.ok, for: .weather)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fetch GitHub Actions runs (host is unsandboxed) for the ShipBox widget.
    /// Requires the user's own repo + token — never a default token. Always
    /// written on success so writtenAt drives the staleness windows.
    /// Fetch both providers and write one snapshot. A provider that is off, or
    /// on but missing credentials, is recorded as `.ok` rather than skipped
    /// silently: `FetchStatusStore` has no clear, and `.ok` is what erases a
    /// failure the user has since switched off. Recording `.notConfigured`
    /// instead would keep nagging about a provider they disabled.
    private func refreshPRBox() async {
        let prbox = settings.prbox

        var github: PRRoleTotals?
        switch gate(.prboxGitHub) {
        case .fetch(let credential):
            do {
                github = try await HostGitHubPRLoader.fetch(
                    token: credential.token,
                    scope: prbox.github.scope,
                    cap: prbox.prCount
                )
                FetchStatusStore.record(.ok, for: .prboxGitHub)
            } catch {
                FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .prboxGitHub)
            }
        case let other:
            if let outcome = other.outcome { FetchStatusStore.record(outcome, for: .prboxGitHub) }
        }

        var azure: PRRoleTotals?
        switch gate(.prboxAzure) {
        case .fetch(let credential):
            do {
                azure = try await HostAzurePRLoader.fetch(
                    organization: credential.organization,
                    projects: credential.projects,
                    token: credential.token,
                    cap: prbox.prCount
                )
                FetchStatusStore.record(.ok, for: .prboxAzure)
            } catch {
                FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .prboxAzure)
            }
        case let other:
            if let outcome = other.outcome { FetchStatusStore.record(outcome, for: .prboxAzure) }
        }

        // One provider failing must not blank the other's rows.
        if github != nil || azure != nil {
            PRBoxSnapshotStore.save(
                PRSnapshotBuilder.build(
                    github: github, azure: azure, cap: prbox.prCount, now: Date()
                )
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshShipBox() async {
        let shipbox = settings.shipbox
        // Dynamic mode needs only a token; static mode also needs a repo.
        // Mirrors DeckAgent exactly — the two have always been line-for-line.
        guard gate(.shipbox) != .unavailable else {
            FetchStatusStore.record(.credentialsUnavailable, for: .shipbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let hasATarget = shipbox.repoMode == .dynamic || !shipbox.repos.isEmpty
        guard case .fetch(let credential) = gate(.shipbox), hasATarget else {
            FetchStatusStore.record(.notConfigured, for: .shipbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot: ShipBoxSnapshot
        do {
            snapshot = try await HostGitHubLoader.fetch(settings: shipbox, token: credential.token)
        } catch {
            FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .shipbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        ShipBoxSnapshotStore.save(snapshot)
        FetchStatusStore.record(.ok, for: .shipbox)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fetch Azure DevOps work items (host is unsandboxed) for the TaskBox
    /// widget. Requires the user's own org, project and PAT — never a default
    /// token. Always written on success so writtenAt drives the staleness
    /// windows; a failure leaves the last-good snapshot untouched.
    private func refreshTaskBox() async {
        guard gate(.taskbox) != .unavailable else {
            FetchStatusStore.record(.credentialsUnavailable, for: .taskbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        guard case .fetch(let credential) = gate(.taskbox) else {
            FetchStatusStore.record(.notConfigured, for: .taskbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot: TaskBoxSnapshot
        do {
            snapshot = try await HostAzureDevOpsLoader.fetch(
                organization: credential.organization,
                projects: credential.projects,
                token: credential.token
            )
        } catch {
            FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .taskbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        TaskBoxSnapshotStore.save(snapshot)
        FetchStatusStore.record(.ok, for: .taskbox)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Install/remove the background refresh agent (launch at login) with the
    /// configured refresh interval.
    private func applyAgent() {
        if settings.agentAtLogin {
            registerAgents()
        } else {
            removeAgents()
        }
    }

    /// Launch-time reconciliation: make the actual registration match the
    /// user's intent, and mirror reality back into the toggle when System
    /// Settings is the one that changed. Never fights the user — a service the
    /// user disabled in System Settings → Login Items stays off and flips the
    /// toggle off; one they enabled there flips it back on.
    private func reconcileAgents() {
        legacyCleanup()
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        var registrationError: String?
        var blocked = false
        var didRegister = false
        for agent in AgentService.all {
            for action in AgentReconcilePolicy.resolve(intent: settings.agentAtLogin, state: agent.state) {
                switch action {
                case .register:
                    do {
                        try agent.register()
                        didRegister = true
                    } catch {
                        registrationError = "Could not register the background agents: \(error.localizedDescription)"
                    }
                case .adoptIntent(let on):
                    if settings.agentAtLogin != on {
                        settings.agentAtLogin = on
                        settings.save()
                    }
                case .reportBlocked:
                    blocked = true
                case .unregister:
                    break // The policy never unregisters; the toggle handler does.
                }
            }
        }
        agentError = registrationError
        agentNotice = blocked ? Self.agentsBlockedNotice : nil

        // ORDER IS LOAD-BEARING. The stamp must be written before liveness is
        // evaluated, or the bundle rename becomes this check's first false
        // positive: ContainerMigration copies settings.json verbatim, so the
        // renamed app starts with an `agentsRegisteredAt` from days ago and a
        // brand-new container holding no processes.json — which reads as
        // "registered long ago, never ran" the moment the window opens, while
        // the new agents are registering perfectly normally.
        //
        // With the stamp first, the new labels are `.notFound`, the loop above
        // registers them, this writes `now`, and the evaluation below sees a
        // fresh registration inside its grace window.
        stampAgentsRegisteredAt(didRegister: didRegister)
        evaluateLiveness()
    }

    /// Persist the grace-period clock. The rule itself is
    /// `AgentRegistrationClock` — two triggers, and the reason they cannot be
    /// collapsed into one is written up there.
    private func stampAgentsRegisteredAt(didRegister: Bool) {
        let stamp = AgentRegistrationClock.stamp(
            stored: settings.agentsRegisteredAt,
            didRegister: didRegister,
            state: AgentService.processes.state,
            now: Date()
        )
        // Only write when it actually changed: `.onChange(of: settings)` saves
        // the file and reloads every widget timeline, and an ordinary launch
        // should do neither.
        guard stamp != settings.agentsRegisteredAt else { return }
        settings.agentsRegisteredAt = stamp
        settings.save()
    }

    /// Ask whether the agents are running, from the two pieces of evidence that
    /// can answer it — one per agent, each written by that agent alone:
    /// `processes.json` for the fast agent, `agent-heartbeat.json` for the 60s
    /// one. Every other snapshot is written by this app too, and so witnesses
    /// nothing.
    private func evaluateLiveness() {
        liveness = AgentLivenessPolicy.resolve(
            intent: settings.agentAtLogin,
            state: AgentService.processes.state,
            processes: ProcessSnapshotStore.evidence(),
            data: AgentHeartbeatStore.evidence(),
            registeredAt: settings.agentsRegisteredAt,
            processRefreshInterval: settings.livebox.processRefreshInterval,
            now: Date()
        )
    }

    /// Shown when the agents are registered but the user has switched Deck off
    /// under System Settings → General → Login Items. Deck does not flip its
    /// own toggle back — the veto is the user's, and the same OS state also
    /// means "registered, awaiting first approval".
    static let agentsBlockedNotice =
        "Turned off in System Settings → Login Items. Deck's agents are not running."


    /// The "Refresh in background" toggle changed: on registers, off unregisters.
    private func registerAgents() {
        legacyCleanup()
        do {
            try AgentService.registerAll()
            agentError = nil
            agentNotice = AgentService.all.contains { $0.state == .requiresApproval }
                ? Self.agentsBlockedNotice
                : nil
        } catch {
            agentError = "Could not register the background agents: \(error.localizedDescription)"
        }
        stampAgentsRegisteredAt(didRegister: true)
        evaluateLiveness()
    }

    /// The documented recovery for "registered but not loaded": unregister,
    /// then register again. It cannot be driven from settings.json — with the
    /// record `.enabled` the reconcile policy re-adopts `agentAtLogin: true`
    /// from the registration and never unregisters — so a button is the only
    /// place it can live.
    ///
    /// Goes through `removeAgents()` / `registerAgents()` rather than calling
    /// `AgentService` directly, because `registerAgents()` runs
    /// `legacyCleanup()` first **and waits for it**: a fire-and-forget bootout
    /// races the registration and the label collision rejects the new job. It
    /// also owns the `agentError` and blocked-notice handling.
    /// `registerAgents()` restarts the grace-period clock, so the notice goes
    /// quiet for one grace window after the button is pressed. That is the
    /// intended "give the repair a moment to take" behaviour rather than an
    /// accident — but note what it costs: if the re-registration is a silent
    /// no-op (`Agent.register()` returns early when the status is still
    /// `.enabled`, and whether `unregister()` drops it synchronously is
    /// unmeasured), the button *looks* like it worked for one window before
    /// the notice returns. It does return. Nothing is hidden permanently.
    private func restartAgents() {
        removeAgents()
        registerAgents()
    }

    /// Unregister both SMAppService agents and remove any legacy
    /// `~/Library/LaunchAgents` plists left by installs predating SMAppService.
    private func removeAgents() {
        AgentService.unregisterAll()
        legacyCleanup()
        // Nothing is registered any more, so a "blocked in System Settings"
        // notice would be stale the moment it is read.
        agentNotice = nil
        evaluateLiveness()
    }

    /// Boot out and delete the pre-SMAppService agents. One-release courtesy
    /// for installs upgraded from ≤1.32: the legacy jobs share labels with the
    /// SMAppService registration, so a stale bootstrap would collide with it.
    /// Must run before registering — and must finish before registering, hence
    /// `waitUntilExit`: a fire-and-forget bootout can race the registration
    /// and the label collision would reject the new job.
    private func legacyCleanup() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func plistURL(_ label: String) -> URL {
            home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        }
        // Only labels that still have a hand-written plist. Without this guard
        // the bootout below lands on Deck's own running SMAppService jobs,
        // because before the rename the legacy labels ARE the current ones —
        // see `LegacyAgentCleanup`.
        let labels = LegacyAgentCleanup.labelsNeedingCleanup(
            candidates: [DeckBundle.Legacy.agentLabel, DeckBundle.Legacy.fastAgentLabel],
            plistExists: { FileManager.default.fileExists(atPath: plistURL($0).path) }
        )
        for label in labels {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: plistURL(label))
        }
    }

    /// Agent logs. Not `/tmp`: that directory is world-writable, so any local
    /// process could pre-create the predictable path and have launchd append
    /// the agent's output to a file it controls.
    private var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Deck")
    }

    /// Uninstall: stop and forget both LaunchAgents. Also clears the toggle so
    /// the next settings change does not quietly reinstall them.
    private func uninstallAgents() {
        settings.agentAtLogin = false
        removeAgents()
    }

    /// Moves any credential still in `settings.json` into the keychain, then
    /// fills the in-memory settings from it.
    ///
    /// Migration first: until it has run the file is still the only place the
    /// token exists, and hydrating would find nothing to overwrite it with.
    /// Saving is what scrubs the file, so it only happens once something moved.
    private func adoptKeychainSecrets() {
        var migrated = settings
        var changed = DeckSecretsMigration.migrate(&migrated)
        // Then the second, one-way step: the five welded credentials become
        // accounts. Same ordering guarantee — write, read back, only then
        // delete — so a keychain failure costs nothing and retries next launch.
        _ = migrated.hydrateFromKeychain()
        if CredentialsMigration.migrate(&migrated) { changed = true }
        if changed {
            settings = migrated
            settings.save()
        }
        unavailableAccounts = settings.hydrateAccountsFromKeychain()
        unavailableSecrets = settings.hydrateFromKeychain()
        for slot in CredentialSlot.allCases where gate(slot) == .unavailable {
            FetchStatusStore.record(.credentialsUnavailable, for: slot.source)
        }
    }

    /// The one decision table, shared with `DeckAgent` so the two cannot drift.
    private func gate(_ slot: CredentialSlot) -> CredentialGate {
        settings.gate(slot, unavailableAccounts: unavailableAccounts,
                      unavailableLegacySecrets: unavailableSecrets)
    }

    /// A freshly pasted credential clears a read failure from this launch —
    /// otherwise the widget would keep saying it can't read a token the user
    /// just typed.
    ///
    /// Accounts only: the five pre-accounts fields have no editing surface any
    /// more, so a legacy read failure can only be cleared by unlocking the
    /// keychain and reopening Deck, which is what the caption says to do.
    private func accountSecretCommitted(_ accountID: String) {
        unavailableAccounts.remove(accountID)
    }

    /// Uninstall: delete Deck's data directory inside the widget container.
    ///
    /// This removes the *contents* Deck owns — settings.json, every snapshot,
    /// the clipboard history — and the five keychain credentials, which is what
    /// keeps the promise below true now that tokens no longer live in the file. It deliberately does not
    /// touch the container itself: that directory's metadata plist is
    /// SIP-protected and survives deletion, after which containermanagerd
    /// never rebuilds the skeleton and every widget renders blank forever.
    private func eraseDeckData() {
        uninstallAgents()
        // Best-effort and silent, like the container sweep below.
        for secret in DeckSecret.allCases {
            DeckKeychain.delete(secret)
        }
        let directory = DeckSettings.containerDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
        settings = DeckSettings()
    }

    private func removeSidebarToggleFromWindow() {
        guard let toolbar = NSApp.windows.first(where: { $0.toolbar != nil })?.toolbar else { return }
        for index in toolbar.items.indices.reversed() {
            if toolbar.items[index].itemIdentifier.rawValue == "com.apple.SwiftUI.navigationSplitView.toggleSidebar" {
                toolbar.removeItem(at: index)
            }
        }
    }
}

/// Read the calendar (host is unsandboxed) for the CalBox widget.
///
/// The app pumps the same snapshot the agent does, so opening settings gives
/// an immediate result instead of waiting up to a minute for the next tick.
private func refreshCalBox() async {
    do {
        let snapshot = try await HostCalendarLoader.fetch(settings: DeckSettings.load().calbox)
        CalBoxSnapshotStore.save(snapshot)
        FetchStatusStore.record(.ok, for: .calbox)
    } catch {
        FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .calbox)
    }
}

/// Pump the MarketBox snapshot from the host app too, so changing the tickers
/// or the display currency applies to the widget immediately instead of on the
/// next agent tick.
private func refreshMarketBox() async {
    do {
        let snapshot = try await HostMarketLoader.fetch(settings: DeckSettings.load().marketbox)
        MarketSnapshotStore.save(snapshot)
        FetchStatusStore.record(.ok, for: .marketbox)
    } catch {
        FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .marketbox)
    }
}

// MARK: - Sidebar selection

private enum DeckWidget: String, CaseIterable, Identifiable {
    case general, credentials
    case livebox, openbox, netbox, batbox, gitbox, devbox, clipbox
    case weatherbox, clockbox, shipbox, taskbox, calbox, prbox, marketbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .credentials: "Credentials"
        case .livebox: "LiveBox"
        case .openbox: "OpenBox"
        case .netbox: "NetBox"
        case .batbox: "BatBox"
        case .gitbox: "GitBox"
        case .devbox: "DevBox"
        case .clipbox: "ClipBox"
        case .weatherbox: "WeatherBox"
        case .clockbox: "ClockBox"
        case .shipbox: "ShipBox"
        case .taskbox: "TaskBox"
        case .calbox: "CalBox"
        case .prbox: "PRBox"
        case .marketbox: "MarketBox"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .credentials: "key.fill"
        case .livebox: "cpu"
        case .openbox: "arrow.left.arrow.right"
        case .netbox: "network"
        case .batbox: "battery.50percent"
        case .gitbox: "chevron.left.forwardslash.chevron.right"
        case .devbox: "server.rack"
        case .clipbox: "doc.on.clipboard"
        case .weatherbox: "cloud.sun"
        case .clockbox: "globe"
        case .shipbox: "shippingbox"
        case .taskbox: "checklist"
        case .calbox: "calendar"
        case .prbox: "arrow.triangle.pull"
        case .marketbox: "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Full-size settings (also reachable from each widget's gear)

private struct GeneralSettingsView: View {
    @Binding var agentAtLogin: Bool
    var agentError: String?
    var agentNotice: String?
    /// Registered, but is launchd actually running them? Only `.down` draws.
    var liveness: AgentLiveness = .unknown
    var onRestartAgents: () -> Void = {}
    /// One-time wording for the bundle identifier change; see
    /// `ContentView.renameNotice`.
    var renameNotice: String?
    /// `nil` when there is nothing to dismiss — a failed migration keeps
    /// reporting itself.
    var onDismissRenameNotice: (() -> Void)?
    var onRemoveAgents: () -> Void
    var onEraseData: () -> Void

    @State private var confirmingErase = false
    @State private var agentsRemoved = false

    /// Says what is wrong and how long it has been wrong, and nothing about
    /// *which* agent: the evidence is the process snapshot, which witnesses
    /// only the fast agent, and claiming more than that would be a guess
    /// dressed as a diagnosis.
    private static func livenessNotice(down: AgentLiveness.Down) -> String {
        let base = "Background refresh has stopped. Deck's agents are registered "
            + "but macOS is not running them."
        guard let lastRefresh = down.reported.timestamp else {
            return base + " No refresh has been recorded."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return base + " Last refresh: \(formatter.localizedString(for: lastRefresh, relativeTo: Date()))."
    }

    var body: some View {
        Form {
            Section("Background refresh") {
                Toggle("Refresh in background (launch at login)", isOn: $agentAtLogin)
                Text("Runs the Deck agent at login to keep widget data fresh even when the app is closed. The agents are listed in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let agentError {
                    Text(agentError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let agentNotice {
                    Label(agentNotice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                // The third way the agents can be down: registered, allowed,
                // and never loaded by launchd. Nothing in the OS reports it,
                // so it is inferred from the age of the one snapshot only the
                // agent writes. `.healthy` and `.unknown` draw nothing —
                // silence is the healthy state here, as it is for every other
                // notice in this tab.
                if case .down(let down) = liveness {
                    HStack(alignment: .firstTextBaseline) {
                        Label(
                            Self.livenessNotice(down: down),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Spacer()
                        Button("Restart agents", action: onRestartAgents)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                // Shown once, after the identifier change moved Deck's
                // container. The widgets already on the desktop point at the
                // old extension and will never render again; without this the
                // symptom reads exactly like the blank-widget bug.
                if let renameNotice {
                    HStack(alignment: .firstTextBaseline) {
                        Label(renameNotice, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        if let onDismissRenameNotice {
                            Button("Dismiss", action: onDismissRenameNotice)
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
            }

            // Deck registers two LaunchAgents on first run. Leaving the only
            // removal path in the README as four terminal commands is not a
            // fair deal for something that starts itself at login.
            Section("Uninstall") {
                Button("Remove background agents") {
                    onRemoveAgents()
                    agentsRemoved = true
                }
                Text(agentsRemoved
                     ? "Removed. Widgets keep their last data but stop refreshing."
                     : "Unregisters com.deck.agent and com.deck.agent.processes from login items.")
                    .font(.caption)
                    .foregroundStyle(agentsRemoved ? .green : .secondary)

                Button("Erase Deck data…", role: .destructive) {
                    confirmingErase = true
                }
                Text("Deletes settings, snapshots and clipboard history. This includes your ShipBox, TaskBox and OpenBox tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("To finish: remove the Deck widgets from your desktop, then drag Deck to the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .confirmationDialog(
            "Erase all Deck data?",
            isPresented: $confirmingErase,
            titleVisibility: .visible
        ) {
            Button("Erase", role: .destructive) { onEraseData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your settings, every widget snapshot, your clipboard history and your saved tokens will be deleted. This cannot be undone.")
        }
    }
}

private struct LiveBoxSettingsView: View {
    @Binding var settings: LiveBoxSettings

    var body: some View {
        Form {
            Section("Chart") {
                Toggle("Show chart", isOn: $settings.showChart)
                Toggle("Per-core CPU lines", isOn: $settings.showPerCoreCores)
                    .disabled(!settings.showChart)
                ColorPicker("CPU color", selection: $settings.cpuColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("MEM color", selection: $settings.memColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("DISK color", selection: $settings.diskColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Metrics") {
                Toggle("Show CPU", isOn: $settings.showCPU)
                Toggle("Show MEM", isOn: $settings.showMEM)
                Toggle("Show DISK", isOn: $settings.showDisk)
                Toggle("Show thermal state", isOn: $settings.showThermal)
                Text("System thermal pressure (nominal / fair / serious / critical), not a temperature reading. Turns amber at serious and red at critical.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Disk") {
                Toggle("Show per-volume disk", isOn: $settings.showPerVolumeDisk)
                    .disabled(!settings.showDisk)
                Text("Lists internal and external volumes on the large widget; small and medium keep the aggregate disk row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Thresholds") {
                Toggle("Show threshold colors", isOn: $settings.showThresholdColors)
                thresholdGroup("CPU", warn: $settings.cpuWarnThreshold, alarm: $settings.cpuAlarmThreshold)
                thresholdGroup("MEM", warn: $settings.memWarnThreshold, alarm: $settings.memAlarmThreshold)
                thresholdGroup("DISK", warn: $settings.diskWarnThreshold, alarm: $settings.diskAlarmThreshold)
                Text("Values at or above a metric's warn threshold turn amber; at or above its alarm threshold, red. Alarm takes precedence when it is lower than Warn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Processes") {
                Toggle("Show top processes", isOn: $settings.showProcesses)
                Stepper("Process count: \(settings.processCount)", value: $settings.processCount, in: 1...20)
                    .disabled(!settings.showProcesses)
                Stepper("Process refresh: \(settings.processRefreshInterval) s", value: $settings.processRefreshInterval, in: 5...60, step: 5)
                    .disabled(!settings.showProcesses)
                Text("How often the widget and the background agent refresh the process list. Lower is livelier; other widgets stay on their own cadence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private func thresholdGroup(_ name: String, warn: Binding<Int>, alarm: Binding<Int>) -> some View {
        Group {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("Warn at: \(warn.wrappedValue)%", value: warn, in: 0...100)
                .disabled(!settings.showThresholdColors)
            Stepper("Alarm at: \(alarm.wrappedValue)%", value: alarm, in: 0...100)
                .disabled(!settings.showThresholdColors)
        }
    }
}

/// A `SecureField` whose value lives in the keychain rather than in
/// `settings.json`.
///
/// The draft is local so `onChange(of: settings)` — which fires per keystroke
/// and saves the whole file — never sees a half-typed token. The value is
/// committed on Return or when the field loses focus, and only then does it
/// reach the keychain and the in-memory settings.
/// Picks which stored account a widget fetches with.
///
/// Filtered to the kind that widget needs, so a GitHub slot can never be
/// pointed at an Azure PAT. There are no token fields on widget tabs any more:
/// one editing surface per secret, in Credentials.
private struct AccountPicker: View {
    let kind: CredentialKind
    let accounts: [CredentialAccount]
    @Binding var accountID: String?
    var onManage: () -> Void

    private var matching: [CredentialAccount] { accounts.filter { $0.kind == kind } }

    /// `nil` and `""` are the same thing to a Picker, which cannot tag nil.
    private var selection: Binding<String> {
        Binding(
            get: { accountID ?? "" },
            set: { accountID = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        Picker("Account", selection: selection) {
            Text("None").tag("")
            ForEach(matching) { account in
                Text(title(account)).tag(account.id)
            }
            // A selection whose account was deleted stays listed rather than
            // silently resolving to None: the widget really is pointed at
            // something missing, and the picker is where that gets fixed.
            if let id = accountID, !matching.contains(where: { $0.id == id }) {
                Text("Deleted account").tag(id)
            }
        }
        HStack(spacing: 6) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Manage in Credentials\u{2026}", action: onManage)
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private func title(_ account: CredentialAccount) -> String {
        let name = account.label.isEmpty ? account.kind.displayName : account.label
        return "\(name) \u{00B7} \(CredentialsCopy.subtitle(for: account))"
    }

    private var caption: String {
        if matching.isEmpty {
            return "No \(kind.displayName) accounts yet."
        }
        return accountID == nil ? "Nothing is fetched until an account is picked." : ""
    }
}

/// A `SecretField` for an account's token.
///
/// Commit semantics are `SecretField`'s, unchanged and deliberately so: on blur
/// and on submit, never per keystroke. Settings are written on every mutation,
/// and a keychain write per character would be both wasteful and racy.
private struct AccountSecretField: View {
    let title: String
    let accountID: String
    @Binding var value: String
    var onCommit: (String) -> Void = { _ in }

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        SecureField(title, text: $draft)
            .focused($focused)
            .textContentType(.password)
            .onAppear { draft = value }
            .onChange(of: value) { newValue in
                if !focused { draft = newValue }
            }
            .onSubmit(commit)
            .onChange(of: focused) { isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        guard draft != value else { return }
        DeckKeychain.write(accountID: accountID, value: draft)
        value = draft
        onCommit(accountID)
    }
}

/// The provider's own mark, shared by the account list, the Add sheet and the
/// detail header.
///
/// Vendor artwork, converted from their SVGs to vector PDFs so it stays sharp
/// at any size. GitHub and opencode ship a light and a dark version; Azure
/// DevOps' is coloured and reads on both. If the artwork cannot be loaded the
/// view falls back to the SF Symbol rather than leaving a hole.
private struct CredentialIcon: View {
    let kind: CredentialKind
    var size: CGFloat = 28

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = Self.artwork(kind, dark: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: kind.systemImage)
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        // opencode's mark is a full-bleed block, where GitHub's and Azure's sit
        // on transparency. Rounding the corners makes the block read as an icon
        // instead of a raw rectangle, and is a no-op for the other two.
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    /// Loaded once per name — an `NSImage` per row per redraw would re-read the
    /// PDF on every keystroke in the settings window.
    private static var cache: [String: NSImage] = [:]

    private static func artwork(_ kind: CredentialKind, dark: Bool) -> NSImage? {
        let name = kind.assetName(dark: dark)
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// "Add Account…" — pick a provider, optionally by searching for it.
///
/// Modelled on System Settings → Internet Accounts: one button on the list,
/// and the choice of *what kind* happens here rather than as three separate
/// buttons scattered down the page.
private struct AddAccountSheet: View {
    var onPick: (CredentialKind) -> Void
    var onCancel: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [CredentialKind] { CredentialKind.matching(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Account")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))

            Text("Choose your provider")
                .font(.subheadline.weight(.semibold))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.self) { kind in
                        Button { onPick(kind) } label: { providerRow(kind) }
                            .buttonStyle(.plain)
                        if kind != matches.last {
                            Divider().padding(.leading, 46)
                        }
                    }
                    if matches.isEmpty {
                        Text("No provider matches \u{201C}\(query)\u{201D}.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .frame(height: 168)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { searchFocused = true }
    }

    private func providerRow(_ kind: CredentialKind) -> some View {
        HStack(spacing: 10) {
            CredentialIcon(kind: kind, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.displayName)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// The Credentials tab: typed accounts, many per kind, each referenced by
/// whichever widgets point at it.
///
/// Two levels, like Internet Accounts: a list of accounts with a chevron on
/// each, and a detail page reached by clicking one, with a back button. Adding
/// is a single button that opens a provider picker, rather than one Add button
/// per kind down the page.
private struct CredentialsSettingsView: View {
    @Binding var settings: DeckSettings
    var unavailableAccounts: Set<String>
    var onSecretCommitted: (String) -> Void

    /// The account being viewed. `nil` is the list.
    @State private var editing: String?
    /// The account most recently backed out of, so Forward can return to it —
    /// System Settings' control is a pair, and a Forward arrow that never
    /// enables is just decoration.
    @State private var forwardTarget: String?
    @State private var adding = false
    @State private var verifying: Set<String> = []
    /// Projects discovered per account id. Absent means "not asked yet or the
    /// ask failed", which is what falls the slots back to plain text fields.
    @State private var discovered: [String: [String]] = [:]
    @State private var discovering: Set<String> = []
    /// Verify failures, by account id. Successes live on the account itself.
    @State private var failures: [String: String] = [:]
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let account = editing.flatMap(account) {
                detail(account)
            } else {
                list
            }
        }
        .toolbar { navigationToolbarItem }
        .sheet(isPresented: $adding) {
            AddAccountSheet(
                onPick: { kind in
                    adding = false
                    add(kind)
                },
                onCancel: { adding = false }
            )
        }
    }

    private func account(_ id: String) -> CredentialAccount? {
        settings.credentials.accounts.first { $0.id == id }
    }

    /// Back and Forward as one joined control, in the **window toolbar** beside
    /// the title, the way System Settings places it.
    ///
    /// `ControlGroup` is what gives the shared border and the divider; two
    /// separate bordered buttons read as two buttons. A `.toolbar` on a view
    /// inside the split view's detail column merges into the window's toolbar,
    /// so this appears only while the Credentials tab is showing.
    ///
    /// Just the control — the window title stays "Deck". Which account you are
    /// looking at is already named by the header inside the page.
    @ToolbarContentBuilder
    private var navigationToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(editing == nil)
                .help("Back to accounts")

                Button {
                    goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                .help("Forward")
            }
            .controlGroupStyle(.navigation)
            .fixedSize()
        }
    }

    private var canGoForward: Bool {
        guard editing == nil, let target = forwardTarget else { return false }
        return account(target) != nil
    }

    private func goBack() {
        forwardTarget = editing
        editing = nil
    }

    private func goForward() {
        guard let target = forwardTarget, account(target) != nil else { return }
        editing = target
        forwardTarget = nil
    }

    private func open(_ id: String) {
        editing = id
        forwardTarget = nil
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if settings.credentials.accounts.isEmpty {
                        Text("No accounts yet. Add one to connect OpenBox, ShipBox, TaskBox or PRBox.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                    ForEach(settings.credentials.accounts) { account in
                        Button { open(account.id) } label: { row(account) }
                            .buttonStyle(.plain)
                    }
                }

                Section {
                    Text("Tokens are stored in your login keychain, not in Deck's settings file. That keeps them out of a file that gets copied around; it does not hide them from other software running as you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.top, 4)

            HStack {
                Spacer()
                Button("Add Account\u{2026}") { adding = true }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    private func row(_ account: CredentialAccount) -> some View {
        HStack(spacing: 10) {
            CredentialIcon(kind: account.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.label.isEmpty ? account.kind.displayName : account.label)
                Text(CredentialsCopy.rowSubtitle(
                    for: account,
                    among: settings.credentials.accounts,
                    usedBy: settings.slots(using: account.id)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if unavailableAccounts.contains(account.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            // Always last, always right: this row goes somewhere.
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - Detail

    private func detail(_ account: CredentialAccount) -> some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 10) {
                        CredentialIcon(kind: account.kind, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.verifiedIdentity ?? account.kind.displayName)
                            Text(CredentialsCopy.connectionSubtitle(for: account))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(verifying.contains(account.id) ? "Verifying\u{2026}" : "Verify\u{2026}") {
                            verify(account.id)
                        }
                        .disabled(
                            verifying.contains(account.id)
                                || CredentialsCopy.verifyHint(for: account) != nil
                        )
                    }
                    .padding(.vertical, 2)
                    caption(for: account)
                }

                Section("Account") {
                    TextField("Name", text: field(account.id, \.label))
                    switch account.kind {
                    case .azure:
                        TextField("Organization (name or dev.azure.com URL)",
                                  text: field(account.id, \.organization))
                        projectSlots(for: account)
                    case .opencode:
                        TextField("Server URL (opencode serve, e.g. http://host:4096)",
                                  text: field(account.id, \.serverURL))
                    case .github:
                        EmptyView()
                    }
                    AccountSecretField(
                        title: account.kind == .azure ? "Personal access token" : "Token",
                        accountID: account.id,
                        value: field(account.id, \.token),
                        onCommit: onSecretCommitted
                    )
                }

                Section("Used by") {
                    let slots = settings.slots(using: account.id)
                    if slots.isEmpty {
                        Text("No widget is using this account yet. Pick it on a widget's own tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(slots, id: \.self) { slot in
                            Label(slot.displayName, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.top, 4)

            HStack {
                Button("Delete Account\u{2026}", role: .destructive) { confirmingDelete = true }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .confirmationDialog(
            "Delete \u{201C}\(account.label.isEmpty ? account.kind.displayName : account.label)\u{201D}?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete(account) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CredentialsCopy.deleteMessage(
                label: account.label,
                slots: settings.slots(using: account.id)
            ))
        }
    }

    @ViewBuilder
    private func caption(for account: CredentialAccount) -> some View {
        if unavailableAccounts.contains(account.id) {
            Text("Deck could not read this token from the keychain this launch. It is still stored \u{2014} unlock your login keychain and reopen Deck.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let failure = failures[account.id] {
            Text(failure)
                .font(.caption)
                .foregroundStyle(.red)
        } else if let hint = CredentialsCopy.verifyHint(for: account) {
            // Not red: an account still being filled in is unfinished, not
            // broken. It names the field, and the field really is below.
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if account.verifiedIdentity != nil {
            Text(CredentialsCopy.verification(for: account))
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text(CredentialsCopy.verification(for: account))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editing

    /// Every credential edit goes through here so a verification can never
    /// outlive the token, organization or server it was made against.
    private func edit(_ id: String, _ body: (inout CredentialAccount) -> Void) {
        guard let index = settings.credentials.accounts.firstIndex(where: { $0.id == id }) else { return }
        let before = settings.credentials.accounts[index].credentialFingerprint
        body(&settings.credentials.accounts[index])
        settings.credentials.accounts[index].clearVerificationIfCredentialChanged(from: before)
        if settings.credentials.accounts[index].credentialFingerprint != before {
            failures[id] = nil
        }
    }

    /// Five project slots: pickers once discovery has answered, plain text
    /// fields until then.
    ///
    /// The fallback is not a nicety — a PAT scoped to Work Items (Read) may not
    /// be able to list projects, and being unable to *type* one would lock that
    /// user out of a widget their token can otherwise serve.
    @ViewBuilder
    private func projectSlots(for account: CredentialAccount) -> some View {
        let names = discovered[account.id]
        ForEach(0..<AzureAccountProjects.maxProjects, id: \.self) { slot in
            let title = slot == 0 ? "Project" : "Project \(slot + 1) (optional)"
            if let names, !names.isEmpty {
                Picker(title, selection: projectSlot(account.id, slot)) {
                    Text("None").tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                    // A stored project the PAT can no longer see would otherwise
                    // vanish from its own picker and silently reset to None.
                    let current = projectSlot(account.id, slot).wrappedValue
                    if !current.isEmpty, !names.contains(current) {
                        Text("\(current) (not found)").tag(current)
                    }
                }
            } else {
                TextField(title, text: projectSlot(account.id, slot))
            }
        }
        HStack {
            Button(discovering.contains(account.id) ? "Loading\u{2026}" : "Load projects") {
                loadProjects(for: account.id)
            }
            .disabled(
                discovering.contains(account.id)
                    || account.organization.trimmingCharacters(in: .whitespaces).isEmpty
                    || account.token.isEmpty
            )
            if let names, names.isEmpty {
                Text("This token can't see any project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Discovery is on demand and host-side only — never on the agent tick.
    private func loadProjects(for id: String) {
        guard let account = account(id) else { return }
        discovering.insert(id)
        Task { @MainActor in
            discovered[id] = try? await HostAzureProjectsLoader.list(
                organization: account.organization, token: account.token
            )
            discovering.remove(id)
        }
    }

    /// One of the five project slots, as a plain string binding.
    ///
    /// The value is stored exactly as typed — see `setSlot` for why
    /// normalising here would make a two-word project name untypeable.
    private func projectSlot(_ id: String, _ slot: Int) -> Binding<String> {
        Binding(
            get: {
                let projects = settings.credentials.accounts
                    .first(where: { $0.id == id })?.projects ?? []
                return slot < projects.count ? projects[slot] : ""
            },
            set: { value in
                edit(id) { account in
                    account.projects = AzureAccountProjects.setSlot(
                        slot, in: account.projects, to: value
                    )
                }
            }
        )
    }

    private func field(_ id: String, _ keyPath: WritableKeyPath<CredentialAccount, String>) -> Binding<String> {
        Binding(
            get: { settings.credentials.accounts.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in edit(id) { $0[keyPath: keyPath] = value } }
        )
    }

    /// A new account opens straight onto its own page — there is nothing to
    /// see for it in the list until it has a token.
    private func add(_ kind: CredentialKind) {
        let account = CredentialAccount(kind: kind, label: kind.displayName)
        settings.credentials.accounts.append(account)
        open(account.id)
    }

    /// Removes the record, its keychain item, and every selection pointing at
    /// it. Clearing the selections matters: a slot left dangling reads as
    /// "not configured" and keeps nagging, when what actually happened is that
    /// the user turned this off.
    private func delete(_ account: CredentialAccount) {
        for slot in settings.slots(using: account.id) {
            settings.setAccountID(nil, for: slot)
        }
        settings.credentials.accounts.removeAll { $0.id == account.id }
        DeckKeychain.delete(accountID: account.id)
        failures[account.id] = nil
        confirmingDelete = false
        editing = nil
        // Nothing to go forward to: the page Forward would return to is gone.
        forwardTarget = nil
    }

    // MARK: - Verify

    private func verify(_ id: String) {
        guard let account = account(id) else { return }
        verifying.insert(id)
        failures[id] = nil
        Task { @MainActor in
            do {
                let identity = try await CredentialVerifier.verify(account)
                if let index = settings.credentials.accounts.firstIndex(where: { $0.id == id }) {
                    settings.credentials.accounts[index].recordVerification(identity, at: Date())
                }
            } catch {
                failures[id] = Self.message(for: error)
            }
            verifying.remove(id)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case CredentialVerifier.VerifyError.notConfigured:
            return "This account is missing something Verify needs."
        case CredentialVerifier.VerifyError.serverError(let code) where code == 401 || code == 403:
            return "\(code) \u{2014} the token was rejected, or it lacks the scopes this needs."
        case CredentialVerifier.VerifyError.serverError(let code):
            return "The server answered \(code)."
        case CredentialVerifier.VerifyError.badResponse:
            return "The response was not what this provider normally sends."
        case CredentialVerifier.VerifyError.transport(let detail):
            return "Could not reach the server: \(detail)"
        default:
            return "Verification failed: \(error.localizedDescription)"
        }
    }
}

private struct OpenBoxSettingsView: View {
    @Binding var settings: OpenBoxSettings
    @Binding var accountID: String?
    let accounts: [CredentialAccount]
    var onManage: () -> Void = {}

    var body: some View {
        Form {
            Section("Remote server (optional)") {
                AccountPicker(kind: .opencode, accounts: accounts,
                              accountID: $accountID, onManage: onManage)
                Text("None = the local opencode database. Pick an account with a server URL to read a remote one instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(source: .opencodeRemote, clearOn: accountID ?? "")
            }
            Section("Chart") {
                Toggle("Show 14-day chart", isOn: $settings.showChart)
                Toggle("Cost-per-day chart (stacked by model)", isOn: $settings.showCostChart)
                    .disabled(!settings.showChart)
                ColorPicker("IN color", selection: $settings.inputColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("OUT color", selection: $settings.outputColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("COST color", selection: $settings.costColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Models") {
                Toggle("Show top models", isOn: $settings.showModels)
                Stepper("Models: \(settings.modelCount)", value: $settings.modelCount, in: 1...3)
                    .disabled(!settings.showModels)
            }
            Section("Tools") {
                Toggle("Show tool usage", isOn: $settings.showTools)
                Stepper("Tools: \(settings.toolCount)", value: $settings.toolCount, in: 1...3)
                    .disabled(!settings.showTools)
            }
            Section("Sessions") {
                Toggle("Show top sessions", isOn: $settings.showSessions)
                Stepper("Sessions: \(settings.sessionCount)", value: $settings.sessionCount, in: 1...5)
                    .disabled(!settings.showSessions)
                Text("Top sessions by tokens over the last 14 days (large widget only).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

}

private struct NetBoxSettingsView: View {
    @Binding var settings: NetBoxSettings
    @State private var interfaceOptions: [String] = []

    var body: some View {
        Form {
            Section("Interface") {
                Picker("Interface", selection: $settings.pinnedInterface) {
                    Text("Automatic (most active)").tag(String?.none)
                    ForEach(displayOptions, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
            }
            Section("Chart") {
                Toggle("Show chart", isOn: $settings.showChart)
                ColorPicker("UP color", selection: $settings.upColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("DOWN color", selection: $settings.downColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Thresholds") {
                Toggle("Show threshold colors", isOn: $settings.showThresholdColors)
                Stepper("Warn at: \(settings.warnThreshold) MB/s", value: $settings.warnThreshold, in: 1...2000)
                    .disabled(!settings.showThresholdColors)
                Stepper("Alarm at: \(settings.alarmThreshold) MB/s", value: $settings.alarmThreshold, in: 1...2000)
                    .disabled(!settings.showThresholdColors)
                Text("Rates at or above the warn threshold turn amber; at or above the alarm threshold, red. Alarm takes precedence when it is lower than Warn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Interfaces") {
                Toggle("Show interfaces", isOn: $settings.showInterfaces)
                Stepper("Interface count: \(settings.interfaceCount)", value: $settings.interfaceCount, in: 1...10)
                    .disabled(!settings.showInterfaces)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .onAppear(perform: refreshInterfaces)
    }

    private var displayOptions: [String] {
        if let pinned = settings.pinnedInterface, !interfaceOptions.contains(pinned) {
            return interfaceOptions + ["\(pinned) (offline)"]
        }
        return interfaceOptions
    }

    private func refreshInterfaces() {
        interfaceOptions = NetworkMetricsLoader.sample()
            .filter { $0.rxBytes + $0.txBytes > 0 }
            .map(\.name)
            .sorted()
    }
}

private struct BatBoxSettingsView: View {
    @Binding var settings: BatBoxSettings

    var body: some View {
        Form {
            Section("Chart") {
                Toggle("Show chart", isOn: $settings.showChart)
                ColorPicker("Level color", selection: $settings.levelColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Status") {
                Toggle("Show status", isOn: $settings.showStatus)
            }
            Section("Accessories") {
                Toggle("Show Bluetooth accessories", isOn: $settings.showAccessories)
                Stepper("Rows: \(settings.accessoryCount)", value: $settings.accessoryCount, in: 1...8)
                    .disabled(!settings.showAccessories)
                Text("Detected automatically. Each accessory uses its own low-battery threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

private struct GitBoxSettingsView: View {
    @Binding var settings: GitBoxSettings

    var body: some View {
        Form {
            Section("Repositories") {
                TextField("Repo paths (comma separated)", text: pathsBinding)
                Stepper("Scan depth: \(settings.scanDepth)", value: $settings.scanDepth, in: 1...5)
            }
            Section("Chart") {
                Toggle("Show chart", isOn: $settings.showChart)
                ColorPicker("Bar color", selection: $settings.barColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("Today color", selection: $settings.todayColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Repos list") {
                Toggle("Show repos", isOn: $settings.showRepos)
                Stepper("Repo count: \(settings.repoCount)", value: $settings.repoCount, in: 1...10)
                    .disabled(!settings.showRepos)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var pathsBinding: Binding<String> {
        Binding(
            get: { settings.repoPaths.joined(separator: ", ") },
            set: {
                settings.repoPaths = $0
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct DevBoxSettingsView: View {
    @Binding var settings: DevBoxSettings

    var body: some View {
        Form {
            Section("Ports") {
                Toggle("Show ports", isOn: $settings.showPorts)
                Stepper("Port count: \(settings.portCount)", value: $settings.portCount, in: 1...10)
                    .disabled(!settings.showPorts)
                ColorPicker("Port color", selection: $settings.portColor.color)
                    .disabled(!settings.showPorts)
            }
            Section("Containers") {
                Toggle("Show containers", isOn: $settings.showContainers)
                Stepper("Container count: \(settings.containerCount)", value: $settings.containerCount, in: 1...10)
                    .disabled(!settings.showContainers)
                ColorPicker("Container color", selection: $settings.containerColor.color)
                    .disabled(!settings.showContainers)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

private struct WeatherBoxSettingsView: View {
    @Binding var settings: WeatherBoxSettings

    var body: some View {
        Form {
            Section("Weather") {
                TextField("Location (city or lat,lon — empty = auto)", text: $settings.location)
                Picker("Units", selection: $settings.unitsFahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Show 3-day forecast", isOn: $settings.showForecast)
                FetchStatusCaption(source: .weather, clearOn: settings.location)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

private struct ClockBoxSettingsView: View {
    @Binding var settings: ClockBoxSettings

    var body: some View {
        Form {
            Section("Cities") {
                // One picker per slot rather than a drag-to-reorder list: slot
                // order *is* display order, so a plain indexed list keeps the
                // two in sync without a reorder affordance to maintain.
                ForEach(0..<ClockBoxCore.maxCities, id: \.self) { slot in
                    Picker("Clock \(slot + 1)", selection: cityBinding(slot: slot)) {
                        Text("None").tag("")
                        Text("Current location").tag(ClockBoxCore.localID)
                        Divider()
                        ForEach(ClockBoxCities.curated, id: \.id) { city in
                            Text(city.displayName).tag(city.id)
                        }
                    }
                }
            }
            Section("Main clock") {
                // Drives the small face only; medium and large follow slot
                // order, so ordering is how you choose what those show.
                Picker("Main clock", selection: $settings.mainCityID) {
                    Text("Auto (first non-local)").tag("")
                    ForEach(selectedCities, id: \.self) { id in
                        Text(ClockBoxCore.displayName(id: id)).tag(id)
                    }
                }
                Text("Shown on the small widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Display") {
                Toggle("Show relative day", isOn: $settings.showRelativeDay)
                Toggle("Show offset from your zone", isOn: $settings.showOffset)
                ColorPicker("Time color", selection: timeColorBinding, supportsOpacity: false)
                Text("Medium shows \(ClockBoxCore.mediumCapacity); large shows \(ClockBoxCore.largeCapacity).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var selectedCities: [String] {
        settings.cityIDs.filter { !$0.isEmpty }
    }

    /// Slots are positional: an empty pick clears that slot and the remaining
    /// cities close up, so the widget never renders a gap.
    private func cityBinding(slot: Int) -> Binding<String> {
        Binding(
            get: { slot < settings.cityIDs.count ? settings.cityIDs[slot] : "" },
            set: { newValue in
                var ids = settings.cityIDs
                while ids.count < ClockBoxCore.maxCities { ids.append("") }
                ids[slot] = newValue
                settings.cityIDs = ids.filter { !$0.isEmpty }
                // A main clock pointing at a city that is no longer selected
                // would silently fall back to auto; clear it so the picker
                // shows what the widget actually does.
                if !settings.mainCityID.isEmpty,
                   !settings.cityIDs.contains(settings.mainCityID) {
                    settings.mainCityID = ""
                }
            }
        )
    }

    private var timeColorBinding: Binding<Color> {
        Binding(
            get: { settings.timeColor.color },
            set: { settings.timeColor = RGBA($0) }
        )
    }
}

private struct ClipBoxSettingsView: View {
    @Binding var settings: ClipBoxSettings

    var body: some View {
        Form {
            Section("History") {
                Toggle("Show list", isOn: $settings.showList)
                Stepper("History count: \(settings.historyCount)", value: $settings.historyCount, in: 3...20)
                    .disabled(!settings.showList)
                Button("Clear history", role: .destructive) {
                    ClipBoxSnapshotStore.clear()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            Section("Colors") {
                ColorPicker("Text", selection: $settings.textColor.color)
                ColorPicker("Image", selection: $settings.imageColor.color)
                ColorPicker("File", selection: $settings.fileColor.color)
                ColorPicker("Other", selection: $settings.otherColor.color)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

/// Reports the last fetch failure for a source next to the fields that cause
/// it. The widget carries the terse chip; here there is room for the sentence.
///
/// The status is held in state and refreshed on a tick — reading the file from
/// `body` would hit the disk on every keystroke in a token field.
private struct FetchStatusCaption: View {
    let source: FetchSource
    /// The fetch inputs (token, repo, URL, location). When they change the
    /// caption clears: a stale reason must not accuse the user of a problem
    /// they may have just fixed. The next refresh re-records it if it still
    /// fails. Keyed on these fields only, so changing a color leaves it alone.
    let clearOn: String

    @State private var status: FetchStatus?

    /// Built once — a publisher recreated per body evaluation leaves a timer
    /// running per render.
    private static let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let status, let hint = FetchStatusCopy.hint(source: source, outcome: status.outcome) {
                Text("\(FetchStatusCopy.line(source: source, outcome: status.outcome) ?? "") · \(Self.timeFormatter.string(from: status.attemptedAt))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { status = FetchStatusStore.load(source) }
        .onReceive(Self.tick) { _ in status = FetchStatusStore.load(source) }
        .onChange(of: clearOn) { _ in status = nil }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct PRBoxSettingsView: View {
    @Binding var settings: PRBoxSettings
    let accounts: [CredentialAccount]
    var onManage: () -> Void = {}

    /// Deck's first per-provider sub-tab. A segmented picker inside the Form
    /// keeps it native and keeps the window at its existing size, where a real
    /// nested TabView would not.
    private enum Provider: String, CaseIterable, Identifiable {
        case github = "GitHub"
        case azure = "Azure DevOps"
        var id: String { rawValue }
    }

    @State private var provider: Provider = .github

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(Provider.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch provider {
            case .github: githubSection
            case .azure: azureSection
            }

            Section("Queue") {
                Toggle("Show list", isOn: $settings.showList)
                Stepper(
                    "PR count: \(settings.prCount)",
                    value: $settings.prCount,
                    in: PRBoxSettings.rowCountRange
                )
                .disabled(!settings.showList)
                Text("The count is for the large widget \u{2014} medium shows at most three rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Colors") {
                ColorPicker("Mine", selection: $settings.mineColor.color)
                ColorPicker("Review", selection: $settings.reviewColor.color)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var githubSection: some View {
        Section("GitHub") {
            // The picker replaced the Include toggle: an account selected is
            // this provider on, None is off. One control instead of two that
            // could disagree.
            AccountPicker(kind: .github, accounts: accounts,
                          accountID: $settings.github.accountID, onManage: onManage)
            TextField("Scope (optional)", text: $settings.github.scope, prompt: Text("org:acme"))
            Text("Without a scope this searches every repository the token can see, which can reach years back into personal repos. The token is sent only to api.github.com over TLS.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FetchStatusCaption(
                source: .prboxGitHub,
                clearOn: "\(settings.github.accountID ?? "")\u{0}\(settings.github.scope)"
            )
        }
    }

    private var azureSection: some View {
        Section("Azure DevOps") {
            AccountPicker(kind: .azure, accounts: accounts,
                          accountID: $settings.azure.accountID, onManage: onManage)
            Text("Shows pull requests created by, or awaiting review from, whoever owns the PAT \u{2014} not whoever is signed in to the browser. The token is sent only to dev.azure.com over TLS; a read-only PAT that can see Code is enough.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show project on rows", isOn: $settings.azure.showProject)
            Text("Prefixes each Azure row with its project. Worth turning on when the account covers several — a repository name is only unique within its project.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FetchStatusCaption(source: .prboxAzure, clearOn: settings.azure.accountID ?? "")
        }
    }
}

private struct ShipBoxSettingsView: View {
    @Binding var settings: ShipBoxSettings
    @Binding var accountID: String?
    let accounts: [CredentialAccount]
    /// The resolved token, for the repo inventory the static pickers offer.
    let token: String
    var onManage: () -> Void = {}

    /// The repos the token can see, fetched when the tab appears. Never
    /// persisted and never read by the agent — it exists only to fill the
    /// static pickers.
    @State private var inventory: [String] = []
    @State private var inventoryState: InventoryState = .idle

    private enum InventoryState: Equatable {
        case idle
        case loading
        case loaded
        case failed(FetchOutcome)
    }

    var body: some View {
        Form {
            // The account comes first because both modes need it and the
            // static picker cannot offer a single repo without a token — a tab
            // of five empty dropdowns above nothing reads as broken.
            Section("GitHub") {
                AccountPicker(kind: .github, accounts: accounts,
                              accountID: $accountID, onManage: onManage)
                Text("Required. The token is sent only to api.github.com over TLS; a token that can read Actions is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(
                    source: .shipbox,
                    clearOn: "\(settings.repoMode.rawValue)\u{0}\(settings.repos.joined(separator: ","))\u{0}\(accountID ?? "")"
                )
            }

            Section {
                Picker("Repos", selection: $settings.repoMode) {
                    Text("Automatic").tag(ShipBoxRepoMode.dynamic)
                    Text("Pick repos").tag(ShipBoxRepoMode.staticList)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch settings.repoMode {
            case .dynamic: dynamicSection
            case .staticList: staticSection
            }

            Section("Runs") {
                Toggle("Show runs list", isOn: $settings.showList)
                Stepper("Run count: \(settings.runCount)", value: $settings.runCount, in: 2...8)
                    .disabled(!settings.showList)
            }
            Section("Status colors") {
                ColorPicker("Queued", selection: $settings.queuedColor.color)
                ColorPicker("Running", selection: $settings.runningColor.color)
                ColorPicker("Success", selection: $settings.successColor.color)
                ColorPicker("Failure", selection: $settings.failureColor.color)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .task(id: token) { await loadInventory() }
    }

    private var dynamicSection: some View {
        Section("Automatic") {
            Stepper(
                "Repos to watch: \(settings.maxRepoCount)",
                value: $settings.maxRepoCount,
                in: 1...ShipBoxSettings.maxRepoCount
            )
            Text("Watches the repos you pushed to most recently that have any Actions runs. The set changes as you push \u{2014} push to something else and it takes a slot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var staticSection: some View {
        Section("Repos") {
            ForEach(0..<ShipBoxSettings.maxRepoCount, id: \.self) { slot in
                Picker("Repo \(slot + 1)", selection: repoBinding(slot: slot)) {
                    Text("None").tag("")
                    ForEach(inventory, id: \.self) { Text($0).tag($0) }
                    // A configured repo the inventory doesn't offer stays
                    // listed so it can be changed rather than silently lost.
                    ForEach(configuredNotInInventory, id: \.self) { Text($0).tag($0) }
                }
            }
            Text(staticCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Says why the pickers are empty, since an empty dropdown explains
    /// nothing on its own.
    private var staticCaption: String {
        if token.isEmpty {
            return "Pick an account above to load the repos you can choose from."
        }
        switch inventoryState {
        case .idle, .loading:
            return "Loading your repos\u{2026}"
        case .failed(let outcome):
            let reason = ShipBoxCopy.line(outcome: outcome, mode: .staticList) ?? "Couldn't load your repos"
            return "\(reason) \u{2014} the list below is only what's already configured."
        case .loaded:
            return inventory.isEmpty
                ? "This account has no repos to pick from."
                : "Slot order is display order. Clearing a slot closes the gap."
        }
    }

    private var configuredNotInInventory: [String] {
        settings.repos.filter { !inventory.contains($0) }
    }

    /// Slots are positional: an empty pick clears that slot and the remaining
    /// repos close up, so the widget never renders a gap.
    private func repoBinding(slot: Int) -> Binding<String> {
        Binding(
            get: { slot < settings.repos.count ? settings.repos[slot] : "" },
            set: { newValue in
                var repos = settings.repos
                while repos.count < ShipBoxSettings.maxRepoCount { repos.append("") }
                repos[slot] = newValue
                settings.repos = ShipBoxSettings.normalized(repos)
            }
        )
    }

    private func loadInventory() async {
        guard !token.isEmpty else {
            inventory = []
            inventoryState = .idle
            return
        }
        inventoryState = .loading
        do {
            inventory = try await HostGitHubLoader.repoInventory(token: token)
            inventoryState = .loaded
        } catch {
            inventory = []
            inventoryState = .failed(FetchClassifier.outcome(for: error))
        }
    }
}

private struct TaskBoxSettingsView: View {
    @Binding var settings: TaskBoxSettings
    @Binding var accountID: String?
    let accounts: [CredentialAccount]
    var onManage: () -> Void = {}

    var body: some View {
        Form {
            Section("Azure DevOps") {
                AccountPicker(kind: .azure, accounts: accounts,
                              accountID: $accountID, onManage: onManage)
                Text("The account carries the organization, up to five projects and the PAT. The token is sent only to dev.azure.com over TLS; a read-only Work Items (Read) PAT is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Shows open work items assigned to whoever owns the PAT \u{2014} not whoever is signed in to the browser or the az CLI \u{2014} across every project the account lists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(source: .taskbox, clearOn: accountID ?? "")
            }
            Section("Tasks") {
                Toggle("Show lane legend", isOn: $settings.showLegend)
                Toggle("Show task list", isOn: $settings.showList)
                Toggle("Show project on rows", isOn: $settings.showProject)
                    .disabled(!settings.showList)
                Stepper("Task count: \(settings.taskCount)", value: $settings.taskCount, in: 2...15)
                    .disabled(!settings.showList)
            }
            Section("Lanes") {
                TextField("To do states", text: $settings.stateMapping.todo)
                TextField("In progress states", text: $settings.stateMapping.inProgress)
                TextField("Testing states", text: $settings.stateMapping.testing)
                TextField("Done states", text: $settings.stateMapping.done)
                Text("Comma-separated, case-insensitive. Azure DevOps runs two vocabularies on one board \u{2014} tasks move To Do \u{2192} In Progress, while backlog items move New \u{2192} Approved \u{2192} Committed \u{2014} so these lists collapse both into the lanes shown on the widget. Only Done rows get a checkmark.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("A state in none of these lists is counted under OTHER, which only appears when something lands there. Nothing is ever dropped, so the legend always adds up to the tasks it describes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to defaults") { settings.stateMapping = TaskStateMapping() }
            }
            Section("Lane colors") {
                ColorPicker("To do", selection: $settings.todoColor.color)
                ColorPicker("In progress", selection: $settings.inProgressColor.color)
                ColorPicker("Testing", selection: $settings.testingColor.color)
                ColorPicker("Done", selection: $settings.doneColor.color)
                ColorPicker("Other", selection: $settings.otherColor.color)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

// MARK: - CalBox settings

private struct CalBoxSettingsView: View {
    @Binding var settings: CalBoxSettings

    @State private var choices: [CalendarChoice] = []
    @State private var accessGranted = true

    var body: some View {
        Form {
            Section("Calendars") {
                if !accessGranted {
                    Text("Deck can't read your calendars yet. Allow access when macOS asks, or turn it on in System Settings → Privacy & Security → Calendars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if choices.isEmpty {
                    Text("No calendars found. Add an account in System Settings → Internet Accounts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(groupedChoices, id: \.source) { group in
                    // Source titles ("Google", "iCloud") tell you which account
                    // a calendar came from — two accounts commonly hold a
                    // calendar of the same name.
                    Text(group.source.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    ForEach(group.calendars) { choice in
                        Toggle(isOn: binding(for: choice)) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(choice.color.color)
                                    .frame(width: 8, height: 8)
                                Text(choice.title)
                            }
                        }
                    }
                }
                Text("Read-only calendars — holidays, birthdays, subscriptions — start off, so their all-day entries don't crowd out your real events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Both Deck and its background agent need calendar access: they are separately signed, so macOS asks once for each.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(source: .calbox, clearOn: settings.calendarIDs.joined(separator: "\u{0}"))
            }
            Section("Today") {
                Toggle("Show today", isOn: $settings.showToday)
                Stepper("Events: \(settings.todayCount)", value: $settings.todayCount, in: 1...CalBoxSettings.maxCount)
                    .disabled(!settings.showToday)
                Toggle("Show all-day events", isOn: $settings.showAllDay)
                    .disabled(!settings.showToday)
            }
            Section("Tomorrow") {
                Toggle("Show tomorrow", isOn: $settings.showTomorrow)
                Stepper("Events: \(settings.tomorrowCount)", value: $settings.tomorrowCount, in: 1...CalBoxSettings.maxCount)
                    .disabled(!settings.showTomorrow)
            }
            Section {
                Text("Small and medium widgets show fewer rows than these counts — past that the rows would be clipped by the frame rather than by your setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Colors") {
                Toggle("Use each calendar's color", isOn: $settings.useCalendarColors)
                ColorPicker("Accent", selection: $settings.accentColor.color)
                    .disabled(settings.useCalendarColors)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .task { await load() }
    }

    private struct Group: Identifiable {
        var source: String
        var calendars: [CalendarChoice]
        var id: String { source }
    }

    private var groupedChoices: [Group] {
        Dictionary(grouping: choices, by: \.sourceTitle)
            .map { Group(source: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    private func binding(for choice: CalendarChoice) -> Binding<Bool> {
        Binding(
            get: { settings.calendarIDs.contains(choice.id) },
            set: { isOn in
                if isOn {
                    if !settings.calendarIDs.contains(choice.id) {
                        settings.calendarIDs.append(choice.id)
                    }
                } else {
                    settings.calendarIDs.removeAll { $0 == choice.id }
                }
                // Any deliberate change counts as having chosen, so unticking
                // everything is respected instead of being re-defaulted on at
                // the next launch.
                settings.hasChosenCalendars = true
            }
        )
    }

    /// Prompts for access (this is the in-context place to ask), lists the
    /// calendars, and applies the default selection exactly once.
    private func load() async {
        accessGranted = await HostCalendarLoader.requestAccess()
        guard accessGranted else { return }
        choices = HostCalendarLoader.calendars().sorted { $0.title < $1.title }
        guard !settings.hasChosenCalendars else { return }
        settings.calendarIDs = choices
            .filter { CalendarDefaults.shouldEnableByDefault(allowsContentModifications: $0.allowsContentModifications) }
            .map(\.id)
        settings.hasChosenCalendars = true
    }
}

private struct MarketBoxSettingsView: View {
    @Binding var settings: MarketBoxSettings

    var body: some View {
        Form {
            Section("Tickers") {
                // One picker per slot rather than free text: a symbol typed
                // blind is unknowable to the user. Slot order *is* display
                // order, so a plain indexed list keeps the two in sync.
                ForEach(0..<MarketBoxSettings.maxCount, id: \.self) { slot in
                    Picker("Ticker \(slot + 1)", selection: tickerBinding(slot: slot)) {
                        Text("None").tag("")
                        ForEach(pickableSymbols, id: \.self) { symbol in
                            Text(MarketSymbolResolver.pickerLabel(for: symbol)).tag(symbol)
                        }
                        // Symbols from an older free-text file stay visible so
                        // they can be changed, not silently lost.
                        ForEach(configuredSymbolsNotInPicker, id: \.self) { symbol in
                            Text(MarketSymbolResolver.pickerLabel(for: symbol)).tag(symbol)
                        }
                    }
                }
                Text("Crypto like BTC or ETH, fiat codes like USD or CAD, and GOLD for 1 gram of gold. Fiat and gold show price only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(source: .marketbox, clearOn: settings.tickers.joined(separator: ","))
            }
            Section("Display") {
                Picker("Display currency", selection: $settings.displayCurrency) {
                    ForEach(MarketCurrency.allCases, id: \.self) { currency in
                        Text(currency.label).tag(currency)
                    }
                }
                Text("Every row is priced in this currency. IRT (Toman) is the free-market rate, IRR is 10× Toman; CAD, EUR and AED convert at the live FX rate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Rows (large face): \(settings.tickerCount)", value: $settings.tickerCount, in: 1...MarketBoxSettings.maxCount)
                Toggle("Show day change", isOn: $settings.showDayChange)
            }
            Section("Colors") {
                ColorPicker("Up color", selection: $settings.upColor.color)
                ColorPicker("Down color", selection: $settings.downColor.color)
                ColorPicker("Accent color", selection: $settings.accentColor.color)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var pickableSymbols: [String] {
        MarketSymbolResolver.allPickableSymbols
    }

    /// A configured symbol the curated list does not offer (left over from a
    /// free-text file) is appended to the first picker that holds it, so it
    /// stays visible and changeable.
    private var configuredSymbolsNotInPicker: [String] {
        settings.tickers.filter { !pickableSymbols.contains($0) }
    }

    /// Slots are positional: an empty pick clears that slot and the remaining
    /// tickers close up, so the widget never renders a gap.
    private func tickerBinding(slot: Int) -> Binding<String> {
        Binding(
            get: { slot < settings.tickers.count ? settings.tickers[slot] : "" },
            set: { newValue in
                var tickers = settings.tickers
                while tickers.count < MarketBoxSettings.maxCount { tickers.append("") }
                tickers[slot] = newValue
                settings.tickers = MarketBoxSettings.normalized(tickers)
            }
        )
    }
}
