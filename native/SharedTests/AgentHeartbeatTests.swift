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

/// The three things that make the heartbeat evidence, none of which the type
/// system can express: the agent writes it, it writes it **first**, and nothing
/// else writes it at all.
///
/// Source-tree assertions, reached through `#filePath` — the idiom
/// `DeckBundleTests` uses to pin `DeckBundle` against `project.yml`. The
/// DeckSharedTests scheme builds only its own target, so there is no built
/// product to inspect instead.
final class AgentHeartbeatWiringTests: XCTestCase {
    private var nativeDir: URL {
        URL(fileURLWithPath: #filePath)      // native/SharedTests/AgentHeartbeatTests.swift
            .deletingLastPathComponent()      // native/SharedTests
            .deletingLastPathComponent()      // native
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: nativeDir.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftSources(in directory: String) throws -> [(name: String, text: String)] {
        let root = nativeDir.appendingPathComponent(directory)
        let urls = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        return try urls.map {
            (name: "\(directory)/\($0)",
             text: try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8))
        }
    }

    private static let write = "AgentHeartbeatStore.save"

    func testTheAgentWritesTheHeartbeat() throws {
        XCTAssertTrue(
            try source("DeckAgent/main.swift").contains(Self.write),
            "DeckAgent must write the heartbeat, or the 60s agent has no witness at all"
        )
    }

    /// **Placement is the design, not a detail.** The full refresh awaits ~10
    /// mostly serial sources at 10s timeouts each; written at the *end*, a
    /// slow-but-healthy tick could cross the 240s limit and be reported dead.
    /// Written at the start it catches strictly more — launchd starts no new
    /// tick while one is running, so a hung agent stops advancing it either way.
    func testTheHeartbeatIsWrittenBeforeAnyFetch() throws {
        let main = try source("DeckAgent/main.swift")
        let write = try XCTUnwrap(main.range(of: Self.write), "no heartbeat write to place")
        // The first data the full path goes after, whichever way settings fall.
        let firstWork = ["RemoteOpenCodeLoader.load", "OpenCodeReader.load",
                         "HostGitBoxSampler.snapshot", "HostWeatherLoader.fetch"]
            .compactMap { main.range(of: $0)?.lowerBound }
            .min()
        let start = try XCTUnwrap(firstWork, "no loader call found — has the agent been restructured?")
        XCTAssertLessThan(
            write.lowerBound, start,
            "the heartbeat must be written before the agent starts fetching"
        )
    }

    /// The witness is a witness **only because one process writes it**. The ten
    /// snapshots the 60s agent produces are all written by the host app too,
    /// which is exactly why none of them could answer this question.
    ///
    /// Stated plainly: this is a substring search. It catches the realistic
    /// regression — a heartbeat write copy-pasted into a host refresh path —
    /// and it would not catch a wrapper function or a renamed store.
    func testNothingButTheAgentWritesTheHeartbeat() throws {
        for target in ["DeckApp", "DeckWidgets"] {
            for file in try swiftSources(in: target) {
                XCTAssertFalse(
                    file.text.contains(Self.write),
                    "\(file.name) writes the heartbeat — that destroys the witness silently"
                )
            }
        }
    }

    /// `dataAgentInterval` is a Swift literal because launchd reads the plist
    /// and Swift never does. Retuning the agent's cadence without this test
    /// would leave a threshold that fires on every healthy tick, with nothing
    /// failing anywhere.
    func testTheDataAgentIntervalMatchesTheAgentsPlist() throws {
        let plist = try source("DeckApp/LaunchAgents/com.deck.agent.plist")
        let declared = plist
            .components(separatedBy: "<key>StartInterval</key>")
            .dropFirst().first?
            .components(separatedBy: "<integer>").dropFirst().first?
            .components(separatedBy: "</integer>").first
        XCTAssertEqual(
            declared.flatMap { Double($0) },
            AgentLivenessPolicy.dataAgentInterval,
            "StartInterval and dataAgentInterval have drifted"
        )
    }
}
