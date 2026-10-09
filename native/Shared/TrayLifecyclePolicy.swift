import Foundation

// MARK: - Tray lifecycle policy
//
// Every quit and Dock-icon decision the resident tray makes, as pure
// functions. The app delegate asks and applies; it decides nothing itself,
// which is what keeps the lifecycle — the part of Deck where CLAUDE.md records
// the most traps — testable without launching an app.

/// Why the app is being asked to terminate (or has lost its last window).
enum QuitReason: Equatable {
    /// "Quit" in the menu-bar item's menu.
    case trayQuit
    /// Command-Q while the settings window is frontmost.
    case settingsCmdQ
    /// "Quit" in the Dock icon's menu.
    case dockQuit
    /// The settings window was closed.
    case lastWindowClosed
    /// Logout, restart or shutdown.
    case system
}

/// What the app looks like to the OS. Mirrors `NSApplication.ActivationPolicy`
/// without importing AppKit into `Shared`.
enum DockPresence: Equatable {
    /// A normal app: Dock icon, menu bar.
    case regular
    /// No Dock icon. The tray item is the only way back in.
    case accessory
}

enum TrayLifecyclePolicy {
    /// Explicit quits and system shutdown always terminate — a resident app
    /// must never veto a logout. Closing the window never does: that is how
    /// Deck already behaves, and in tray-only mode it is the whole feature.
    static func shouldTerminate(reason: QuitReason, keepInTrayOnly: Bool) -> Bool {
        switch reason {
        case .trayQuit, .settingsCmdQ, .dockQuit, .system: true
        case .lastWindowClosed: false
        }
    }

    /// The Dock icon is hidden only when the user asked for tray-only, the
    /// status item actually exists, and no settings window is open. Without a
    /// tray there would be no way back into a Deck with no Dock icon and no
    /// window, so a missing status item keeps Deck a normal app.
    static func activationPolicy(
        trayReady: Bool,
        keepInTrayOnly: Bool,
        settingsWindowOpen: Bool
    ) -> DockPresence {
        keepInTrayOnly && trayReady && !settingsWindowOpen ? .accessory : .regular
    }

    static func canEnableTrayOnly(trayReady: Bool) -> Bool {
        trayReady
    }

    /// A Deck launched only to carry a widget click still gets out of the way
    /// once the page is open. One that was already running — tray or window —
    /// must not be quit by someone clicking a widget. Quitting from the tray is
    /// the explicit exit, so a click after that is a fresh, cold launch.
    static func quitsAfterForwardingURL(alreadyRunning: Bool) -> Bool {
        !alreadyRunning
    }
}

// MARK: - Shortcut registration copy

/// The sentence the Spotlight settings tab shows when registering the global
/// shortcut fails. A failure there is otherwise invisible: the shortcut just
/// does nothing.
enum ShortcutRegistrationCopy {
    /// `eventHotKeyExistsErr`, measured in the phase 0 probe by registering one
    /// combination twice.
    private static let alreadyRegistered: Int32 = -9878

    /// `nil` on success (`noErr`).
    static func message(status: Int32) -> String? {
        switch status {
        case 0:
            return nil
        case alreadyRegistered:
            return "That shortcut is already in use by another app. Choose a different one."
        default:
            return "Couldn't register the shortcut (error \(status)). Try a different one."
        }
    }
}
