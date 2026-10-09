import XCTest

// Every quit and Dock-icon decision the tray makes, as a pure policy, so the
// app delegate only applies it. The lifecycle is where CLAUDE.md records the
// most traps; these pin the rules the PRD approved.

final class TrayLifecyclePolicyTests: XCTestCase {
    // MARK: Quitting

    func testExplicitQuitsAlwaysTerminate() {
        for tray in [false, true] {
            for reason in [QuitReason.trayQuit, .settingsCmdQ, .dockQuit] {
                XCTAssertTrue(
                    TrayLifecyclePolicy.shouldTerminate(reason: reason, keepInTrayOnly: tray),
                    "\(reason) must quit (tray-only: \(tray))")
            }
        }
    }

    /// Logout and restart must never be vetoed by a resident app.
    func testSystemShutdownAlwaysTerminates() {
        XCTAssertTrue(TrayLifecyclePolicy.shouldTerminate(reason: .system, keepInTrayOnly: true))
        XCTAssertTrue(TrayLifecyclePolicy.shouldTerminate(reason: .system, keepInTrayOnly: false))
    }

    /// Closing the window never quits Deck: that is today's behaviour, and in
    /// tray-only mode it is the whole point.
    func testClosingTheLastWindowNeverTerminates() {
        XCTAssertFalse(TrayLifecyclePolicy.shouldTerminate(reason: .lastWindowClosed, keepInTrayOnly: true))
        XCTAssertFalse(TrayLifecyclePolicy.shouldTerminate(reason: .lastWindowClosed, keepInTrayOnly: false))
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

    /// -9878 is `eventHotKeyExistsErr`, measured in the phase 0 probe.
    func testAConflictIsNamedAsOne() throws {
        let text = try XCTUnwrap(ShortcutRegistrationCopy.message(status: -9878))
        XCTAssertTrue(text.contains("already in use"))
    }

    func testAnyOtherFailureCarriesTheCode() throws {
        let text = try XCTUnwrap(ShortcutRegistrationCopy.message(status: -50))
        XCTAssertTrue(text.contains("-50"))
    }
}
