import WidgetKit
import SwiftUI
import Charts

// MARK: - Sample history (persisted in the extension container so the chart has a rolling window)

struct Sample: Codable {
    let cpu: Double
    let mem: Double
    let disk: Double
}

enum HistoryStore {
    static let capacity = 60

    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("LiveBoxWidget/history.json")
    }

    static func load() -> [Sample] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let samples = try? JSONDecoder().decode([Sample].self, from: data)
        else { return [] }
        return samples
    }

    static func save(_ samples: [Sample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}

// MARK: - Timeline entry

struct LiveBoxEntry: TimelineEntry {
    let date: Date
    let cpu: Double
    let mem: Double
    let disk: Double
    let processes: [Metrics.TopProcess]
    let history: [Sample]
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> LiveBoxEntry {
        LiveBoxEntry(
            date: .now,
            cpu: 32,
            mem: 61,
            disk: 45,
            processes: [
                .init(name: "chrome", cpuPercent: 12.3),
                .init(name: "code", cpuPercent: 4.1),
                .init(name: "spotify", cpuPercent: 3.2),
            ],
            history: (0..<20).map { i in
                Sample(cpu: Double(20 + (i % 7) * 3), mem: 60, disk: 45)
            }
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> LiveBoxEntry {
        let cpu = Metrics.cpuPercent()
        let mem = Metrics.memoryPercent()
        let disk = Metrics.diskPercent()

        var history = HistoryStore.load()
        history.append(Sample(cpu: cpu, mem: mem, disk: disk))
        if history.count > HistoryStore.capacity {
            history.removeFirst(history.count - HistoryStore.capacity)
        }
        HistoryStore.save(history)

        return LiveBoxEntry(
            date: .now,
            cpu: cpu,
            mem: mem,
            disk: disk,
            processes: Metrics.topProcesses(limit: 3),
            history: history
        )
    }
}

// MARK: - Widget

struct LiveBoxWidget: Widget {
    let kind = "LiveBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LiveBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("LiveBox")
        .description("CPU, memory, disk usage with a live chart and top processes.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable()
    }
}

struct LiveBoxWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveBoxWidget()
    }
}

// MARK: - Views

struct LiveBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LiveBoxEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            default:
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricRow(title: "CPU", value: entry.cpu, color: .green)
            metricRow(title: "MEM", value: entry.mem, color: .cyan)
            metricRow(title: "DISK", value: entry.disk, color: .orange)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                metricRow(title: "CPU", value: entry.cpu, color: .green)
                metricRow(title: "MEM", value: entry.mem, color: .cyan)
                metricRow(title: "DISK", value: entry.disk, color: .orange)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if !entry.history.isEmpty {
                chart
            }

            if !entry.processes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.processes) { process in
                        HStack(spacing: 6) {
                            Text(process.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(String(format: "%.1f%%", process.cpuPercent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart(Array(entry.history.enumerated()), id: \.offset) { index, sample in
            LineMark(
                x: .value("Time", index),
                y: .value("CPU", sample.cpu),
                series: .value("Metric", "CPU")
            )
            .foregroundStyle(.green)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", index),
                y: .value("MEM", sample.mem),
                series: .value("Metric", "MEM")
            )
            .foregroundStyle(.cyan)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", index),
                y: .value("DISK", sample.disk),
                series: .value("Metric", "DISK")
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .frame(height: 62)
    }

    private func metricRow(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(String(format: "%3.0f%%", value))
                .foregroundStyle(.primary)
        }
    }
}
