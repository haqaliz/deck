import XCTest

// Every quit and Dock-icon decision the tray makes, as a pure policy, so the
// app delegate only applies it. The lifecycle is where CLAUDE.md records the
// most traps; these pin the rules the PRD approved.

final class TrayLifecyclePolicyTests: XCTestCase {
    // MARK: Quitting

    /// "Keep Deck in the menu bar only" means exactly that: closing Deck from
    /// the Dock (or Cmd-Q in the settings window) closes the app but leaves
    /// the tray, and so the shortcut, running. Only the tray's own Quit ends it.
    func testTrayOnlyKeepsRunningWhenQuitFromTheDockOrCmdQ() {
        for reason in [QuitReason.dockQuit, .settingsCmdQ] {
            XCTAssertFalse(
                TrayLifecyclePolicy.shouldTerminate(reason: reason, keepInTrayOnly: true, trayReady: true),
                "\(reason) must leave the tray running")
        }
    }

    func testWithoutTrayOnlyEveryQuitTerminates() {
        for reason in [QuitReason.trayQuit, .settingsCmdQ, .dockQuit, .system] {
            XCTAssertTrue(
                TrayLifecyclePolicy.shouldTerminate(reason: reason, keepInTrayOnly: false, trayReady: true),
                "\(reason) must quit when tray-only is off")
        }
    }

    func testTheTrayQuitAlwaysTerminates() {
        XCTAssertTrue(TrayLifecyclePolicy.shouldTerminate(reason: .trayQuit, keepInTrayOnly: true, trayReady: true))
    }

    /// Logout and restart must never be vetoed by a resident app.
    func testSystemShutdownAlwaysTerminates() {
        XCTAssertTrue(TrayLifecyclePolicy.shouldTerminate(reason: .system, keepInTrayOnly: true, trayReady: true))
        XCTAssertTrue(TrayLifecyclePolicy.shouldTerminate(reason: .system, keepInTrayOnly: true, trayReady: false))
    }

    /// With no tray there is nothing to stay resident behind: cancelling the
    /// quit would leave an app with no window, no Dock icon and no way to
    /// quit it short of Force Quit.
    func testWithoutAWorkingTrayQuitAlwaysTerminates() {
        for reason in [QuitReason.dockQuit, .settingsCmdQ, .trayQuit] {
            XCTAssertTrue(
                TrayLifecyclePolicy.shouldTerminate(reason: reason, keepInTrayOnly: true, trayReady: false),
                "\(reason) must quit when the tray never appeared")
        }
    }

    /// Closing the last window never quits Deck: that is today's behaviour, and
    /// in tray-only mode it is the whole point.
    func testClosingTheLastWindowNeverTerminates() {
        XCTAssertFalse(TrayLifecyclePolicy.shouldTerminate(reason: .lastWindowClosed, keepInTrayOnly: true, trayReady: true))
        XCTAssertFalse(TrayLifecyclePolicy.shouldTerminate(reason: .lastWindowClosed, keepInTrayOnly: false, trayReady: true))
    }

    // MARK: Dock icon

    func testDockIconHiddenOnlyWhenTrayOnlyAndTheTrayExistsAndNoWindow() {
        XCTAssertEqual(
            TrayLifecyclePolicy.activationPolicy(trayReady: true, keepInTrayOnly: true, settingsWindowOpen: false),
            .accessory)
    }

    /// The tray is the only way back in once the Dock icon is gone, so a Deck
    /// whose status item failed to appear must stay a normal app.
    func testNeverHidesTheDockIconWithoutATray() {
        XCTAssertEqual(
            TrayLifecyclePolicy.activationPolicy(trayReady: false, keepInTrayOnly: true, settingsWindowOpen: false),
            .regular)
    }

    func testDockIconReturnsWhileTheSettingsWindowIsOpen() {
        XCTAssertEqual(
            TrayLifecyclePolicy.activationPolicy(trayReady: true, keepInTrayOnly: true, settingsWindowOpen: true),
            .regular)
    }

    func testTrayOnlyOffIsAlwaysRegular() {
        for ready in [false, true] {
            for open in [false, true] {
                XCTAssertEqual(
                    TrayLifecyclePolicy.activationPolicy(trayReady: ready, keepInTrayOnly: false, settingsWindowOpen: open),
                    .regular)
            }
        }
    }

    func testTrayOnlyCannotBeEnabledUntilTheTrayExists() {
        XCTAssertFalse(TrayLifecyclePolicy.canEnableTrayOnly(trayReady: false))
        XCTAssertTrue(TrayLifecyclePolicy.canEnableTrayOnly(trayReady: true))
    }

    // MARK: Widget URL launches

    /// A Deck started only to carry a widget click still gets out of the way;
    /// one that was already running (tray or window) must not be quit by it.
    func testColdURLLaunchQuitsAfterForwarding() {
        XCTAssertTrue(TrayLifecyclePolicy.quitsAfterForwardingURL(alreadyRunning: false))
    }

    func testRunningDeckSurvivesAURLOpen() {
        XCTAssertFalse(TrayLifecyclePolicy.quitsAfterForwardingURL(alreadyRunning: true))
    }
}

final class ShortcutRegistrationCopyTests: XCTestCase {
    func testSuccessSaysNothing() {
        XCTAssertNil(ShortcutRegistrationCopy.message(status: 0))
    }

    /// -9878 is `eventHotKeyExistsErr`: returned only for a duplicate inside
    /// this process. The copy must not claim another app was found, because
    /// another app holding the combination is never reported.
    func testTheDuplicateCodeDoesNotBlameAnotherApp() throws {
        let text = try XCTUnwrap(ShortcutRegistrationCopy.message(status: -9878))
        XCTAssertFalse(text.lowercased().contains("another app"))
        XCTAssertTrue(text.contains("couldn't claim"))
    }

    func testTheSilentConflictCaveatIsStatedHonestly() {
        XCTAssertTrue(ShortcutRegistrationCopy.silentConflictNote.contains("doesn't report"))
    }

    func testAnyOtherFailureCarriesTheCode() throws {
        let text = try XCTUnwrap(ShortcutRegistrationCopy.message(status: -50))
        XCTAssertTrue(text.contains("-50"))
    }
}
