import WidgetKit
import SwiftUI
import Charts
import OSLog

private let openboxLog = Logger(subsystem: "com.deck.app.widgets", category: "OpenBox")

// MARK: - Timeline entry

struct OpenBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let sessions: Int64
    let input: Int64
    let output: Int64
    let cost: Double
    let daily: [OpenCodeSnapshot.Day]
    let models: [OpenCodeSnapshot.Model]
    let totalInput: Int64
    let totalOutput: Int64
    let totalCost: Double
    let settings: OpenBoxSettings
}

// MARK: - Provider

struct OpenBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> OpenBoxEntry {
        var daily: [OpenCodeSnapshot.Day] = []
        for i in 0..<14 {
            daily.append(
                OpenCodeSnapshot.Day(
                    day: "day\(i)",
                    input: Int64(300_000 + (i % 5) * 120_000),
                    output: Int64(40_000 + (i % 3) * 30_000)
                )
            )
        }
        return OpenBoxEntry(
            date: .now,
            available: true,
            sessions: 12,
            input: 2_400_000,
            output: 310_000,
            cost: 0.42,
            daily: daily,
            models: [
                OpenCodeSnapshot.Model(model: "deepseek-v4-flash", cost: 0.21, input: 1_200_000, output: 150_000),
                OpenCodeSnapshot.Model(model: "gpt-5.2", cost: 0.15, input: 800_000, output: 90_000),
            ],
            totalInput: 48_000_000,
            totalOutput: 6_100_000,
            totalCost: 9.84,
            settings: OpenBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (OpenBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> OpenBoxEntry {
        let snapshot = OpenCodeSnapshotStore.load()
        openboxLog.info("snapshot found=\(snapshot != nil) path=\(OpenCodeSnapshotStore.fileURL.path) home=\(FileManager.default.homeDirectoryForCurrentUser.path)")
        guard let snapshot, snapshot.writtenAt.timeIntervalSinceNow > -7200 else {
            return OpenBoxEntry(
                date: .now,
                available: false,
                sessions: 0,
                input: 0,
                output: 0,
                cost: 0,
                daily: [],
                models: [],
                totalInput: 0,
                totalOutput: 0,
                totalCost: 0,
                settings: DeckSettings.load().openbox
            )
        }
        let settings = DeckSettings.load().openbox
        return OpenBoxEntry(
            date: .now,
            available: true,
            sessions: snapshot.sessions,
            input: snapshot.input,
            output: snapshot.output,
            cost: snapshot.cost,
            daily: snapshot.daily,
            models: snapshot.models,
            totalInput: snapshot.totalInput,
            totalOutput: snapshot.totalOutput,
            totalCost: snapshot.totalCost,
            settings: settings
        )
    }
}

// MARK: - Widget

struct OpenBoxWidget: Widget {
    let kind = "OpenBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OpenBoxProvider()) { entry in
            OpenBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OpenBox")
        .description("Today's opencode tokens and cost with a 14-day chart and top models.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct OpenBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OpenBoxEntry

    var body: some View {
        Group {
            if !entry.available {
                unavailableView
            } else {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    mediumView
                default:
                    largeView
                }
            }
        }
    }


    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No opencode data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Run opencode to record usage.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            tokenRow(title: "IN", value: entry.input, color: entry.settings.inputColor.color)
            tokenRow(title: "OUT", value: entry.output, color: entry.settings.outputColor.color)
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.settings.costColor.color)
                        .frame(width: 7, height: 7)
                    Text("COST")
                        .foregroundStyle(.secondary)
                    Text(OpenCodeFormatters.formatCost(entry.cost))
                        .foregroundStyle(.primary)
                }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                tokenRow(title: "IN", value: entry.input, color: entry.settings.inputColor.color)
                tokenRow(title: "OUT", value: entry.output, color: entry.settings.outputColor.color)
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                    Text("COST")
                        .foregroundStyle(.secondary)
                    Text(OpenCodeFormatters.formatCost(entry.cost))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showChart && !entry.daily.isEmpty {
                chart
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                tokenRow(title: "IN", value: entry.input, color: entry.settings.inputColor.color)
                tokenRow(title: "OUT", value: entry.output, color: entry.settings.outputColor.color)
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.settings.costColor.color)
                        .frame(width: 7, height: 7)
                    Text("COST")
                        .foregroundStyle(.secondary)
                    Text(OpenCodeFormatters.formatCost(entry.cost))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showChart && !entry.daily.isEmpty {
                chart
                    .padding(.top, 6)
            }

            if entry.settings.showModels && !entry.models.isEmpty {
                Divider()
                    .padding(.top, 4)
                modelsList
            }

            Spacer(minLength: 0)

            Text("All time: \(OpenCodeFormatters.formatTokens(entry.totalInput)) in · \(OpenCodeFormatters.formatTokens(entry.totalOutput)) out · \(OpenCodeFormatters.formatCost(entry.totalCost))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var modelsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODELS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            ForEach(entry.models, id: \.model) { model in
                let parsed = ModelParser.parse(model.model)
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(parsed.provider)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 5) {
                            Text(parsed.id)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if let variant = parsed.variant {
                                Text(variant)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(entry.settings.costColor.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule()
                                            .fill(entry.settings.costColor.color.opacity(0.15))
                                    )
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(OpenCodeFormatters.formatCost(model.cost))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(entry.settings.costColor.color)
                        Text("\(OpenCodeFormatters.formatTokens(model.input)) / \(OpenCodeFormatters.formatTokens(model.output))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart(Array(entry.daily.enumerated()), id: \.offset) { index, day in
            LineMark(
                x: .value("Day", index),
                y: .value("Input", day.input),
                series: .value("Metric", "Input")
            )
            .foregroundStyle(entry.settings.inputColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", index),
                y: .value("Output", day.output),
                series: .value("Metric", "Output")
            )
            .foregroundStyle(entry.settings.outputColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: family == .systemMedium ? 62 : 82)
    }

    private func tokenRow(title: String, value: Int64, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(OpenCodeFormatters.formatTokens(value))
                .foregroundStyle(.primary)
        }
    }
}

private enum ModelParser {
    static let variants: Set<String> = [
        "flash", "mini", "max", "pro", "sonnet", "opus", "haiku", "turbo",
        "free", "latest", "small", "large", "nano", "medium", "plus",
        "preview", "thinking", "lite", "ultra", "grande", "dash", "snap",
        "exp", "extended", "high", "low", "fast", "reasoning",
    ]

    /// Splits a raw model string (JSON object or `provider/id-variant`) into
    /// provider, id and variant — mirrors the window widget's ModelParser.
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

private enum OpenCodeFormatters {
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
