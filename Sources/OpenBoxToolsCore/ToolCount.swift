import Foundation

struct ToolCount: Codable, Equatable {
    let tool: String
    let count: Int64
}

/// Maps sqlite rows (from the existing `rows(_:sql:)` helper) to ToolCount,
/// dropping rows with a nil tool name, sorting by count descending.
func mapRows(_ rows: [[String: Any]]) -> [ToolCount] {
    rows.compactMap { row -> ToolCount? in
        guard let tool = row["tool"] as? String else { return nil }
        let count = row["count"] as? Int64 ?? (row["count"] as? NSNumber)?.int64Value ?? 0
        return ToolCount(tool: tool, count: count)
    }
    .sorted { $0.count > $1.count }
}

/// Stable leading slice of at most n entries.
func top(_ n: Int, from tools: [ToolCount]) -> [ToolCount] {
    Array(tools.prefix(n))
}
