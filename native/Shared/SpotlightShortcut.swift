import Foundation

// MARK: - Shortcut display
//
// The settings tab words a recorded shortcut ("⌥Space") and the state of
// Deck's own login item. Both are pure so the view stays layout.
//
// Modifier values are Carbon's mask (cmdKey 256, shiftKey 512, optionKey 2048,
// controlKey 4096), the same numbers `SpotlightSettings` stores.

enum ShortcutFormat {
    static let usableMask = 256 | 512 | 2048 | 4096

    /// Drops the bits `NSEvent` flags carry that a global hotkey cannot use —
    /// caps lock, fn, the numeric-pad marker.
    static func usableModifiers(_ modifiers: Int) -> Int {
        modifiers & usableMask
    }

    /// A shortcut with no modifier would swallow ordinary typing system-wide.
    static func isRecordable(modifiers: Int) -> Bool {
        usableModifiers(modifiers) != 0
    }

    /// Glyphs in the order macOS prints them: control, option, shift, command.
    static func display(keyCode: Int, modifiers: Int) -> String {
        var out = ""
        if modifiers & 4096 != 0 { out += "⌃" }
        if modifiers & 2048 != 0 { out += "⌥" }
        if modifiers & 512 != 0 { out += "⇧" }
        if modifiers & 256 != 0 { out += "⌘" }
        return out + (keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// US ANSI virtual key codes (`kVK_*`). Anything else renders as
    /// "Key N" rather than as nothing.
    private static let keyNames: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",",
        47: ".", 44: "/", 50: "`",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

// MARK: - Login item state

/// Deck.app's own login registration (`SMAppService.mainApp`), kept apart from
/// the two background agents, which have their own toggle.
enum LoginItemState: Equatable {
    case off
    case on
    /// Registered, but switched off by the user in System Settings → General →
    /// Login Items. A veto is `.requiresApproval`, not `.notRegistered`
    /// (CLAUDE.md) — Deck did register, someone else said no.
    case needsApproval
    case unavailable

    /// `SMAppService.Status` raw values: notRegistered 0, enabled 1,
    /// requiresApproval 2, notFound 3. Pinned by a test, since a framework
    /// renumbering would otherwise silently invert the toggle.
    init(rawStatus: Int) {
        switch rawStatus {
        case 0: self = .off
        case 1: self = .on
        case 2: self = .needsApproval
        default: self = .unavailable
        }
    }

    var toggleIsOn: Bool { self == .on || self == .needsApproval }

    var canToggle: Bool { self != .unavailable }

    var note: String? {
        switch self {
        case .needsApproval:
            return "Turned off in System Settings → General → Login Items. Turn it back on there."
        case .unavailable:
            return "Deck can't register itself as a login item from this location. Install it in Applications first."
        case .off, .on:
            return nil
        }
    }
}
