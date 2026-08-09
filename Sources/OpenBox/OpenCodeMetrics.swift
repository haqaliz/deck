import Foundation
import OpenBoxCore

// MARK: - OpenCode DB access
//
// Metrics are read from the local opencode SQLite database via
// `opencode db <sql> --format json`.

enum OpenCodeQueries {
    static let totals = """
        SELECT COUNT(*) as sessions, SUM(tokens_input) as input, SUM(tokens_output) as output,
               SUM(tokens_cache_read) as cache_read, SUM(tokens_cache_write) as cache_write,
               ROUND(SUM(cost), 4) as cost
        FROM session
        """

    static let today = """
        SELECT COUNT(*) as sessions, SUM(tokens_input) as input, SUM(tokens_output) as output,
               ROUND(SUM(cost), 4) as cost
        FROM session
        WHERE time_created > (strftime('%s','now')*1000 - 86400000)
        """

    static let daily = """
        SELECT date(time_created/1000,'unixepoch') as day,
               SUM(tokens_input) as input, SUM(tokens_output) as output
        FROM session
        WHERE time_created > (strftime('%s','now','-13 days')*1000)
        GROUP BY day ORDER BY day
        """

    static let models = """
        SELECT model, COUNT(*) as sessions, SUM(tokens_input) as input,
               SUM(tokens_output) as output, ROUND(SUM(cost), 4) as cost
        FROM session WHERE model IS NOT NULL
        GROUP BY model ORDER BY cost DESC LIMIT 3
        """
}

enum OpenCodeMetricsLoader {
    static func load() -> OpenCodeMetrics? {
        guard
            let totals = run(OpenCodeQueries.totals).first,
            let today = run(OpenCodeQueries.today).first
        else { return nil }

        var metrics = OpenCodeMetrics()
        metrics.sessions = totals.int("sessions") ?? 0
        metrics.input = totals.int64("input") ?? 0
        metrics.output = totals.int64("output") ?? 0
        metrics.cacheRead = totals.int64("cache_read") ?? 0
        metrics.cacheWrite = totals.int64("cache_write") ?? 0
        metrics.cost = totals.double("cost") ?? 0

        metrics.todaySessions = today.int("sessions") ?? 0
        metrics.todayInput = today.int64("input") ?? 0
        metrics.todayOutput = today.int64("output") ?? 0
        metrics.todayCost = today.double("cost") ?? 0

        metrics.daily = run(OpenCodeQueries.daily).compactMap { row in
            guard let day = row["day"] as? String else { return nil }
            return DayUsage(
                day: day,
                input: row.int64("input") ?? 0,
                output: row.int64("output") ?? 0
            )
        }

        metrics.models = run(OpenCodeQueries.models).compactMap { row in
            guard let model = row["model"] as? String else { return nil }
            let parsed = ModelParser.parse(model)
            return ModelUsage(
                model: model,
                provider: parsed.provider,
                modelID: parsed.id,
                variant: parsed.variant,
                cost: row.double("cost") ?? 0,
                input: row.int64("input") ?? 0,
                output: row.int64("output") ?? 0
            )
        }

        return metrics
    }

    // MARK: - Runner

    private static func run(_ sql: String) -> [[String: Any]] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["opencode", "db", sql, "--format", "json"]
        process.standardOutput = pipe
        process.standardError = nil
        process.environment = environmentWithPath
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return json
    }

    private static var environmentWithPath: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["~/.opencode/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        if let path = env["PATH"] {
            env["PATH"] = path + ":" + extra.joined(separator: ":")
        } else {
            env["PATH"] = extra.joined(separator: ":")
        }
        return env
    }
}

private extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        (self[key] as? NSNumber)?.intValue ?? (self[key] as? Int)
    }

    func int64(_ key: String) -> Int64? {
        (self[key] as? NSNumber)?.int64Value ?? (self[key] as? Int).map(Int64.init)
    }

    func double(_ key: String) -> Double? {
        (self[key] as? NSNumber)?.doubleValue ?? (self[key] as? Double)
    }
}
