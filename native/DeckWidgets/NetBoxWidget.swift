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

    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NetBoxWidget/history.json")
    }

    static func load() -> [NetSample] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let samples = try? JSONDecoder().decode([NetSample].self, from: data)
        else { return [] }
        return samples
    }

    static func save(_ samples: [NetSample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
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

    private static let storageKey = "NetBox.previousSample"

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
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> NetBoxEntry {
        let current = NetworkMetricsLoader.sample()
        let now = Date()

        var stored = UserDefaults.standard.data(forKey: Self.storageKey)
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
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }

        let totalUp = rates.reduce(0) { $0 + $1.up }
        let totalDown = rates.reduce(0) { $0 + $1.down }

        var history = NetBoxHistoryStore.load()
        history.append(NetSample(up: totalUp, down: totalDown))
        if history.count > NetBoxHistoryStore.capacity {
            history.removeFirst(history.count - NetBoxHistoryStore.capacity)
        }
        NetBoxHistoryStore.save(history)

        let sorted = rates.sorted { max($0.up, $0.down) > max($1.up, $1.down) }

        return NetBoxEntry(
            date: now,
            interfaces: Array(sorted.prefix(10)),
            totalUp: totalUp,
            totalDown: totalDown,
            history: history,
            settings: DeckSettings.load().netbox
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
                                .foregroundStyle(entry.settings.upColor.color)
                            Text("↓ \(NetBoxFormatters.formatRate(interface.down))")
                                .foregroundStyle(entry.settings.downColor.color)
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
                                .foregroundStyle(entry.settings.upColor.color)
                            Text("↓ \(NetBoxFormatters.formatRate(interface.down))")
                                .foregroundStyle(entry.settings.downColor.color)
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
            .foregroundStyle(entry.settings.upColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", index),
                y: .value("DOWN", sample.down),
                series: .value("Metric", "DOWN")
            )
            .foregroundStyle(entry.settings.downColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1, peak))
        .frame(height: 80)
    }

    private func rateRow(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(NetBoxFormatters.formatRate(value))
                .foregroundStyle(.primary)
        }
    }
}
