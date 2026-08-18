import XCTest

final class AtomicFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func payload(_ n: Int) -> Data {
        Data(String(repeating: "x", count: 1024).utf8)
            + Data("|\(n)".utf8)
    }

    func testWriteReplacesTarget() {
        let url = dir.appendingPathComponent("out.json")
        XCTAssertTrue(AtomicFile.write(payload(1), to: url))
        XCTAssertEqual(try? Data(contentsOf: url), payload(1))
        XCTAssertTrue(AtomicFile.write(payload(2), to: url))
        XCTAssertEqual(try? Data(contentsOf: url), payload(2))
    }

    func testConcurrentWritersNeverCorruptTarget() {
        let url = dir.appendingPathComponent("out.json")
        let total = 800
        DispatchQueue.concurrentPerform(iterations: total) { i in
            _ = AtomicFile.write(self.payload(i), to: url)
        }
        guard let data = try? Data(contentsOf: url) else {
            return XCTFail("target missing after concurrent writes")
        }
        XCTAssertTrue(
            (0..<total).contains { self.payload($0) == data },
            "target is corrupt (not equal to any written payload, length \(data.count))"
        )
    }

    func testWriteFailureReturnsFalseAndKeepsTarget() {
        let readOnly = dir.appendingPathComponent("readonly", isDirectory: true)
        try? FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: readOnly.path
        )
        let url = readOnly.appendingPathComponent("out.json")
        XCTAssertFalse(AtomicFile.write(payload(1), to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "target must be untouched after failed write")
    }

    func testNoTempLeftoversAfterSuccess() {
        let url = dir.appendingPathComponent("out.json")
        for i in 0..<10 { XCTAssertTrue(AtomicFile.write(payload(i), to: url)) }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.contains(".tmp.") } ?? []
        XCTAssertTrue(leftovers.isEmpty, "leftover temp files: \(leftovers)")
    }

    func testWriteCreatesMissingParentDirectory() {
        let deep = dir.appendingPathComponent("a/b/c", isDirectory: true)
        let url = deep.appendingPathComponent("out.json")
        XCTAssertTrue(AtomicFile.write(payload(1), to: url))
        XCTAssertEqual(try? Data(contentsOf: url), payload(1))
    }
}
