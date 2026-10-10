import XCTest

// How the settings tab words things it cannot see for itself: a recorded
// shortcut, and the state of Deck's own login item.

final class ShortcutFormatTests: XCTestCase {
    func testDefaultIsOptionSpace() {
        XCTAssertEqual(ShortcutFormat.display(keyCode: 49, modifiers: 2048), "⌥Space")
    }

    /// macOS orders glyphs control, option, shift, command.
    func testModifierOrderIsTheSystemOrder() {
        XCTAssertEqual(ShortcutFormat.display(keyCode: 40, modifiers: 256 | 512 | 2048 | 4096), "⌃⌥⇧⌘K")
    }

    func testLettersDigitsAndNamedKeys() {
        XCTAssertEqual(ShortcutFormat.display(keyCode: 0, modifiers: 256), "⌘A")
        XCTAssertEqual(ShortcutFormat.display(keyCode: 18, modifiers: 4096), "⌃1")
        XCTAssertEqual(ShortcutFormat.display(keyCode: 36, modifiers: 256), "⌘↩")
        XCTAssertEqual(ShortcutFormat.display(keyCode: 122, modifiers: 2048), "⌥F1")
    }

    func testAnUnknownKeyCodeStillRendersSomething() {
        XCTAssertEqual(ShortcutFormat.display(keyCode: 126 + 1, modifiers: 256), "⌘Key 127")
    }

    func testRecordingNeedsAModifier() {
        XCTAssertFalse(ShortcutFormat.isRecordable(modifiers: 0))
        XCTAssertTrue(ShortcutFormat.isRecordable(modifiers: 2048))
    }

    /// Caps-lock, fn and the numeric-pad bit ride along on NSEvent flags and
    /// are not modifiers a global hotkey can use.
    func testCarbonMaskKeepsOnlyUsableModifiers() {
        let capsLockAndOption = 65536 | 2048
        XCTAssertEqual(ShortcutFormat.usableModifiers(capsLockAndOption), 2048)
    }
}

/// The tray's Search item shows the shortcut natively, which needs the menu's
/// own key-equivalent string rather than the display glyph.
final class MenuKeyEquivalentTests: XCTestCase {
    func testLettersAndDigitsAreLowercase() {
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 40), "k")
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 0), "a")
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 18), "1")
    }

    func testSpaceIsALiteralSpace() {
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 49), " ")
    }

    func testReturnAndTab() {
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 36), "\r")
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 48), "\t")
    }

    /// AppKit spells arrows and function keys as private-use scalars.
    func testArrowsAndFunctionKeysUseAppKitScalars() {
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 126), "\u{F700}")  // up
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 125), "\u{F701}")  // down
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 123), "\u{F702}")  // left
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 124), "\u{F703}")  // right
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 122), "\u{F704}")  // F1
        XCTAssertEqual(ShortcutFormat.menuKeyEquivalent(keyCode: 111), "\u{F70F}")  // F12
    }

    /// An unknown key shows no shortcut rather than a wrong one.
    func testUnmappedKeyIsNil() {
        XCTAssertNil(ShortcutFormat.menuKeyEquivalent(keyCode: 127))
    }

    /// Every key the recorder can display has a menu equivalent, so the tray
    /// never disagrees with the settings tab about what the shortcut is.
    func testEveryDisplayableKeyHasAMenuEquivalent() {
        for code in 0...126 where ShortcutFormat.display(keyCode: code, modifiers: 0) != "Key \(code)" {
            XCTAssertNotNil(ShortcutFormat.menuKeyEquivalent(keyCode: code), "key \(code)")
        }
    }
}

final class LoginItemStateTests: XCTestCase {
    // SMAppService.Status raw values: notRegistered 0, enabled 1,
    // requiresApproval 2, notFound 3.
    func testMapping() {
        XCTAssertEqual(LoginItemState(rawStatus: 0), .off)
        XCTAssertEqual(LoginItemState(rawStatus: 1), .on)
        XCTAssertEqual(LoginItemState(rawStatus: 2), .needsApproval)
        XCTAssertEqual(LoginItemState(rawStatus: 3), .unavailable)
        XCTAssertEqual(LoginItemState(rawStatus: 99), .unavailable)
    }

    /// A user veto in Login Items is `.requiresApproval`, not `.notRegistered`
    /// (CLAUDE.md): the toggle must still read as "on" — Deck did register —
    /// and the note must say who turned it off.
    func testApprovalStateReadsAsOnWithAnExplanation() {
        XCTAssertTrue(LoginItemState.needsApproval.toggleIsOn)
        XCTAssertNotNil(LoginItemState.needsApproval.note)
        XCTAssertTrue(LoginItemState.needsApproval.note!.contains("Login Items"))
    }

    func testPlainStatesHaveNoNote() {
        XCTAssertFalse(LoginItemState.off.toggleIsOn)
        XCTAssertTrue(LoginItemState.on.toggleIsOn)
        XCTAssertNil(LoginItemState.off.note)
        XCTAssertNil(LoginItemState.on.note)
    }

    func testUnavailableCannotBeToggled() {
        XCTAssertFalse(LoginItemState.unavailable.canToggle)
        XCTAssertTrue(LoginItemState.off.canToggle)
        XCTAssertTrue(LoginItemState.needsApproval.canToggle)
    }
}
