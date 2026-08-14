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
    let tools: [OpenCodeSnapshot.ToolCount]
    let costDaily: [OpenCodeSnapshot.CostDay]
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
            tools: [
                OpenCodeSnapshot.ToolCount(tool: "bash", count: 7186),
                OpenCodeSnapshot.ToolCount(tool: "read", count: 4169),
                OpenCodeSnapshot.ToolCount(tool: "edit", count: 2098),
            ],
            costDaily: [
                OpenCodeSnapshot.CostDay(day: "day0", model: "deepseek-v4-flash", cost: 0.21),
                OpenCodeSnapshot.CostDay(day: "day1", model: "deepseek-v4-flash", cost: 0.15),
                OpenCodeSnapshot.CostDay(day: "day1", model: "gpt-5.2", cost: 0.06),
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
                tools: [],
                costDaily: [],
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
            tools: snapshot.tools,
            costDaily: snapshot.costDaily,
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
        .containerBackground(for: .widget) {
            Color.clear
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
                if entry.settings.showCostChart && !entry.costDaily.isEmpty {
                    costChart
                } else {
                    chart
                }
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
                if entry.settings.showCostChart && !entry.costDaily.isEmpty {
                    costChart
                        .padding(.top, 6)
                    if family == .systemLarge {
                        costLegend
                            .padding(.top, 4)
                    }
                } else {
                    chart
                        .padding(.top, 6)
                }
            }

            if entry.settings.showModels && !entry.models.isEmpty {
                Divider()
                    .padding(.top, 4)
                modelsList
            }

            if entry.settings.showTools && !entry.tools.isEmpty {
                Divider()
                    .padding(.top, 4)
                toolsList
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

            ForEach(entry.models.prefix(entry.settings.modelCount), id: \.model) { model in
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

    private var toolsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TOOLS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            ForEach(entry.tools.prefix(entry.settings.toolCount), id: \.tool) { tool in
                HStack(spacing: 8) {
                    Text(tool.tool)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text("\(tool.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(entry.settings.inputColor.color)
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
        .frame(height: family == .systemMedium ? 62 : 56)
    }

    private var costChart: some View {
        let series = CostSeries.buildSeries(from: entry.costDaily)
        let colors = costSeriesColors(count: series.count)
        let points = CostSeries.points(from: series)
        return Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Cost", point.cost)
                )
                .foregroundStyle(by: .value("Model", point.model))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartForegroundStyleScale(
            domain: series.map(\.model),
            range: colors
        )
        .frame(height: family == .systemMedium ? 62 : 56)
    }

    private var costLegend: some View {
        let series = CostSeries.buildSeries(from: entry.costDaily)
        let colors = costSeriesColors(count: series.count)
        return HStack(spacing: 10) {
            ForEach(Array(series.enumerated()), id: \.element.model) { index, s in
                HStack(spacing: 4) {
                    Circle()
                        .fill(colors[index])
                        .frame(width: 6, height: 6)
                    Text(CostSeries.displayID(of: s.model))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func costSeriesColors(count: Int) -> [Color] {
        let palette: [Color] = [
            entry.settings.costColor.color,
            Color(red: 0.35, green: 0.78, blue: 0.78),
            Color(red: 0.95, green: 0.55, blue: 0.65),
            Color.gray,
        ]
        return Array(palette.prefix(count))
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
