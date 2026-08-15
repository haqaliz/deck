import Foundation

// MARK: - OpenBox pure logic (model parsing + cost series + formatting)
//
// Extracted from DeckWidgets/OpenBoxWidget.swift so the Shared parsers are
// testable in DeckSharedTests (the widget target can't be compiled into a
// unit-test bundle). Behavior is identical to the original private copies.

enum ModelParser {
    static let variants: Set<String> = [
        "flash", "mini", "max", "pro", "sonnet", "opus", "haiku", "turbo",
        "free", "latest", "small", "large", "nano", "medium", "plus",
        "preview", "thinking", "lite", "ultra", "grande", "dash", "snap",
        "exp", "extended", "high", "low", "fast", "reasoning",
    ]

    /// Splits a raw model string (JSON object or `provider/id-variant`) into
    /// provider, id and variant.
    static func parse(_ raw: String) -> (provider: String, id: String, variant: String?) {
        if let data = raw.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var provider = (obj["providerID"] as? String) ?? "local"
            var id = (obj["id"] as? String) ?? raw
            let variant = obj["variant"] as? String

            if let slash = id.firstIndex(of: "/") {
                provider += " · " + String(id[..<slash])
                id = String(id[id.index(after: slash)...])
            }
            return (provider: provider, id: id, variant: variant)
        }

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

enum CostSeries {
    struct Series: Equatable {
        let model: String
        let costs: [Double]
    }

    struct Point: Identifiable {
        let id = UUID()
        let model: String
        let day: Int
        let cost: Double
    }

    /// One value per day per model, top-N models by total cost (ties keep
    /// first-appearance order), the rest merged into an "other" series.
    static func buildSeries(from costDays: [OpenCodeSnapshot.CostDay], topN: Int = 3) -> [Series] {
        guard !costDays.isEmpty else { return [] }

        let days = orderedDays(in: costDays)
        var totals: [String: Double] = [:]
        for day in costDays { totals[day.model, default: 0] += day.cost }

        var appearance: [String: Int] = [:]
        var index = 0
        for day in costDays where appearance[day.model] == nil {
            appearance[day.model] = index
            index += 1
        }

        let top = totals.keys
            .sorted {
                if totals[$0]! != totals[$1]! { return totals[$0]! > totals[$1]! }
                return appearance[$0]! < appearance[$1]!
            }
            .prefix(topN)

        var series = top.map { model in
            Series(model: model, costs: costs(for: model, days: days, from: costDays))
        }

        let other = totals.keys.filter { !top.contains($0) }
        if !other.isEmpty {
            series.append(Series(model: "other", costs: days.map { day in
                other.reduce(0.0) { sum, model in
                    sum + (costDays.first { $0.day == day && $0.model == model }?.cost ?? 0)
                }
            }))
        }
        return series
    }

    /// Flattens series into day-aligned chart points (x = day index).
    static func points(from series: [Series]) -> [Point] {
        series.enumerated().flatMap { _, s in
            s.costs.enumerated().map { day, cost in
                Point(model: s.model, day: day, cost: cost)
            }
        }
    }

    /// Short label for the legend: JSON-object model strings resolve to their
    /// `id`, `provider/id` strings to the last `/`-segment.
    static func displayID(of raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let id = obj["id"] as? String {
            return id
        }
        if let slash = raw.lastIndex(of: "/") {
            return String(raw[raw.index(after: slash)...])
        }
        return raw
    }

    private static func orderedDays(in costDays: [OpenCodeSnapshot.CostDay]) -> [String] {
        var days: [String] = []
        for day in costDays where !days.contains(day.day) {
            days.append(day.day)
        }
        return days
    }

    private static func costs(for model: String, days: [String], from costDays: [OpenCodeSnapshot.CostDay]) -> [Double] {
        days.map { day in
            costDays.first { $0.day == day && $0.model == model }?.cost ?? 0
        }
    }
}

enum OpenCodeFormatters {
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
}

// MARK: - Session rows (pure; tested in OpenBoxSessionCoreTests)

enum OpenBoxSessionList {
    /// Maps raw SQL rows (title/tokens_input/tokens_output/time_created) into
    /// session rows: orders by total tokens desc, drops nil/empty titles,
    /// caps at `limit`. The SQL query only filters the window — ordering and
    /// capping live here so they stay purely testable.
    static func map(_ rows: [[String: Any]], now: Date, limit: Int) -> [OpenCodeSnapshot.SessionRow] {
        let mapped = rows.compactMap { row -> OpenCodeSnapshot.SessionRow? in
            guard let title = row.string("title"), !title.isEmpty else { return nil }
            return OpenCodeSnapshot.SessionRow(
                title: title,
                input: row.int64("tokens_input") ?? 0,
                output: row.int64("tokens_output") ?? 0,
                timeCreated: Date(timeIntervalSince1970: row.int64("time_created").map { Double($0) / 1000 } ?? 0)
            )
        }
        return mapped
            .sorted {
                let lhs = $0.input + $0.output
                let rhs = $1.input + $1.output
                if lhs != rhs { return lhs > rhs }
                return $0.timeCreated > $1.timeCreated
            }
            .prefix(limit)
            .map { $0 }
    }

    /// "just now" / "10m ago" / "2h ago" / "3d ago" — same shape as the
    /// ClipBox relative-time label, seconds from `to` back to `now`.
    static func relativeTime(from now: Date, to date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return switch seconds {
        case ..<60: "just now"
        case ..<3600: "\(seconds / 60)m ago"
        case ..<86400: "\(seconds / 3600)h ago"
        default: "\(seconds / 86400)d ago"
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func int64(_ key: String) -> Int64? {
        self[key] as? Int64 ?? (self[key] as? NSNumber)?.int64Value
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }
}
