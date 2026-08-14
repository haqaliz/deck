import XCTest

// Ported from the OpenBoxToolsCore scratch package (2c899e7) against
// OpenCodeReader.mapToolRows.

final class ToolCountTests: XCTestCase {
    private func row(_ tool: String?, _ count: Int64?) -> [String: Any] {
        var r: [String: Any] = [:]
        if let tool { r["tool"] = tool }
        if let count { r["count"] = count }
        return r
    }

    func testEmptyRowsMapToEmpty() {
        XCTAssertEqual(OpenCodeReader.mapToolRows([]), [])
    }

    func testValidRowsMapAndSortDescending() {
        let rows: [[String: Any]] = [
            row("read", 4169),
            row("bash", 7186),
            row("edit", 2098),
        ]
        XCTAssertEqual(OpenCodeReader.mapToolRows(rows), [
            OpenCodeSnapshot.ToolCount(tool: "bash", count: 7186),
            OpenCodeSnapshot.ToolCount(tool: "read", count: 4169),
            OpenCodeSnapshot.ToolCount(tool: "edit", count: 2098),
        ])
    }

    func testNilToolRowsAreDropped() {
        let rows: [[String: Any]] = [
            row("bash", 10),
            row(nil, 999),
            row(nil, nil),
        ]
        XCTAssertEqual(OpenCodeReader.mapToolRows(rows), [OpenCodeSnapshot.ToolCount(tool: "bash", count: 10)])
    }

    func testMissingCountMapsToZeroAndIsKept() {
        let rows: [[String: Any]] = [row("grep", nil)]
        XCTAssertEqual(OpenCodeReader.mapToolRows(rows), [OpenCodeSnapshot.ToolCount(tool: "grep", count: 0)])
    }

    func testLiveDBShapeParityFixture() {
        let rows: [[String: Any]] = [
            row("bash", 7186),
            row("read", 4169),
            row("edit", 2098),
            row("grep", 910),
            row("write", 711),
            row("glob", 204),
            row("task", 202),
            row("skill", 187),
        ]
        XCTAssertEqual(OpenCodeReader.mapToolRows(rows), [
            OpenCodeSnapshot.ToolCount(tool: "bash", count: 7186),
            OpenCodeSnapshot.ToolCount(tool: "read", count: 4169),
            OpenCodeSnapshot.ToolCount(tool: "edit", count: 2098),
            OpenCodeSnapshot.ToolCount(tool: "grep", count: 910),
            OpenCodeSnapshot.ToolCount(tool: "write", count: 711),
            OpenCodeSnapshot.ToolCount(tool: "glob", count: 204),
            OpenCodeSnapshot.ToolCount(tool: "task", count: 202),
            OpenCodeSnapshot.ToolCount(tool: "skill", count: 187),
        ])
    }
}
