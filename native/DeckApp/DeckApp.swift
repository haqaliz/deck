import SwiftUI
import WidgetKit
import AppKit

@main
struct DeckApp: App {
    var body: some Scene {
        WindowGroup("Deck") {
            ContentView()
        }
        .windowResizability(.contentSize)
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
            case .general: GeneralSettingsView(agentAtLogin: $settings.agentAtLogin)
            case .livebox: LiveBoxSettingsView(settings: $settings.livebox)
            case .openbox: OpenBoxSettingsView(settings: $settings.openbox)
            case .netbox: NetBoxSettingsView(settings: $settings.netbox)
            case .batbox: BatBoxSettingsView(settings: $settings.batbox)
            case .gitbox: GitBoxSettingsView(settings: $settings.gitbox)
            case .devbox: DevBoxSettingsView(settings: $settings.devbox)
            case .clipbox: ClipBoxSettingsView(settings: $settings.clipbox)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 640, height: 500)
        .onAppear {
            installAgentIfNeeded()
            Task { await refreshOpenCode() }
            refreshProcesses()
            refreshGitBox()
            refreshDevBox()
            refreshClipBox()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { await refreshOpenCode() }
                refreshProcesses()
                refreshGitBox()
                refreshDevBox()
                refreshClipBox()
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
    /// into the widget container.
    private func refreshOpenCode() async {
        let openbox = settings.openbox
        let snapshot: OpenCodeSnapshot?
        if let serverURL = openbox.serverURL, !serverURL.isEmpty, !openbox.token.isEmpty {
            snapshot = try? await RemoteOpenCodeLoader.load(serverURL: serverURL, token: openbox.token)
        } else {
            snapshot = OpenCodeReader.load()
        }
        guard let snapshot else { return }
        if snapshot != OpenCodeSnapshotStore.load() {
            OpenCodeSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Sample top processes (host is unsandboxed) and push them into the
    /// widget container for the LiveBox process list.
    private func refreshProcesses() {
        let snapshot = ProcessSnapshot(writtenAt: Date(), processes: HostProcessSampler.top(limit: 10))
        if snapshot != ProcessSnapshotStore.load() {
            ProcessSnapshotStore.save(snapshot)
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

    private var agentInterval: Int {
        60
    }

    private func installAgentIfNeeded() {
        let plist = agentPlistURL
        try? FileManager.default.createDirectory(
            at: plist.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.deck.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Applications/Deck.app/Contents/MacOS/DeckAgent</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>\(agentInterval)</integer>
            <key>StandardOutPath</key>
            <string>/tmp/deck-agent.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/deck-agent.log</string>
        </dict>
        </plist>
        """
        try? content.write(to: plist, atomically: true, encoding: .utf8)
        bootstrapAgent()
    }

    private func bootstrapAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(getuid())", agentPlistURL.path]
        try? process.run()
    }

    private func removeAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/com.deck.agent"]
        try? process.run()
        try? FileManager.default.removeItem(at: agentPlistURL)
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

// MARK: - Sidebar selection

private enum DeckWidget: String, CaseIterable, Identifiable {
    case general, livebox, openbox, netbox, batbox, gitbox, devbox, clipbox

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
        }
    }
}

// MARK: - Full-size settings (also reachable from each widget's gear)

private struct GeneralSettingsView: View {
    @Binding var agentAtLogin: Bool

    var body: some View {
        Form {
            Section("Background refresh") {
                Toggle("Refresh in background (launch at login)", isOn: $agentAtLogin)
                Text("Runs the Deck agent at login to keep widget data fresh even when the app is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
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
            }
            Section("Processes") {
                Toggle("Show top processes", isOn: $settings.showProcesses)
                Stepper("Process count: \(settings.processCount)", value: $settings.processCount, in: 1...20)
                    .disabled(!settings.showProcesses)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

private struct OpenBoxSettingsView: View {
    @Binding var settings: OpenBoxSettings

    var body: some View {
        Form {
            Section("Remote server (optional)") {
                SecureField("Token", text: $settings.token)
                TextField("Server URL (opencode serve)", text: serverURLBinding)
                Stepper("Refresh interval: \(settings.refreshInterval) s", value: $settings.refreshInterval, in: 5...60, step: 5)
                Text("Empty URL = local opencode database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    var body: some View {
        Form {
            Section("Chart") {
                Toggle("Show chart", isOn: $settings.showChart)
                ColorPicker("UP color", selection: $settings.upColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("DOWN color", selection: $settings.downColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Interfaces") {
                Toggle("Show interfaces", isOn: $settings.showInterfaces)
                Stepper("Interface count: \(settings.interfaceCount)", value: $settings.interfaceCount, in: 1...10)
                    .disabled(!settings.showInterfaces)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
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
                TextField("Repo paths (comma separated, ~/dev default)", text: pathsBinding)
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
