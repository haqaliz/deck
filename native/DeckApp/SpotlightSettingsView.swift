import SwiftUI
import AppKit

// MARK: - Runtime hand-off
//
// The settings view and the app delegate share no state (the delegate outlives
// the window). These carry the two facts the view cannot compute itself.

extension Notification.Name {
    /// `object` is a Bool: the recorder is listening, so the global shortcut
    /// must be released (pressing the current combination would otherwise
    /// toggle the panel instead of being recorded).
    static let deckShortcutRecording = Notification.Name("com.deck.shortcutRecording")
    /// `object` is the Carbon status of the latest registration (Int32).
    static let deckShortcutStatus = Notification.Name("com.deck.shortcutStatus")
}

@MainActor
enum SpotlightRuntime {
    static var trayReady = false
    static var shortcutStatus: Int32 = 0
}

// MARK: - Settings tab

struct SpotlightSettingsView: View {
    @Binding var settings: SpotlightSettings

    @State private var examplesFor: SearchProviderID?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var shortcutStatus: Int32 = SpotlightRuntime.shortcutStatus

    var body: some View {
        // Examples are a page of their own inside Settings, not a dialog over
        // it: opening one replaces this tab's content, and Back (or Esc)
        // returns to the list.
        ZStack {
            if let provider = examplesFor {
                SearchExamplesPage(provider: provider) {
                    withAnimation(.easeInOut(duration: 0.2)) { examplesFor = nil }
                }
                .transition(.move(edge: .trailing))
            } else {
                listPage
                    .transition(.move(edge: .leading))
            }
        }
        .clipped()
    }

    private var listPage: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Open search")
                    Spacer()
                    Button(recording ? "Press a shortcut…" : ShortcutFormat.display(
                        keyCode: settings.shortcutKeyCode, modifiers: settings.shortcutModifiers
                    )) { toggleRecording() }
                    .buttonStyle(.bordered)
                    .help("Click, then press the new combination. Esc cancels.")
                    if settings.shortcutKeyCode != SpotlightSettings.defaultKeyCode
                        || settings.shortcutModifiers != SpotlightSettings.defaultModifiers {
                        Button("Reset") {
                            settings.shortcutKeyCode = SpotlightSettings.defaultKeyCode
                            settings.shortcutModifiers = SpotlightSettings.defaultModifiers
                        }
                        .buttonStyle(.link)
                    }
                }
                if let message = ShortcutRegistrationCopy.message(status: shortcutStatus) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(ShortcutRegistrationCopy.silentConflictNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Search in") {
                ForEach(SearchProviderID.allCases) { provider in
                    sourceRow(provider, isOn: binding(for: provider), note: Self.note(for: provider))
                }
                Text("Without a prefix, the local sources and work items answer. Pull requests, Commits and Markets only search when you start with their prefix: pr, commit or mkt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .onAppear {
            shortcutStatus = SpotlightRuntime.shortcutStatus
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: .deckShortcutStatus)) { note in
            if let status = note.object as? Int32 { shortcutStatus = status }
        }
    }

    private func binding(for provider: SearchProviderID) -> Binding<Bool> {
        switch provider {
        case .clip: $settings.clipEnabled
        case .port: $settings.portEnabled
        case .time: $settings.timeEnabled
        case .oc: $settings.ocEnabled
        case .run: $settings.runEnabled
        case .task: $settings.taskEnabled
        case .pr: $settings.prEnabled
        case .commit: $settings.commitEnabled
        case .event: $settings.eventEnabled
        case .market: $settings.marketEnabled
        }
    }

    /// The caveat under each source: what it needs, what it does not cover.
    private static func note(for provider: SearchProviderID) -> String? {
        switch provider {
        case .clip:
            "Off by default: copied text would appear in the search panel, which can be on screen while you share it. Needs ClipBox history."
        case .oc:
            "Recent sessions only, not the full history."
        case .run:
            "Recent builds only: the runs ShipBox already holds. Needs ShipBox set up."
        case .task:
            "Needs an account chosen in TaskBox. Searches every project on it, closed items included, and finds bugs, backlog items, epics, features and tasks."
        case .pr:
            "Needs an account chosen in PRBox. GitHub: pull requests you are involved in, or PRBox's scope if you set one. Azure DevOps: each project's 100 most recent. A number finds recent pull requests only."
        case .commit:
            "Searches the repositories GitBox scans; add some in the GitBox settings. Runs on this Mac."
        case .event:
            "Off by default: event titles would appear in the panel, which can be on screen while you share it. macOS asks for calendar access the first time. Reads the calendars CalBox uses."
        case .market:
            "Needs no account. Shares CoinGecko's and Yahoo's public limits with the MarketBox widget, so it only searches after the mkt prefix."
        case .port, .time:
            nil
        }
    }

    /// One source: its switch, an example search to try, what the example finds
    /// and what Enter does, and any caveat. The example comes from the same
    /// model the panel uses, so what is shown here is what the panel accepts.
    private func sourceRow(_ provider: SearchProviderID, isOn: Binding<Bool>, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(provider.settingsTitle, isOn: isOn)
            HStack(spacing: 6) {
                Text("Try")
                    .foregroundStyle(.secondary)
                Text(provider.exampleQuery)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.caption)
            Text(provider.exampleSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("More examples (\(provider.examples.count))") {
                withAnimation(.easeInOut(duration: 0.2)) { examplesFor = provider }
            }
                .buttonStyle(.link)
                .font(.caption)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Recorder

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        NotificationCenter.default.post(name: .deckShortcutRecording, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc cancels
                stopRecording()
                return nil
            }
            let mods = ShortcutFormat.usableModifiers(carbonModifiers(from: event.modifierFlags))
            guard ShortcutFormat.isRecordable(modifiers: mods) else { return nil }  // wait for a modifier
            settings.shortcutKeyCode = Int(event.keyCode)
            settings.shortcutModifiers = mods
            stopRecording()
            return nil
        }
    }

    /// Always tells the delegate to take the shortcut back. A cancelled
    /// recording changes no setting, so nothing else would re-register what
    /// `startRecording` released; after a successful one the settings save
    /// registers the new combination right behind this.
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        NotificationCenter.default.post(name: .deckShortcutRecording, object: false)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= 256 }
        if flags.contains(.shift) { m |= 512 }
        if flags.contains(.option) { m |= 2048 }
        if flags.contains(.control) { m |= 4096 }
        return m
    }
}

// MARK: - Menu bar section (lives in General)

/// Tray-only mode and Deck's own login item. They are about how the app
/// itself runs, not about search, so they sit in General beside "Refresh in
/// background". Reads the OS for the login state each time it appears — never
/// `settings.json` — because the user can change it in Login Items.
struct MenuBarSettingsSection: View {
    @Binding var settings: SpotlightSettings

    @State private var login: LoginItemState = MainAppLoginItem.state
    @State private var loginError: String?

    var body: some View {
        Section("Menu bar") {
            Toggle("Keep Deck in the menu bar only", isOn: $settings.keepInTrayOnly)
                .disabled(!SpotlightRuntime.trayReady && !settings.keepInTrayOnly)
            Text("Hides the Dock icon while the settings window is closed. Deck keeps running from the menu bar, so the search shortcut keeps working. Quit Deck from the menu bar item.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Open Deck at login", isOn: loginBinding)
                .disabled(!login.canToggle)
            Text("The search shortcut only works while Deck is running. This is separate from “Refresh in background”, which keeps widget data fresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let note = loginError ?? login.note {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { login = MainAppLoginItem.state }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { login.toggleIsOn },
            set: { on in
                let result = MainAppLoginItem.set(on)
                login = result.state
                loginError = result.error
                settings.openAtLogin = result.state.toggleIsOn
            }
        )
    }
}


// MARK: - More examples

extension SearchProviderID: Identifiable {
    var id: String { rawValue }
}

/// One source's examples as a page of Settings: the search to type, and what it
/// finds. Opened from "More examples" under each source's toggle; Back returns
/// to the Spotlight list.
struct SearchExamplesPage: View {
    let provider: SearchProviderID
    let onBack: () -> Void

    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Label("Spotlight", systemImage: "chevron.left")
                }
                .buttonStyle(.link)
                .keyboardShortcut(.cancelAction)  // Esc goes back too
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.settingsTitle)
                    .font(.title2.weight(.semibold))
                Text("Open search with your shortcut and type any of these.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(provider.examples, id: \.query) { example in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(example.query)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                                Text(example.summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Button(copied == example.query ? "Copied" : "Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(example.query, forType: .string)
                                copied = example.query
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}
