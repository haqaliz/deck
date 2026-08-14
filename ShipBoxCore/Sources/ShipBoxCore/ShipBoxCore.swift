import Foundation

// MARK: - Models

enum ShipStatus: String, Codable, Equatable {
    case queued
    case running
    case success
    case failure
    case neutral

    /// GitHub run status/conclusion pair → Deck status.
    static func map(status: String?, conclusion: String?) -> ShipStatus {
        switch (status, conclusion) {
        case ("queued", _), ("waiting", _), ("requested", _), ("pending", _):
            return .queued
        case ("in_progress", _):
            return .running
        case ("completed", "success"):
            return .success
        case ("completed", "failure"), ("completed", "timed_out"),
             ("completed", "action_required"), ("completed", "stale"):
            return .failure
        default:
            return .neutral
        }
    }
}

struct ShipRun: Codable, Equatable {
    var name: String
    var runNumber: Int
    var branch: String
    var status: ShipStatus
    var createdAt: Date
    var updatedAt: Date
    var htmlURL: String
}

struct ParsedRuns: Equatable {
    var totalCount: Int
    var runs: [ShipRun]
}

// MARK: - Parser
//
// GitHub REST contract: every field is a JSON string; conclusion is null while
// a run is not completed. Dates are ISO8601 ("2026-08-14T10:00:00Z").

enum RunParser {
    static func parse(_ data: Data) -> ParsedRuns? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let runsList = json["workflow_runs"] as? [[String: Any]]
        else { return nil }

        let total = (json["total_count"] as? NSNumber)?.intValue
            ?? Int(json["total_count"] as? String ?? "") ?? runsList.count

        return ParsedRuns(totalCount: total, runs: runsList.compactMap(run(from:)))
    }

    private static func run(from entry: [String: Any]) -> ShipRun? {
        guard let name = entry["name"] as? String else { return nil }
        let status = ShipStatus.map(
            status: entry["status"] as? String,
            conclusion: entry["conclusion"] as? String
        )
        return ShipRun(
            name: name,
            runNumber: intValue(entry["run_number"]) ?? 0,
            branch: (entry["head_branch"] as? String) ?? "",
            status: status,
            createdAt: dateValue(entry["created_at"]) ?? Date(timeIntervalSince1970: 0),
            updatedAt: dateValue(entry["updated_at"]) ?? Date(timeIntervalSince1970: 0),
            htmlURL: (entry["html_url"] as? String) ?? ""
        )
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, !string.isEmpty { return Int(string) }
        return nil
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return Self.dateFormatter.date(from: string)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Formatting

enum RunFormatting {
    struct Totals: Equatable {
        var success = 0
        var failure = 0
        var running = 0
        var queued = 0
        var neutral = 0
    }

    static func totals(for runs: [ShipRun]) -> Totals {
        var totals = Totals()
        for run in runs {
            switch run.status {
            case .success: totals.success += 1
            case .failure: totals.failure += 1
            case .running: totals.running += 1
            case .queued: totals.queued += 1
            case .neutral: totals.neutral += 1
            }
        }
        return totals
    }

    /// "2 fail · 3 pass · 1 run" — neutral/queued skipped when zero.
    static func totalsLine(for runs: [ShipRun]) -> String {
        let totals = totals(for: runs)
        var parts: [String] = []
        if totals.failure > 0 { parts.append("\(totals.failure) fail") }
        if totals.success > 0 { parts.append("\(totals.success) pass") }
        if totals.running > 0 { parts.append("\(totals.running) run") }
        if totals.queued > 0 { parts.append("\(totals.queued) queued") }
        return parts.joined(separator: " · ")
    }

    /// "3m12s" / "0m45s" / "1h04m" for completed runs.
    static func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%dh%02dm", hours, minutes)
        }
        return "\(minutes)m\(secs)s"
    }

    /// Row trailing text: "main · 3m12s", "main · QUEUED", "feat/x · RUNNING".
    static func detail(for run: ShipRun) -> String {
        let branch = run.branch.isEmpty ? "—" : run.branch
        switch run.status {
        case .queued:
            return "\(branch) · QUEUED"
        case .running:
            return "\(branch) · RUNNING"
        case .success, .failure, .neutral:
            return "\(branch) · \(duration(from: run.createdAt, to: run.updatedAt))"
        }
    }
}
