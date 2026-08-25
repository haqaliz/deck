import SwiftUI
import WidgetKit
import AppKit

@main
struct DeckApp: App {
    @NSApplicationDelegateAdaptor(DeckAppDelegate.self) private var appDelegate

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
    @State private var settings = DeckSettings.load()
    @State private var selection: DeckWidget = .livebox
    @State private var timer: Timer?
    @State private var toolbarSweepTimer: Timer?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(DeckWidget.general)
                Section("Widgets") {
                    ForEach(DeckWidget.allCases.filter { $0 != .general }) { widget in
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
                onRemoveAgents: uninstallAgents,
                onEraseData: eraseDeckData
            )
            case .livebox: LiveBoxSettingsView(settings: $settings.livebox)
            case .openbox: OpenBoxSettingsView(settings: $settings.openbox)
            case .netbox: NetBoxSettingsView(settings: $settings.netbox)
            case .batbox: BatBoxSettingsView(settings: $settings.batbox)
            case .gitbox: GitBoxSettingsView(settings: $settings.gitbox)
            case .devbox: DevBoxSettingsView(settings: $settings.devbox)
            case .clipbox: ClipBoxSettingsView(settings: $settings.clipbox)
            case .weatherbox: WeatherBoxSettingsView(settings: $settings.weatherbox)
            case .clockbox: ClockBoxSettingsView(settings: $settings.clockbox)
            case .shipbox: ShipBoxSettingsView(settings: $settings.shipbox)
            case .taskbox: TaskBoxSettingsView(settings: $settings.taskbox)
            case .calbox: CalBoxSettingsView(settings: $settings.calbox)
            case .prbox: PRBoxSettingsView(settings: $settings.prbox)
            case .marketbox: MarketBoxSettingsView(settings: $settings.marketbox)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 640, height: 500)
        .onAppear {
            DeckSettings.tightenPermissions()
            installAgentIfNeeded()
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
            applyAgent()
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
        let openbox = settings.openbox
        let snapshot: OpenCodeSnapshot?
        if let serverURL = openbox.serverURL, !serverURL.isEmpty {
            if !openbox.token.isEmpty {
                do {
                    snapshot = try await RemoteOpenCodeLoader.load(serverURL: serverURL, token: openbox.token)
                    FetchStatusStore.record(.ok, for: .opencodeRemote)
                } catch {
                    snapshot = nil
                    FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .opencodeRemote)
                }
            } else {
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
        guard prbox.isAnyProviderUsable else {
            FetchStatusStore.record(prbox.github.enabled ? .notConfigured : .ok, for: .prboxGitHub)
            FetchStatusStore.record(prbox.azure.enabled ? .notConfigured : .ok, for: .prboxAzure)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        var github: PRRoleTotals?
        if prbox.github.isUsable {
            do {
                github = try await HostGitHubPRLoader.fetch(
                    token: prbox.github.token,
                    scope: prbox.github.scope,
                    cap: prbox.prCount
                )
                FetchStatusStore.record(.ok, for: .prboxGitHub)
            } catch {
                FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .prboxGitHub)
            }
        } else {
            FetchStatusStore.record(prbox.github.enabled ? .notConfigured : .ok, for: .prboxGitHub)
        }

        var azure: PRRoleTotals?
        if prbox.azure.isUsable {
            do {
                azure = try await HostAzurePRLoader.fetch(
                    organization: prbox.azure.organization,
                    project: prbox.azure.project,
                    token: prbox.azure.token,
                    cap: prbox.prCount
                )
                FetchStatusStore.record(.ok, for: .prboxAzure)
            } catch {
                FetchStatusStore.record(FetchClassifier.outcome(for: error), for: .prboxAzure)
            }
        } else {
            FetchStatusStore.record(prbox.azure.enabled ? .notConfigured : .ok, for: .prboxAzure)
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
        let configured = !shipbox.token.isEmpty
            && (shipbox.repoMode == .dynamic || !shipbox.repos.isEmpty)
        guard configured else {
            FetchStatusStore.record(.notConfigured, for: .shipbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot: ShipBoxSnapshot
        do {
            snapshot = try await HostGitHubLoader.fetch(settings: shipbox)
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
        let taskbox = settings.taskbox
        let organization = taskbox.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = taskbox.project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organization.isEmpty, !project.isEmpty, !taskbox.token.isEmpty else {
            FetchStatusStore.record(.notConfigured, for: .taskbox)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot: TaskBoxSnapshot
        do {
            snapshot = try await HostAzureDevOpsLoader.fetch(
                organization: organization, project: project, token: taskbox.token
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
            installAgentIfNeeded()
        } else {
            removeAgent()
        }
    }

    private var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.deck.agent.plist")
    }

    private var processAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.deck.agent.processes.plist")
    }

    private var agentInterval: Int {
        60
    }

    /// Agent logs. Not `/tmp`: that directory is world-writable, so any local
    /// process could pre-create the predictable path and have launchd append
    /// the agent's output to a file it controls.
    private var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Deck")
    }

    private func installAgentIfNeeded() {
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        installAgent(
            plistURL: agentPlistURL,
            label: "com.deck.agent",
            interval: agentInterval,
            extraArguments: [],
            logPath: logDirectory.appendingPathComponent("agent.log").path,
            restartIfChanged: false
        )
        installAgent(
            plistURL: processAgentPlistURL,
            label: "com.deck.agent.processes",
            interval: settings.livebox.processRefreshInterval,
            extraArguments: ["--processes"],
            logPath: logDirectory.appendingPathComponent("agent-processes.log").path,
            restartIfChanged: true
        )
    }

    private func installAgent(plistURL: URL, label: String, interval: Int, extraArguments: [String], logPath: String, restartIfChanged: Bool) {
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // A rewritten plist does not affect a job launchd already loaded, so
        // reload when anything in it actually changed — including the log path,
        // which is how installs predating ~/Library/Logs/Deck migrate off /tmp.
        let intervalChanged = restartIfChanged && currentStartInterval(of: plistURL) != interval
        if intervalChanged || currentLogPath(of: plistURL) != logPath {
            runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        }
        let args = (["/Applications/Deck.app/Contents/MacOS/DeckAgent"] + extraArguments)
            .map { "<string>\($0)</string>" }
            .joined(separator: "\n")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(args)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>\(interval)</integer>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """
        try? content.write(to: plistURL, atomically: true, encoding: .utf8)
        runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private func currentLogPath(of plistURL: URL) -> String? {
        plistValue(of: plistURL)?["StandardOutPath"] as? String
    }

    private func plistValue(of plistURL: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    private func currentStartInterval(of plistURL: URL) -> Int? {
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any]
        else { return nil }
        return dict["StartInterval"] as? Int
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
    }

    /// Uninstall: stop and forget both LaunchAgents. Also clears the toggle so
    /// the next settings change does not quietly reinstall them.
    private func uninstallAgents() {
        settings.agentAtLogin = false
        removeAgent()
    }

    /// Uninstall: delete Deck's data directory inside the widget container.
    ///
    /// This removes the *contents* Deck owns — settings.json, every snapshot,
    /// the clipboard history and the saved tokens. It deliberately does not
    /// touch the container itself: that directory's metadata plist is
    /// SIP-protected and survives deletion, after which containermanagerd
    /// never rebuilds the skeleton and every widget renders blank forever.
    private func eraseDeckData() {
        uninstallAgents()
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

    private func removeAgent() {
        runLaunchctl(["bootout", "gui/\(getuid())/com.deck.agent"])
        runLaunchctl(["bootout", "gui/\(getuid())/com.deck.agent.processes"])
        try? FileManager.default.removeItem(at: agentPlistURL)
        try? FileManager.default.removeItem(at: processAgentPlistURL)
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
    case general, livebox, openbox, netbox, batbox, gitbox, devbox, clipbox
    case weatherbox, clockbox, shipbox, taskbox, calbox, prbox, marketbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
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
    var onRemoveAgents: () -> Void
    var onEraseData: () -> Void

    @State private var confirmingErase = false
    @State private var agentsRemoved = false

    var body: some View {
        Form {
            Section("Background refresh") {
                Toggle("Refresh in background (launch at login)", isOn: $agentAtLogin)
                Text("Runs the Deck agent at login to keep widget data fresh even when the app is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Deck installs two LaunchAgents on first run. Leaving the only
            // removal path in the README as four terminal commands is not a
            // fair deal for something that starts itself at login.
            Section("Uninstall") {
                Button("Remove background agents") {
                    onRemoveAgents()
                    agentsRemoved = true
                }
                Text(agentsRemoved
                     ? "Removed. Widgets keep their last data but stop refreshing."
                     : "Stops com.deck.agent and com.deck.agent.processes and deletes their LaunchAgent files.")
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

private struct OpenBoxSettingsView: View {
    @Binding var settings: OpenBoxSettings

    var body: some View {
        Form {
            Section("Remote server (optional)") {
                SecureField("Token", text: $settings.token)
                    .textContentType(.password)
                TextField("Server URL (opencode serve, e.g. http://host:4096)", text: serverURLBinding)
                Text("Empty URL = local opencode database. A configured URL works only with your own token pasted above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(source: .opencodeRemote, clearOn: "\(settings.serverURL ?? "")\u{0}\(settings.token)")
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

    private var serverURLBinding: Binding<String> {
        Binding(
            get: { settings.serverURL ?? "" },
            set: { settings.serverURL = $0.isEmpty ? nil : $0 }
        )
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
            Toggle("Include GitHub", isOn: $settings.github.enabled)
            SecureField("Personal access token", text: $settings.github.token)
                .textContentType(.password)
            TextField("Scope (optional)", text: $settings.github.scope, prompt: Text("org:acme"))
            Text("Without a scope this searches every repository the token can see, which can reach years back into personal repos. The token is sent only to api.github.com over TLS.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FetchStatusCaption(
                source: .prboxGitHub,
                clearOn: "\(settings.github.enabled)\u{0}\(settings.github.token)\u{0}\(settings.github.scope)"
            )
        }
    }

    private var azureSection: some View {
        Section("Azure DevOps") {
            Toggle("Include Azure DevOps", isOn: $settings.azure.enabled)
            TextField("Organization", text: $settings.azure.organization)
            TextField("Project", text: $settings.azure.project)
            SecureField("Personal access token", text: $settings.azure.token)
                .textContentType(.password)
            Text("Shows pull requests created by, or awaiting review from, whoever owns the PAT \u{2014} not whoever is signed in to the browser. The token is sent only to dev.azure.com over TLS; a read-only PAT that can see Code is enough.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FetchStatusCaption(
                source: .prboxAzure,
                clearOn: "\(settings.azure.enabled)\u{0}\(settings.azure.organization)\u{0}\(settings.azure.project)\u{0}\(settings.azure.token)"
            )
        }
    }
}

private struct ShipBoxSettingsView: View {
    @Binding var settings: ShipBoxSettings

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
            // The token comes first because both modes need it and the static
            // picker cannot offer a single repo without it — a tab of five
            // empty dropdowns above the field that fills them reads as broken.
            Section("GitHub") {
                SecureField("GitHub token", text: $settings.token)
                    .textContentType(.password)
                Text("Required. The token is sent only to api.github.com over TLS; a token that can read Actions is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(
                    source: .shipbox,
                    clearOn: "\(settings.repoMode.rawValue)\u{0}\(settings.repos.joined(separator: ","))\u{0}\(settings.token)"
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
        .task(id: settings.token) { await loadInventory() }
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
        if settings.token.isEmpty {
            return "Add a token above to load the repos you can pick from."
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
        guard !settings.token.isEmpty else {
            inventory = []
            inventoryState = .idle
            return
        }
        inventoryState = .loading
        do {
            inventory = try await HostGitHubLoader.repoInventory(token: settings.token)
            inventoryState = .loaded
        } catch {
            inventory = []
            inventoryState = .failed(FetchClassifier.outcome(for: error))
        }
    }
}

private struct TaskBoxSettingsView: View {
    @Binding var settings: TaskBoxSettings

    var body: some View {
        Form {
            Section("Azure DevOps") {
                TextField("Organization", text: $settings.organization)
                TextField("Project", text: $settings.project)
                SecureField("Personal access token", text: $settings.token)
                    .textContentType(.password)
                Text("Empty organization, project or token = the widget shows no data. The token is sent only to dev.azure.com over TLS; a read-only Work Items (Read) PAT is enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Shows open work items assigned to whoever owns the PAT \u{2014} not whoever is signed in to the browser or the az CLI \u{2014} in the project above only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FetchStatusCaption(
                    source: .taskbox,
                    clearOn: "\(settings.organization)\u{0}\(settings.project)\u{0}\(settings.token)"
                )
            }
            Section("Tasks") {
                Toggle("Show lane legend", isOn: $settings.showLegend)
                Toggle("Show task list", isOn: $settings.showList)
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
