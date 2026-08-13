import Foundation

struct CostDay: Codable, Equatable {
    let day: String
    let model: String
    let cost: Double
}

enum CostRows {
    /// Maps the reader's `[[String: Any]]` rows (from `GROUP BY day, model`)
    /// into `CostDay` values. Drops rows missing day or model; a missing cost
    /// reads as 0. Sorted by day asc, then cost desc within a day.
    static func mapRows(_ rows: [[String: Any]]) -> [CostDay] {
        rows.compactMap { row in
            guard let day = row["day"] as? String,
                  let model = row["model"] as? String else { return nil }
            let cost = (row["cost"] as? Double) ?? (row["cost"] as? NSNumber)?.doubleValue ?? 0
            return CostDay(day: day, model: model, cost: cost)
        }
        .sorted {
            $0.day == $1.day ? $0.cost > $1.cost : $0.day < $1.day
        }
    }
}

enum CostSeries {
    struct Series: Equatable {
        let model: String
        let costs: [Double]
    }

    /// Flattens a `[day: [model: cost]]` accumulator (remote mode) into the
    /// same sorted `[CostDay]` shape the reader produces.
    static func daily(fromDayModelCosts dayModelCosts: [String: [String: Double]]) -> [CostDay] {
        CostRows.mapRows(
            dayModelCosts.keys.sorted().flatMap { day in
                dayModelCosts[day]!.map { model, cost in
                    ["day": day, "model": model, "cost": cost]
                }
            }
        )
    }

    /// Builds chart series from sorted cost days: one value per day per model,
    /// top-N models by total cost (ties keep first-appearance order), the rest
    /// merged into an "other" series. Day order is the input's.
    static func buildSeries(from costDays: [CostDay], topN: Int = 3) -> [Series] {
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

    /// Short label for a chart legend: JSON-object model strings resolve to
    /// their `id`, `provider/id` strings to the last `/`-segment.
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

    private static func orderedDays(in costDays: [CostDay]) -> [String] {
        var days: [String] = []
        for day in costDays where !days.contains(day.day) {
            days.append(day.day)
        }
        return days
    }

    private static func costs(for model: String, days: [String], from costDays: [CostDay]) -> [Double] {
        days.map { day in
            costDays.first { $0.day == day && $0.model == model }?.cost ?? 0
        }
    }
}
