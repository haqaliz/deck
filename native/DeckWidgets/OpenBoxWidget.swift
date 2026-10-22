import WidgetKit
import SwiftUI
import Charts
import OSLog

private let openboxLog = Logger(subsystem: DeckBundle.widgetsID, category: "OpenBox")

// MARK: - Timeline entry

struct OpenBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let writtenAt: Date?
    let stale: Bool
    /// One line explaining the last remote fetch, or nil (always nil in local
    /// mode — the local DB is not a fetch).
    let chip: String?
    let sessions: Int64
    let input: Int64
    let output: Int64
    let cost: Double
    let daily: [OpenCodeSnapshot.Day]
    let models: [OpenCodeSnapshot.Model]
    let tools: [OpenCodeSnapshot.ToolCount]
    let costDaily: [OpenCodeSnapshot.CostDay]
    let sessionList: [OpenCodeSnapshot.SessionRow]
    let totalInput: Int64
    let totalOutput: Int64
    let totalCost: Double
    let limits: OpenBoxUsage?
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
            writtenAt: .now,
            stale: false,
            chip: nil,
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
            sessionList: [
                OpenCodeSnapshot.SessionRow(title: "ShipBox widget review", input: 380_000, output: 32_000, timeCreated: .now.addingTimeInterval(-7200)),
                OpenCodeSnapshot.SessionRow(title: "OpenBox cost chart spike", input: 96_000, output: 11_000, timeCreated: .now.addingTimeInterval(-86_400)),
                OpenCodeSnapshot.SessionRow(title: "Settings migration audit", input: 31_000, output: 4_000, timeCreated: .now.addingTimeInterval(-3 * 86_400)),
            ],
            totalInput: 48_000_000,
            totalOutput: 6_100_000,
            totalCost: 9.84,
            limits: placeholderLimits(now: .now),
            settings: placeholderSettings
        )
    }

    private func placeholderLimits(now: Date) -> OpenBoxUsage {
        OpenBoxUsage(
            writtenAt: now,
            product: "go",
            cancelAtPeriodEnd: false,
            fiveHour: .init(
                usedMicroCents: 6_639_170,
                limitMicroCents: 1_200_000_000,
                resetsAt: now.addingTimeInterval(4 * 3_600)
            ),
            week: .init(
                usedMicroCents: 849_821_991,
                limitMicroCents: 3_000_000_000,
                resetsAt: now.addingTimeInterval(3 * 86_400 + 9 * 3_600)
            ),
            month: .init(
                usedMicroCents: 5_078_102_976,
                limitMicroCents: 6_000_000_000,
                resetsAt: now.addingTimeInterval(4 * 86_400 + 21 * 3_600)
            )
        )
    }

    private var placeholderSettings: OpenBoxSettings {
        var settings = OpenBoxSettings()
        settings.showLimits = true
        return settings
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
        let limits = OpenBoxUsageStore.load()
        openboxLog.info("snapshot found=\(snapshot != nil) path=\(OpenCodeSnapshotStore.fileURL.path) home=\(FileManager.default.homeDirectoryForCurrentUser.path)")
        let now = Date()
        let allSettings = DeckSettings.load()
        let openboxSettings = allSettings.openbox
        // Remote mode only: a status left over from a server the user has
        // since cleared must not haunt a perfectly healthy local OpenBox.
        // The server URL lives on the selected opencode account now, so this
        // must not read `openboxSettings.serverURL` — that field is empty
        // after the migration and OpenBox would render as local forever.
        let isRemote = allSettings.openBoxUsesRemoteServer
        let chip = isRemote
            ? FetchChip.text(
                source: .opencodeRemote,
                status: FetchStatusStore.load(.opencodeRemote),
                dataWrittenAt: snapshot?.writtenAt,
                now: now
            )
            : nil

        guard let snapshot else {
            return OpenBoxEntry(
                date: now,
                available: false,
                writtenAt: nil,
                stale: false,
                chip: chip,
                sessions: 0,
                input: 0,
                output: 0,
                cost: 0,
                daily: [],
                models: [],
                tools: [],
                costDaily: [],
                sessionList: [],
                totalInput: 0,
                totalOutput: 0,
                totalCost: 0,
                limits: limits,
                settings: openboxSettings
            )
        }
        let settings = openboxSettings
        return OpenBoxEntry(
            date: now,
            available: true,
            writtenAt: snapshot.writtenAt,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            chip: chip,
            sessions: snapshot.sessions,
            input: snapshot.input,
            output: snapshot.output,
            cost: snapshot.cost,
            daily: snapshot.daily,
            models: snapshot.models,
            tools: snapshot.tools,
            costDaily: snapshot.costDaily,
            sessionList: snapshot.sessionList,
            totalInput: snapshot.totalInput,
            totalOutput: snapshot.totalOutput,
            totalCost: snapshot.totalCost,
            limits: limits,
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
        .description("Today's opencode tokens and cost with a 14-day chart, top models and Go usage limits.")
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
            Text(entry.chip ?? "Run opencode to record usage.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Reason for the last failed remote fetch and/or how old these numbers
    /// are. Without the old 2-hour cutoff, stale figures must say so rather
    /// than read as today's.
    private var statusLine: some View {
        HStack(spacing: 4) {
            if let chip = entry.chip {
                Text(chip)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if entry.stale, let writtenAt = entry.writtenAt {
                Text("· \(timeString(writtenAt))")
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.tertiary)
    }

    private var hasStatusLine: Bool {
        entry.chip != nil || (entry.stale && entry.writtenAt != nil)
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

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
            if hasStatusLine {
                statusLine
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasStatusLine {
                statusLine
            }
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

            if limitsVisible, let usage = entry.limits {
                limitsSection(usage)
                    .padding(.top, 2)
            }

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
            if hasStatusLine {
                statusLine
            }
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

            if limitsVisible, let usage = entry.limits {
                limitsSection(usage)
                    .padding(.top, 2)
            }

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

            if entry.settings.showSessions && !entry.sessionList.isEmpty {
                Divider()
                    .padding(.top, 4)
                sessionsList
            }

            Spacer(minLength: 0)

            Text("All time: \(OpenCodeFormatters.formatTokens(entry.totalInput)) in · \(OpenCodeFormatters.formatTokens(entry.totalOutput)) out · \(OpenCodeFormatters.formatCost(entry.totalCost))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The same three meters the Console Go page shows, from
    /// `openbox-usage.json`. Limits and remaining are the server's numbers;
    /// the bar is used/limit.
    private func limitsSection(_ usage: OpenBoxUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("LIMITS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Text(usage.productLabel)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if entry.date.timeIntervalSince(usage.writtenAt) > 10 * 60 {
                    Text("as of \(timeString(usage.writtenAt))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            limitRow("ROLLING", usage.fiveHour)
            limitRow("WEEKLY", usage.week)
            limitRow("MONTHLY", usage.month)
        }
    }

    @ViewBuilder
    private func limitRow(_ title: String, _ meter: OpenBoxUsage.Meter?) -> some View {
        if let meter {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .frame(width: 46, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.22))
                        Capsule()
                            .fill(limitTint(meter.percent))
                            .frame(width: max(2, proxy.size.width * min(meter.percent / 100, 1)))
                    }
                }
                .frame(height: 5)
                Text(meter.percentText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(limitTint(meter.percent))
                    .frame(width: 34, alignment: .trailing)
                Text("\(OpenBoxUsageFormatters.money(meter.remainingMicroCents)) left of \(OpenBoxUsageFormatters.money(meter.limitMicroCents))")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The Console's meter tones: over 95% is danger, 70% and up is warning.
    private func limitTint(_ percent: Double) -> Color {
        if percent > 95 { return .red }
        if percent >= 70 { return .orange }
        return .green
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

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SESSIONS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            ForEach(entry.sessionList.prefix(entry.settings.sessionCount), id: \.title) { session in
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(OpenCodeFormatters.formatTokens(session.input + session.output))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(entry.settings.inputColor.color)
                    Text(OpenBoxSessionList.relativeTime(from: entry.date, to: session.timeCreated))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private var limitsVisible: Bool {
        entry.settings.showLimits && entry.limits?.hasMeters == true
    }

    /// Medium shares its height with the limits section; a full chart would
    /// push the third meter out of the card.
    private var chartHeight: CGFloat {
        family == .systemMedium ? (limitsVisible ? 40 : 62) : 56
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
        .frame(height: chartHeight)
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
        .frame(height: chartHeight)
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
