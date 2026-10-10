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

    @State private var recording = false
    @State private var monitor: Any?
    @State private var shortcutStatus: Int32 = SpotlightRuntime.shortcutStatus

    var body: some View {
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
                sourceRow(.clip, isOn: $settings.clipEnabled,
                          note: "Off by default: copied text would appear in the search panel, which can be on screen while you share it. Needs ClipBox history.")
                sourceRow(.port, isOn: $settings.portEnabled)
                sourceRow(.time, isOn: $settings.timeEnabled)
                sourceRow(.oc, isOn: $settings.ocEnabled,
                          note: "Recent sessions only, not the full history.")
                sourceRow(.task, isOn: $settings.taskEnabled,
                          note: "Does nothing until an account is chosen in TaskBox. Searches every project on that account, including closed items.")
                Text("With no prefix, every source above answers. A prefix searches just that one.")
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
