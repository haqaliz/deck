import Foundation

// MARK: - OpenCode DB access
//
// Metrics are read from the local opencode SQLite database via
// `opencode db <sql> --format json`.

struct DayUsage: Identifiable, Equatable {
    let day: String
    let input: Int64
    let output: Int64
    var id: String { day }
}

struct ModelUsage: Identifiable, Equatable {
    let model: String
    let provider: String
    let modelID: String
    let variant: String?
    let cost: Double
    let input: Int64
    let output: Int64
    var id: String { model }
}

/// Splits `provider/model-id-variant` (or `provider:model`) into
/// provider, id and variant. e.g. `opencode-go/deepseek-v4-flash-free`
/// → provider `opencode-go`, id `deepseek-v4`, variant `flash free`.
enum ModelParser {
    static let variants: Set<String> = [
        "flash", "mini", "max", "pro", "sonnet", "opus", "haiku", "turbo",
        "free", "latest", "small", "large", "nano", "medium", "plus",
        "preview", "thinking", "lite", "ultra", "grande", "dash", "snap",
        "exp", "extended", "high", "low", "fast", "reasoning",
    ]

    static func parse(_ raw: String) -> (provider: String, id: String, variant: String?) {
        // 1. OpenCode stores the model as JSON: {"id":..., "providerID":..., "variant":...}
        if let data = raw.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var provider = (obj["providerID"] as? String) ?? "local"
            var id = (obj["id"] as? String) ?? raw
            let variant = obj["variant"] as? String

            // the id may carry its own vendor prefix: "qwen/qwen3.8-max"
            if let slash = id.firstIndex(of: "/") {
                provider += " · " + String(id[..<slash])
                id = String(id[id.index(after: slash)...])
            }
            return (provider: provider, id: id, variant: variant)
        }

        // 2. Fallback for plain `provider/model-id-variant` strings
        var provider = "local"
        var idPart = raw
        if let slash = raw.lastIndex(of: "/") {
            provider = String(raw[..<slash])
            idPart = String(raw[raw.index(after: slash)...])
        } else if let colon = raw.lastIndex(of: ":") {
            provider = String(raw[..<colon])
            idPart = String(raw[raw.index(after: colon)...])
        }

        let tokens = idPart.split(separator: "-").map(String.init)
        var idTokens = tokens
        var variantTokens: [String] = []

        while let last = idTokens.last, variants.contains(last.lowercased()) {
            variantTokens.insert(last, at: 0)
            idTokens.removeLast()
        }

        if variantTokens.isEmpty,
           let index = idTokens.firstIndex(where: { variants.contains($0.lowercased()) }) {
            variantTokens = [idTokens[index]]
            idTokens.remove(at: index)
        }

        return (
            provider: provider,
            id: idTokens.joined(separator: "-"),
            variant: variantTokens.isEmpty ? nil : variantTokens.joined(separator: " ")
        )
    }
}

struct OpenCodeMetrics {
    var sessions: Int = 0
    var messages: Int = 0
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var cost: Double = 0

    var todaySessions: Int = 0
    var todayInput: Int64 = 0
    var todayOutput: Int64 = 0
    var todayCost: Double = 0

    var daily: [DayUsage] = []
    var models: [ModelUsage] = []
}

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

    // MARK: - Formatting

    static func formatTokens(_ value: Int64) -> String {
        let n = Double(value)
        if n >= 1_000_000_000 { return String(format: "%.2fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", n / 1_000) }
        return "\(value)"
    }

    static func formatCost(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func shortDay(_ day: String) -> String {
        String(day.dropFirst(5))
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
