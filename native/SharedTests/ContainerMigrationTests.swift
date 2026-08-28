import XCTest

/// The bundle rename moves the widget extension's sandbox container, and
/// `settings.json` is the only thing in it that cannot be rebuilt — every other
/// file is a snapshot the agent rewrites within one 60s tick. These pin the
/// decision of whether to carry it across, which is deliberately separated from
/// the file I/O so it can be exhausted here.
final class ContainerMigrationPolicyTests: XCTestCase {
    private typealias Policy = ContainerMigrationPolicy

    /// The dormant state. Until the flip, `DeckBundle.widgetsID` and
    /// `DeckBundle.Legacy.widgetsID` are the same string, so both paths resolve
    /// to one directory — copying would be a file onto itself. This case is why
    /// the migration can ship a release early and stay invisible.
    func testSameContainerIsSkipped() {
        XCTAssertEqual(
            Policy.decide(identifiersDiffer: false, legacyContainerExists: true,
                          legacySettingsExists: true, currentSettingsExists: false),
            .skip(.sameContainer)
        )
    }

    /// A machine that never ran the old Deck.
    func testFreshInstallIsSkipped() {
        XCTAssertEqual(
            Policy.decide(identifiersDiffer: true, legacyContainerExists: false,
                          legacySettingsExists: false, currentSettingsExists: false),
            .skip(.noLegacyContainer)
        )
    }

    /// The old container exists but Deck never wrote settings into it — the app
    /// only writes `settings.json` on change, so an install that was never
    /// configured has snapshots and no settings file. Measured during the probe.
    func testLegacyContainerWithoutSettingsIsSkipped() {
        XCTAssertEqual(
            Policy.decide(identifiersDiffer: true, legacyContainerExists: true,
                          legacySettingsExists: false, currentSettingsExists: false),
            .skip(.noLegacySettings)
        )
    }

    /// Never overwrite. A second run must not clobber settings the user has
    /// changed since the first — this is what makes the migration safe to call
    /// on every launch, from both the app and the agent.
    func testExistingCurrentSettingsAreNeverOverwritten() {
        XCTAssertEqual(
            Policy.decide(identifiersDiffer: true, legacyContainerExists: true,
                          legacySettingsExists: true, currentSettingsExists: true),
            .skip(.alreadyMigrated)
        )
    }

    func testCarriesSettingsAcrossWhenNothingBlocksIt() {
        XCTAssertEqual(
            Policy.decide(identifiersDiffer: true, legacyContainerExists: true,
                          legacySettingsExists: true, currentSettingsExists: false),
            .copy
        )
    }

    /// "Already migrated" outranks "no legacy settings": if the new container is
    /// configured, the old one is irrelevant however it looks.
    func testAlreadyMigratedOutranksMissingLegacySettings() {
        XCTAssertEqual(
            Policy.decide(identifiersDiffer: true, legacyContainerExists: true,
                          legacySettingsExists: false, currentSettingsExists: true),
            .skip(.alreadyMigrated)
        )
    }

    /// The reasons must stay distinguishable. Deck's standing rule — `absent`
    /// and `failed` are never collapsed (`SecretRead`, `FetchOutcome`) — applies
    /// here too: the General tab words a skip differently from a failure, and a
    /// fresh install must never be described as a migration that did nothing.
    func testSkipReasonsAreDistinct() {
        let reasons: [ContainerMigrationPolicy.Decision] = [
            .skip(.sameContainer), .skip(.noLegacyContainer),
            .skip(.noLegacySettings), .skip(.alreadyMigrated), .copy,
        ]
        XCTAssertEqual(Set(reasons.map(String.init(describing:))).count, reasons.count)
    }
}

/// The thin I/O half, driven against temp directories rather than the real
/// container.
final class ContainerMigrationRunTests: XCTestCase {
    private var root: URL!
    private var legacy: URL!
    private var current: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deck-migration-\(UUID().uuidString)")
        legacy = root.appendingPathComponent("legacy/Application Support/Deck")
        current = root.appendingPathComponent("current/Application Support/Deck")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeLegacySettings(_ body: String = #"{"agentAtLogin":true}"#) throws {
        try body.write(to: legacy.appendingPathComponent("settings.json"),
                       atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: legacy.appendingPathComponent("settings.json").path
        )
    }

    func testCopiesSettingsAndCreatesTheDestination() throws {
        try writeLegacySettings()
        let outcome = ContainerMigration.run(legacyDirectory: legacy, currentDirectory: current)
        XCTAssertEqual(outcome, .migrated)
        let copied = current.appendingPathComponent("settings.json")
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), #"{"agentAtLogin":true}"#)
    }

    /// A copied credential file must not become world-readable in transit.
    func testCopyIsMode600() throws {
        try writeLegacySettings()
        _ = ContainerMigration.run(legacyDirectory: legacy, currentDirectory: current)
        let attrs = try FileManager.default.attributesOfItem(
            atPath: current.appendingPathComponent("settings.json").path
        )
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
    }

    /// The old container is migrated *from*, never altered — and above all never
    /// deleted: its metadata plist is SIP-protected, so removing the directory
    /// leaves containermanagerd believing it is still provisioned and every
    /// widget renders blank forever (CLAUDE.md).
    func testLeavesTheLegacyDirectoryIntact() throws {
        try writeLegacySettings()
        _ = ContainerMigration.run(legacyDirectory: legacy, currentDirectory: current)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: legacy.appendingPathComponent("settings.json").path))
    }

    func testSecondRunDoesNotOverwrite() throws {
        try writeLegacySettings()
        _ = ContainerMigration.run(legacyDirectory: legacy, currentDirectory: current)
        try #"{"agentAtLogin":false}"#.write(
            to: current.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let second = ContainerMigration.run(legacyDirectory: legacy, currentDirectory: current)
        XCTAssertEqual(second, .skipped(.alreadyMigrated))
        XCTAssertEqual(
            try String(contentsOf: current.appendingPathComponent("settings.json"), encoding: .utf8),
            #"{"agentAtLogin":false}"#,
            "the user's newer settings were clobbered by a second migration"
        )
    }

    func testMissingLegacyContainerIsASkipNotAFailure() {
        let absent = root.appendingPathComponent("nope/Application Support/Deck")
        XCTAssertEqual(
            ContainerMigration.run(legacyDirectory: absent, currentDirectory: current),
            .skipped(.noLegacyContainer)
        )
    }

    /// The dormant guarantee, checked against the **real** paths rather than
    /// temp ones. While the current and legacy widget ids are the same string,
    /// calling `run()` with its production defaults must do nothing at all —
    /// this is what makes it safe to ship a release before the rename. Skips
    /// itself once the flip lands, when the migration is supposed to act.
    func testIsInertAgainstTheRealPathsWhileIdentifiersMatch() throws {
        try XCTSkipUnless(
            DeckBundle.widgetsID == DeckBundle.Legacy.widgetsID,
            "identifiers have diverged — the migration is live and no longer inert"
        )
        XCTAssertEqual(ContainerMigration.run(), .skipped(.sameContainer))
    }

    /// Pointing both at one directory must be inert, not a copy onto itself.
    func testSameDirectoryIsInert() throws {
        try writeLegacySettings()
        XCTAssertEqual(
            ContainerMigration.run(legacyDirectory: legacy, currentDirectory: legacy),
            .skipped(.sameContainer)
        )
    }
}
