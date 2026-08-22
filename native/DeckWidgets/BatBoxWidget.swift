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
    let accessories: [BatteryAccessory]
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
            accessories: [
                BatteryAccessory(id: "p", name: "MX Master 3S", percent: 75, lowWarnLevel: 20, category: "Mouse")
            ],
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
            accessories: AccessoryMetricsLoader.snapshot(),
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

            if entry.settings.showAccessories, let summary = AccessoryCore.summary(entry.accessories) {
                Text(summary)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
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

            accessorySection
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

            accessorySection

            Spacer(minLength: 0)
        }
    }

    /// Hidden entirely when nothing is connected — an empty header would be
    /// worse than no section. Rows are ordered lowest-battery-first by the
    /// loader, so the row cap keeps whatever is closest to dying.
    @ViewBuilder
    private var accessorySection: some View {
        if entry.settings.showAccessories && !entry.accessories.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("ACCESSORIES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                ForEach(entry.accessories.prefix(entry.settings.accessoryCount), id: \.id) { accessory in
                    HStack(spacing: 6) {
                        Image(systemName: AccessoryCore.symbol(for: accessory.category))
                            .font(.system(size: 11))
                            .foregroundStyle(accessoryColor(accessory))
                            .frame(width: 16)
                        Text(accessory.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(BatteryFormatters.formatPercent(accessory.percent))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accessoryColor(accessory))
                    }
                }
            }
        }
    }

    /// Each accessory is judged against its OWN reported warn level, not a
    /// global setting — the manufacturer's threshold beats ours.
    private func accessoryColor(_ accessory: BatteryAccessory) -> Color {
        switch AccessoryCore.tier(percent: accessory.percent, lowWarnLevel: accessory.lowWarnLevel) {
        case .normal: return .secondary
        case .warn: return ThresholdTier.warnColor.color
        case .alarm: return ThresholdTier.alarmColor.color
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
    /// Last 48 bars only: 48 × 5pt = 240pt, so the sparkline never overflows
    /// the large widget width (72 bars would be ~360pt and get clipped).
    private var chart: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(entry.history.suffix(48).enumerated()), id: \.offset) { index, level in
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
