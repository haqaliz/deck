import XCTest

final class ProcessSnapshotStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcessSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var storeURL: URL {
        dir.appendingPathComponent("processes.json")
    }

    private func makeSnapshot() -> ProcessSnapshot {
        ProcessSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            processes: [
                TopProcess(name: "TestApp", cpuPercent: 12.5, memPercent: 3.2),
                TopProcess(name: "OtherApp", cpuPercent: 1.1, memPercent: 0.5),
            ]
        )
    }

    func testSaveThenLoadRoundTrips() {
        let snapshot = makeSnapshot()
        ProcessSnapshotStore.save(snapshot, to: storeURL)
        XCTAssertEqual(ProcessSnapshotStore.load(from: storeURL), snapshot)
    }

    func testCorruptFileLoadsNilAndNextSaveHeals() {
        try? "not-json{{{".write(to: storeURL, atomically: true, encoding: .utf8)
        XCTAssertNil(ProcessSnapshotStore.load(from: storeURL))
        ProcessSnapshotStore.save(makeSnapshot(), to: storeURL)
        XCTAssertNotNil(ProcessSnapshotStore.load(from: storeURL))
    }

    func testNoTempLeftoversAfterSave() {
        for _ in 0..<10 { ProcessSnapshotStore.save(makeSnapshot(), to: storeURL) }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.contains(".tmp.") } ?? []
        XCTAssertTrue(leftovers.isEmpty, "leftover temp files: \(leftovers)")
    }
}
