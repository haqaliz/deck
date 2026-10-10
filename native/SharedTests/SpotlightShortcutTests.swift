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
