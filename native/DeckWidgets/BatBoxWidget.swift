import WidgetKit
import SwiftUI
import Charts

// MARK: - Level history (persisted in the extension container for the chart)

enum BatBoxHistoryStore {
    static let capacity = 72

    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("BatBoxWidget/history.json")
    }

    static func load() -> [Double] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let levels = try? JSONDecoder().decode([Double].self, from: data)
        else { return [] }
        return levels
    }

    static func save(_ levels: [Double]) {
        guard let data = try? JSONEncoder().encode(levels) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}

// MARK: - Timeline entry

struct BatBoxEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot
    let history: [Double]
    let settings: BatBoxSettings
}

// MARK: - Provider

struct BatBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatBoxEntry {
        BatBoxEntry(
            date: .now,
            snapshot: BatterySnapshot(
                levelPercent: 71,
                timeToEmptyMinutes: 214,
                timeToFullMinutes: nil,
                isCharging: false,
                isCharged: false,
                isPresent: true,
                powerSource: .battery
            ),
            history: (0..<20).map { Double(40 + ($0 % 6) * 8) },
            settings: BatBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BatBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> BatBoxEntry {
        let snapshot = BatteryMetricsLoader.snapshot()

        var history = BatBoxHistoryStore.load()
        if let level = snapshot.levelPercent {
            history.append(level)
            if history.count > BatBoxHistoryStore.capacity {
                history.removeFirst(history.count - BatBoxHistoryStore.capacity)
            }
            BatBoxHistoryStore.save(history)
        }

        return BatBoxEntry(
            date: .now,
            snapshot: snapshot,
            history: history,
            settings: DeckSettings.load().batbox
        )
    }
}

// MARK: - Widget

struct BatBoxWidget: Widget {
    let kind = "BatBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatBoxProvider()) { entry in
            BatBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BatBox")
        .description("Battery level, time remaining and charge state.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct BatBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatBoxEntry

    private var snapshot: BatterySnapshot { entry.snapshot }

    var body: some View {
        Group {
            if !snapshot.isPresent || snapshot.levelPercent == nil {
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
            Text("BatBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No battery")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(batteryColor)
                Text(BatteryFormatters.formatPercent(snapshot.levelPercent ?? 0))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text(BatteryFormatters.formatState(
                isCharging: snapshot.isCharging,
                isCharged: snapshot.isCharged,
                powerSource: snapshot.powerSource
            ))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(batteryColor)
                    Text(BatteryFormatters.formatPercent(snapshot.levelPercent ?? 0))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text(snapshot.isCharging ? "TIME TO FULL" : "TIME LEFT")
                        .foregroundStyle(.secondary)
                    Text(BatteryFormatters.formatTime(minutes:
                        snapshot.isCharging ? snapshot.timeToFullMinutes : snapshot.timeToEmptyMinutes
                    ))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            Divider()

            HStack(spacing: 4) {
                Circle()
                    .fill(batteryColor)
                    .frame(width: 7, height: 7)
                Text("STATE")
                    .foregroundStyle(.secondary)
                Text(BatteryFormatters.formatState(
                    isCharging: snapshot.isCharging,
                    isCharged: snapshot.isCharged,
                    powerSource: snapshot.powerSource
                ))
                .foregroundStyle(.primary)
                Spacer()
                Text(snapshot.powerSource == .ac ? "AC Power" : "Battery")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(batteryColor)
                    Text(BatteryFormatters.formatPercent(snapshot.levelPercent ?? 0))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text(snapshot.isCharging ? "TIME TO FULL" : "TIME LEFT")
                        .foregroundStyle(.secondary)
                    Text(BatteryFormatters.formatTime(minutes:
                        snapshot.isCharging ? snapshot.timeToFullMinutes : snapshot.timeToEmptyMinutes
                    ))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showChart && !entry.history.isEmpty {
                chart
            }

            if entry.settings.showStatus {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    statusRow(title: "State", value: BatteryFormatters.formatState(
                        isCharging: snapshot.isCharging,
                        isCharged: snapshot.isCharged,
                        powerSource: snapshot.powerSource
                    ))
                    statusRow(title: "Time", value: timeText)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.settings.levelColor.color)
        }
    }

    private var timeText: String {
        if snapshot.isCharged { return "Full" }
        if snapshot.isCharging {
            return BatteryFormatters.formatTime(minutes: snapshot.timeToFullMinutes)
        }
        return BatteryFormatters.formatTime(minutes: snapshot.timeToEmptyMinutes)
    }

    /// Custom bar sparkline (fixed 64pt) — deterministic sizing, no chart
    /// framework quirks. At 100% the bars are full-height, like a level meter.
    private var chart: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(entry.history.enumerated()), id: \.offset) { index, level in
                Rectangle()
                    .fill(entry.settings.levelColor.color.opacity(0.55))
                    .frame(width: 3, height: max(2, level / 100 * 60))
            }
        }
        .frame(height: 64, alignment: .bottom)
    }

    private var level: Double { snapshot.levelPercent ?? 0 }

    private var batteryColor: Color {
        if level < 20 { return .red }
        if level < 50 { return .orange }
        return .green
    }

    private var batterySymbol: String {
        if snapshot.isCharging { return "battery.100percent.bolt" }
        if level > 90 { return "battery.100percent" }
        if level > 65 { return "battery.75percent" }
        if level > 40 { return "battery.50percent" }
        if level > 15 { return "battery.25percent" }
        return "battery.0percent"
    }
}
