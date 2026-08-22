import WidgetKit
import SwiftUI
import Charts

// MARK: - Sample history (persisted in the extension container for the chart)

struct NetSample: Codable {
    let up: Double
    let down: Double
}

enum NetBoxHistoryStore {
    static let capacity = 60

    /// Per widget family. Every NetBox instance shares one process, so a
    /// single history file had small/medium/large all appending to the same
    /// series — each size double-feeding the others' charts.
    static func fileURL(family: WidgetFamily) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NetBoxWidget/history-\(family).json")
    }

    static func load(family: WidgetFamily) -> [NetSample] {
        guard
            let data = try? Data(contentsOf: fileURL(family: family)),
            let samples = try? JSONDecoder().decode([NetSample].self, from: data)
        else { return [] }
        return samples
    }

    static func save(_ samples: [NetSample], family: WidgetFamily) {
        let url = fileURL(family: family)
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }
}

// MARK: - Timeline entry

struct NetBoxEntry: TimelineEntry {
    let date: Date
    let interfaces: [InterfaceRates]
    let totalUp: Double
    let totalDown: Double
    let history: [NetSample]
    let settings: NetBoxSettings
}

// MARK: - Provider
//
// Rates need two byte-counter samples: the previous sample is persisted in
// UserDefaults (extension container) across timeline reloads.

struct NetBoxProvider: TimelineProvider {
    private struct StoredSample: Codable {
        let date: Date
        let interfaces: [InterfaceSample]
    }

    /// Per widget family. With one shared key, two NetBox widgets stomped on
    /// each other's previous sample: whichever regenerated second saw a ~0s
    /// interval and a ~0 byte delta, so every rate computed to 0 — which then
    /// made the "most active" sort an all-ties sort and ACTIVE showed an
    /// arbitrary dead interface.
    private static func storageKey(family: WidgetFamily) -> String {
        "NetBox.previousSample.\(family)"
    }

    func placeholder(in context: Context) -> NetBoxEntry {
        var history: [NetSample] = []
        for i in 0..<20 {
            history.append(
                NetSample(
                    up: Double(400_000 + (i % 5) * 300_000),
                    down: Double(1_200_000 + (i % 4) * 600_000)
                )
            )
        }
        return NetBoxEntry(
            date: .now,
            interfaces: [
                InterfaceRates(name: "en0", up: 1_200_000, down: 3_400_000),
                InterfaceRates(name: "en1", up: 80_000, down: 210_000),
            ],
            totalUp: 1_280_000,
            totalDown: 3_610_000,
            history: history,
            settings: NetBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NetBoxEntry) -> Void) {
        completion(makeEntry(family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetBoxEntry>) -> Void) {
        let entry = makeEntry(family: context.family)
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry(family: WidgetFamily) -> NetBoxEntry {
        let settings = DeckSettings.load().netbox
        let current = NetworkMetricsLoader.sample()
        let now = Date()

        var stored = UserDefaults.standard.data(forKey: Self.storageKey(family: family))
            .flatMap { try? JSONDecoder().decode(StoredSample.self, from: $0) }

        if let sample = stored, sample.date.timeIntervalSince(now) > 300 {
            stored = nil
        }

        let rates: [InterfaceRates]
        if let stored {
            rates = current.compactMap { currentSample in
                guard let previous = stored.interfaces.first(where: { $0.name == currentSample.name }) else { return nil }
                return NetworkMetricsLoader.rates(
                    previous: previous,
                    current: currentSample,
                    interval: now.timeIntervalSince(stored.date)
                )
            }
        } else {
            rates = []
        }

        if let data = try? JSONEncoder().encode(
            StoredSample(date: now, interfaces: current)
        ) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(family: family))
        }

        let pinned = NetBoxPinnedInterface.select(pinned: settings.pinnedInterface, interfaces: rates)
        let totalUp = pinned.reduce(0) { $0 + $1.up }
        let totalDown = pinned.reduce(0) { $0 + $1.down }

        var history = NetBoxHistoryStore.load(family: family)
        history.append(NetSample(up: totalUp, down: totalDown))
        if history.count > NetBoxHistoryStore.capacity {
            history.removeFirst(history.count - NetBoxHistoryStore.capacity)
        }
        NetBoxHistoryStore.save(history, family: family)

        let sorted = NetBoxActiveInterface.sorted(rates: pinned, live: NetworkMetricsLoader.liveInterfaces())

        return NetBoxEntry(
            date: now,
            interfaces: Array(sorted.prefix(10)),
            totalUp: totalUp,
            totalDown: totalDown,
            history: history,
            settings: settings
        )
    }
}

// MARK: - Widget

struct NetBoxWidget: Widget {
    let kind = "NetBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetBoxProvider()) { entry in
            NetBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NetBox")
        .description("Per-interface up/down rates with the most active interfaces.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct NetBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetBoxEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            default:
                largeView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }


    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            rateRow(title: "DOWN", value: entry.totalDown, color: entry.settings.downColor.color)
            rateRow(title: "UP", value: entry.totalUp, color: entry.settings.upColor.color)
            if let active = entry.interfaces.first {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("ACTIVE")
                        .foregroundStyle(.secondary)
                    Text(active.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                rateRow(title: "DOWN", value: entry.totalDown, color: entry.settings.downColor.color)
                rateRow(title: "UP", value: entry.totalUp, color: entry.settings.upColor.color)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showInterfaces && !entry.interfaces.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("INTERFACES")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    ForEach(Array(entry.interfaces.prefix(entry.settings.interfaceCount).enumerated()), id: \.offset) { _, interface in
                        HStack(spacing: 6) {
                            Text(interface.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .frame(width: 44, alignment: .leading)
                            Spacer()
                            Text("↑ \(NetBoxFormatters.formatRate(interface.up))")
                                .foregroundStyle(tierColor(for: interface.up) ?? entry.settings.upColor.color)
                            Text("↓ \(NetBoxFormatters.formatRate(interface.down))")
                                .foregroundStyle(tierColor(for: interface.down) ?? entry.settings.downColor.color)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("Sampling…")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                rateRow(title: "DOWN", value: entry.totalDown, color: entry.settings.downColor.color)
                rateRow(title: "UP", value: entry.totalUp, color: entry.settings.upColor.color)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showChart && !entry.history.isEmpty {
                chart
            }

            if entry.settings.showInterfaces && !entry.interfaces.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("INTERFACES")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    ForEach(Array(entry.interfaces.prefix(entry.settings.interfaceCount).enumerated()), id: \.offset) { _, interface in
                        HStack(spacing: 6) {
                            Text(interface.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .frame(width: 44, alignment: .leading)
                            Spacer()
                            Text("↑ \(NetBoxFormatters.formatRate(interface.up))")
                                .foregroundStyle(tierColor(for: interface.up) ?? entry.settings.upColor.color)
                            Text("↓ \(NetBoxFormatters.formatRate(interface.down))")
                                .foregroundStyle(tierColor(for: interface.down) ?? entry.settings.downColor.color)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var peak: Double {
        entry.history.map { max($0.up, $0.down) }.max() ?? 1
    }

    private var chart: some View {
        Chart(Array(entry.history.enumerated()), id: \.offset) { index, sample in
            LineMark(
                x: .value("Time", index),
                y: .value("UP", sample.up),
                series: .value("Metric", "UP")
            )
            .foregroundStyle(tierColor(for: sample.up) ?? entry.settings.upColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", index),
                y: .value("DOWN", sample.down),
                series: .value("Metric", "DOWN")
            )
            .foregroundStyle(tierColor(for: sample.down) ?? entry.settings.downColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1, peak))
        .frame(height: 80)
    }

    /// Dot follows the tier alongside the value, matching LiveBox.
    private func rateRow(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tierColor(for: value) ?? color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(NetBoxFormatters.formatRate(value))
                .foregroundStyle(tierColor(for: value) ?? .primary)
        }
    }

    /// Overrides the row/chart color while a rate sits in warn/alarm tier;
    /// nil keeps the user's color (or the default .primary text color).
    /// Non-positive rates ("no reading") never tint.
    private func tierColor(for rate: Double) -> Color? {
        let settings = entry.settings
        guard settings.showThresholdColors else { return nil }
        switch NetBoxThresholdTier.tier(
            rate: rate,
            warnMBps: settings.warnThreshold,
            alarmMBps: settings.alarmThreshold
        ) {
        case .normal: return nil
        case .warn: return ThresholdTier.warnColor.color
        case .alarm: return ThresholdTier.alarmColor.color
        }
    }
}
