import XCTest

/// The 60s agent's liveness witness, and the evidence vocabulary both witnesses
/// answer in.
///
/// The point of `AgentEvidence` is that **"no file" and "a file I cannot read"
/// are different answers.** `ProcessSnapshotStore.load()` collapses them —
/// `try? Data(contentsOf:)` then `try? decode`, both to `nil` — and the liveness
/// notice then tells a user "No refresh has been recorded" about a file
/// something plainly recorded.
final class AgentEvidenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-heartbeat-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    // MARK: - The heartbeat's own evidence

    func testAbsentHeartbeatIsNever() {
        XCTAssertEqual(AgentHeartbeatStore.evidence(at: url("nothing.json")), .never)
    }

    func testUndecodableHeartbeatIsUnreadable() throws {
        let target = url("agent-heartbeat.json")
        try Data("{ not json".utf8).write(to: target)
        XCTAssertEqual(AgentHeartbeatStore.evidence(at: target), .unreadable)
    }

    /// A truncated write is the realistic corruption, and zero bytes is its
    /// limit case. `AtomicFile` makes it unlikely, not impossible — it falls
    /// back to a plain write when `replaceItemAt` throws.
    func testEmptyHeartbeatFileIsUnreadable() throws {
        let target = url("agent-heartbeat.json")
        try Data().write(to: target)
        XCTAssertEqual(AgentHeartbeatStore.evidence(at: target), .unreadable)
    }

    /// Right JSON, wrong shape: a file holding some *other* snapshot is
    /// unreadable as a heartbeat, not absent.
    func testWellFormedJSONWithoutTheFieldIsUnreadable() throws {
        let target = url("agent-heartbeat.json")
        try Data(#"{"somethingElse":1}"#.utf8).write(to: target)
        XCTAssertEqual(AgentHeartbeatStore.evidence(at: target), .unreadable)
    }

    func testSavedHeartbeatReadsBackAsRanAtItsTimestamp() {
        let target = url("agent-heartbeat.json")
        let written = Date(timeIntervalSince1970: 1_700_000_000)
        AgentHeartbeatStore.save(AgentHeartbeat(writtenAt: written), to: target)
        XCTAssertEqual(AgentHeartbeatStore.evidence(at: target), .ran(at: written))
    }

    /// `JSONEncoder` writes `Date` as seconds since the **2001 reference date**,
    /// not the Unix epoch. Harmless — the same encoder reads it back — and
    /// confusing to anyone who opens the container and does the arithmetic, so
    /// it is pinned rather than discovered twice.
    func testHeartbeatEncodesItsDateAgainstTheReferenceDate() throws {
        let target = url("agent-heartbeat.json")
        AgentHeartbeatStore.save(
            AgentHeartbeat(writtenAt: Date(timeIntervalSinceReferenceDate: 752_025_600)),
            to: target
        )
        let raw = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(
            raw.contains("752025600"),
            "expected reference-date seconds in \(raw)"
        )
    }

    // MARK: - The process snapshot answers the same way

    func testAbsentProcessSnapshotIsNever() {
        XCTAssertEqual(ProcessSnapshotStore.evidence(at: url("nothing.json")), .never)
    }

    func testUndecodableProcessSnapshotIsUnreadableRatherThanNever() throws {
        let target = url("processes.json")
        try Data("{".utf8).write(to: target)
        XCTAssertEqual(
            ProcessSnapshotStore.evidence(at: target), .unreadable,
            "a corrupt snapshot must not read as an agent that never ran"
        )
    }

    func testValidProcessSnapshotIsRanAtItsWrittenAt() {
        let target = url("processes.json")
        let written = Date(timeIntervalSince1970: 1_700_000_123)
        ProcessSnapshotStore.save(
            ProcessSnapshot(writtenAt: written, processes: []), to: target
        )
        XCTAssertEqual(ProcessSnapshotStore.evidence(at: target), .ran(at: written))
    }

    // MARK: - Where it lives

    /// The witness is a **file**, not a field on `DeckSettings`, and that is
    /// load-bearing: `ContainerMigration` copies only `settings.json` across the
    /// bundle rename. A field would carry a stale timestamp from the old install
    /// into a container whose agent has never run — the exact false positive
    /// `AgentRegistrationClock` exists to prevent.
    func testHeartbeatLivesBesideTheSnapshotsInTheContainer() {
        XCTAssertEqual(AgentHeartbeatStore.fileURL.lastPathComponent, "agent-heartbeat.json")
        XCTAssertEqual(
            AgentHeartbeatStore.fileURL.deletingLastPathComponent().standardizedFileURL,
            DeckSettings.containerDirectory.standardizedFileURL
        )
    }
}
