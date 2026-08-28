import XCTest

/// Pins Deck's bundle identifiers to the places the build actually reads them.
///
/// `DeckBundle` holds the ids as Swift literals because there is no way not to:
/// `PRODUCT_BUNDLE_IDENTIFIER` is a build setting, Swift has no string-valued
/// compile flag, and the one runtime source — `Bundle.main.bundleIdentifier` —
/// is wrong for both callers that matter (the host app needs the *extension's*
/// id, and `DeckAgent` is a `type: tool` whose identity lives in a
/// `__TEXT,__info_plist` section). So the literal cannot be eliminated; what it
/// can be is **pinned**, which is what these tests do.
///
/// The source tree is reached through `#filePath` rather than a bundle
/// resource: the DeckSharedTests scheme builds only its own target, so
/// `Deck.app` is not in the products directory during a test run and its
/// Info.plist cannot be read from there.
final class DeckBundleTests: XCTestCase {
    private var nativeDir: URL {
        URL(fileURLWithPath: #filePath)      // native/SharedTests/DeckBundleTests.swift
            .deletingLastPathComponent()      // native/SharedTests
            .deletingLastPathComponent()      // native
    }

    private func projectYML() throws -> String {
        try String(contentsOf: nativeDir.appendingPathComponent("project.yml"), encoding: .utf8)
    }

    // MARK: - Internal consistency

    /// True in both the old (`com.deck.app`) and new (`io.github.haqaliz.deck`)
    /// schemes, so it survives the flip and is worth asserting.
    func testWidgetsIDIsTheAppIDPlusWidgets() {
        XCTAssertEqual(DeckBundle.widgetsID, DeckBundle.appID + ".widgets")
    }

    func testFastAgentLabelIsTheAgentLabelPlusProcesses() {
        XCTAssertEqual(DeckBundle.fastAgentLabel, DeckBundle.agentLabel + ".processes")
    }

    /// The agent's OSLog subsystem is its label; `log show --predicate
    /// 'subsystem == "…"'` is the documented diagnostic path and must not drift
    /// from the label the docs tell people to grep for.
    func testLogSubsystemIsTheAgentLabel() {
        XCTAssertEqual(DeckBundle.logSubsystem, DeckBundle.agentLabel)
    }

    // MARK: - Legacy ids are frozen

    /// These name a container, a keychain service and two BTM records that
    /// exist on users' disks. Updating them during the rename would strand
    /// every one of those. They are never allowed to change.
    func testLegacyIdentifiersAreFrozen() {
        XCTAssertEqual(DeckBundle.Legacy.appID, "com.deck.app")
        XCTAssertEqual(DeckBundle.Legacy.widgetsID, "com.deck.app.widgets")
        XCTAssertEqual(DeckBundle.Legacy.agentLabel, "com.deck.agent")
        XCTAssertEqual(DeckBundle.Legacy.fastAgentLabel, "com.deck.agent.processes")
    }

    /// The keychain service is deliberately NOT the current app id: the five
    /// tokens live under the legacy string and stay there, because legacy-
    /// keychain access is not bound to the reading binary (measured in
    /// docs/planning/keychain-tokens/probe.md) so nothing needs migrating.
    func testKeychainServiceIsTheLegacyAppID() {
        XCTAssertEqual(DeckKeychain.defaultService, DeckBundle.Legacy.appID)
    }

    // MARK: - Drift guards against the build inputs

    func testProjectYMLDeclaresTheAppAndWidgetIdentifiers() throws {
        let yml = try projectYML()
        XCTAssertTrue(
            yml.contains("PRODUCT_BUNDLE_IDENTIFIER: \(DeckBundle.appID)\n"),
            "project.yml does not declare PRODUCT_BUNDLE_IDENTIFIER: \(DeckBundle.appID)"
        )
        XCTAssertTrue(
            yml.contains("PRODUCT_BUNDLE_IDENTIFIER: \(DeckBundle.widgetsID)\n"),
            "project.yml does not declare PRODUCT_BUNDLE_IDENTIFIER: \(DeckBundle.widgetsID)"
        )
    }

    func testProjectYMLDeclaresTheAgentIdentifier() throws {
        let yml = try projectYML()
        XCTAssertTrue(
            yml.contains("CFBundleIdentifier: \(DeckBundle.agentLabel)\n"),
            "project.yml does not declare CFBundleIdentifier: \(DeckBundle.agentLabel)"
        )
    }

    /// DeckAgent is a `type: tool`, so this generated plist is compiled into a
    /// `__TEXT,__info_plist` section and is what `codesign` reports as the
    /// binary's Identifier — which is in turn what TCC keys its grants to.
    func testAgentInfoPlistMatchesTheAgentLabel() throws {
        let url = nativeDir.appendingPathComponent("DeckAgent/Info.plist")
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil
        ) as? [String: Any]
        XCTAssertEqual(plist?["CFBundleIdentifier"] as? String, DeckBundle.agentLabel)
    }

    /// `SMAppService.agent(plistName:)` resolves these by filename inside the
    /// bundle, and launchd keys the job by the Label inside them. A rename that
    /// updates one and not the other produces a job that cannot be registered.
    func testLaunchAgentPlistsAreNamedAndLabelledForTheCurrentAgents() throws {
        for label in [DeckBundle.agentLabel, DeckBundle.fastAgentLabel] {
            let url = nativeDir.appendingPathComponent("DeckApp/LaunchAgents/\(label).plist")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "missing LaunchAgent plist for \(label)"
            )
            let plist = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil
            ) as? [String: Any]
            XCTAssertEqual(plist?["Label"] as? String, label, "Label drifted in \(label).plist")
        }
    }
}
