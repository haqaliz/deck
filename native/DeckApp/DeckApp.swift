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
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("Deck Widgets")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Same settings are available inside each widget (gear → flip).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Toggle("Refresh widgets in the background (launch at login)", isOn: $settings.agentAtLogin)

            TabView {
                LiveBoxSettingsView(settings: $settings.livebox)
                    .tabItem { Label("LiveBox", systemImage: "cpu") }
                OpenBoxSettingsView(settings: $settings.openbox)
                    .tabItem { Label("OpenBox", systemImage: "arrow.left.arrow.right") }
                NetBoxSettingsView(settings: $settings.netbox)
                    .tabItem { Label("NetBox", systemImage: "network") }
                BatBoxSettingsView(settings: $settings.batbox)
                    .tabItem { Label("BatBox", systemImage: "battery.50percent") }
                GitBoxSettingsView(settings: $settings.gitbox)
                    .tabItem { Label("GitBox", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
            .frame(height: 320)
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            installAgentIfNeeded()
            Task { await refreshOpenCode() }
            refreshProcesses()
            refreshGitBox()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { await refreshOpenCode() }
                refreshProcesses()
                refreshGitBox()
            }
            WidgetCenter.shared.reloadAllTimelines()
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
}

// MARK: - Full-size settings (also reachable from each widget's gear)

private struct LiveBoxSettingsView: View {
    @Binding var settings: LiveBoxSettings

    var body: some View {
        Form {
            Section("Chart") {
                Toggle("Show chart", isOn: $settings.showChart)
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
                ColorPicker("IN color", selection: $settings.inputColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("OUT color", selection: $settings.outputColor.color)
                    .disabled(!settings.showChart)
                ColorPicker("COST color", selection: $settings.costColor.color)
                    .disabled(!settings.showChart)
            }
            Section("Models") {
                Toggle("Show top models", isOn: $settings.showModels)
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
