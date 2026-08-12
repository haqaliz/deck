import Testing
import Foundation
@testable import OpenBoxToolsCore

@Suite("ToolCount mapping")
struct ToolCountTests {
    private func row(_ tool: String?, _ count: Int64?) -> [String: Any] {
        var r: [String: Any] = [:]
        if let tool { r["tool"] = tool }
        if let count { r["count"] = count }
        return r
    }

    @Test("empty rows map to empty list")
    func emptyRows() {
        #expect(mapRows([]) == [])
    }

    @Test("valid rows map and sort descending")
    func validRows() {
        let rows: [[String: Any]] = [
            row("read", 4169),
            row("bash", 7186),
            row("edit", 2098),
        ]
        #expect(mapRows(rows) == [
            ToolCount(tool: "bash", count: 7186),
            ToolCount(tool: "read", count: 4169),
            ToolCount(tool: "edit", count: 2098),
        ])
    }

    @Test("nil tool rows are dropped")
    func nilToolDropped() {
        let rows: [[String: Any]] = [
            row("bash", 10),
            row(nil, 999),
            row(nil, nil),
        ]
        #expect(mapRows(rows) == [ToolCount(tool: "bash", count: 10)])
    }

    @Test("missing count maps to zero and is kept")
    func missingCount() {
        let rows: [[String: Any]] = [row("grep", nil)]
        #expect(mapRows(rows) == [ToolCount(tool: "grep", count: 0)])
    }

    @Test("live DB shape parity fixture")
    func liveShape() {
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
        let expected: [ToolCount] = [
            ToolCount(tool: "bash", count: 7186),
            ToolCount(tool: "read", count: 4169),
            ToolCount(tool: "edit", count: 2098),
            ToolCount(tool: "grep", count: 910),
            ToolCount(tool: "write", count: 711),
            ToolCount(tool: "glob", count: 204),
            ToolCount(tool: "task", count: 202),
            ToolCount(tool: "skill", count: 187),
        ]
        #expect(mapRows(rows) == expected)
    }

    @Test("top n keeps leading slice")
    func topN() {
        let all = [ToolCount(tool: "a", count: 5), ToolCount(tool: "b", count: 4), ToolCount(tool: "c", count: 3)]
        #expect(top(2, from: all) == [ToolCount(tool: "a", count: 5), ToolCount(tool: "b", count: 4)])
        #expect(top(0, from: all) == [])
        #expect(top(10, from: all) == all)
        #expect(top(2, from: []) == [])
    }
}
