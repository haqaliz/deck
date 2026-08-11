import WidgetKit
import SwiftUI
import Charts
import OSLog
import AppIntents

private let liveboxLog = Logger(subsystem: "com.deck.app.widgets", category: "LiveBox")

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
//
// The entry only carries stable config; live data is sampled at render time
// inside a TimelineView (5s ticks), which WidgetKit does not throttle.

struct LiveBoxEntry: TimelineEntry {
    let date: Date
    let settings: LiveBoxSettings
    let processMode: String
}

// MARK: - Live sampler (runs on every 5s render tick)

enum LiveBoxSampler {
    private static var previousTicks: CpuTicks?

    static func sample() -> (cpu: Double, mem: Double, disk: Double) {
        let cpuDelta = cpuUsagePercent(previous: previousTicks)
        previousTicks = cpuDelta.current
        return (cpuDelta.usage, memoryUsagePercent(), diskUsagePercent())
    }

    static func processes(mode: String) -> [TopProcess] {
        guard
            let snapshot = ProcessSnapshotStore.load(),
            snapshot.writtenAt.timeIntervalSinceNow > -90
        else { return [] }
        return mode == LiveBoxProcessMode.memory
            ? snapshot.processes.sorted { $0.memPercent > $1.memPercent }
            : snapshot.processes
    }

    static func history(appending sample: (cpu: Double, mem: Double, disk: Double)) -> [Sample] {
        var history = HistoryStore.load()
        history.append(Sample(cpu: sample.cpu, mem: sample.mem, disk: sample.disk))
        if history.count > HistoryStore.capacity {
            history.removeFirst(history.count - HistoryStore.capacity)
        }
        HistoryStore.save(history)
        return history
    }
}

// MARK: - Provider

struct LiveBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> LiveBoxEntry {
        LiveBoxEntry(
            date: .now,
            settings: LiveBoxSettings(),
            processMode: LiveBoxProcessMode.current
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveBoxEntry>) -> Void) {
        // A single long-lived entry: the view's TimelineView drives 5s data
        // refreshes; regeneration only refreshes settings/mode changes.
        completion(Timeline(
            entries: [makeEntry()],
            policy: .after(Date().addingTimeInterval(60))
        ))
    }

    private func makeEntry() -> LiveBoxEntry {
        let settings = DeckSettings.load().livebox
        liveboxLog.info("timeline generated settings.showChart=\(settings.showChart) settings.showProcesses=\(settings.showProcesses)")
        return LiveBoxEntry(
            date: .now,
            settings: settings,
            processMode: LiveBoxProcessMode.current
        )
    }
}

// MARK: - Process mode (CPU/MEM tabs, persisted in the extension container)

enum LiveBoxProcessMode {
    static let key = "LiveBox.processMode"
    static let cpu = "cpu"
    static let memory = "memory"

    static var current: String {
        UserDefaults.standard.string(forKey: key) ?? cpu
    }

    static func set(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: key)
    }
}

struct SetProcessModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sort processes"

    @Parameter(title: "Mode")
    var mode: String

    init() {}
    init(mode: String) { self.mode = mode }

    func perform() async throws -> some IntentResult {
        LiveBoxProcessMode.set(mode)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Widget

struct LiveBoxWidget: Widget {
    let kind = "LiveBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LiveBoxProvider()) { entry in
            LiveBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("LiveBox")
        .description("CPU, memory, disk usage with a live chart and top processes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable()
    }
}

// MARK: - Views

struct LiveBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LiveBoxEntry

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let sample = LiveBoxSampler.sample()
            LiveBoxFace(
                family: family,
                settings: entry.settings,
                processMode: entry.processMode,
                date: context.date,
                cpu: sample.cpu,
                mem: sample.mem,
                disk: sample.disk,
                processes: LiveBoxSampler.processes(mode: entry.processMode),
                history: LiveBoxSampler.history(appending: sample)
            )
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

/// Renders one 5s tick with freshly sampled values.
struct LiveBoxFace: View {
    let family: WidgetFamily
    let settings: LiveBoxSettings
    let processMode: String
    let date: Date
    let cpu: Double
    let mem: Double
    let disk: Double
    let processes: [TopProcess]
    let history: [Sample]

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
    }


    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.showCPU {
                metricRow(title: "CPU", value: cpu, color: settings.cpuColor.color)
            }
            if settings.showMEM {
                metricRow(title: "MEM", value: mem, color: settings.memColor.color)
            }
            if settings.showDisk {
                metricRow(title: "DISK", value: disk, color: settings.diskColor.color)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                if settings.showCPU {
                    metricRow(title: "CPU", value: cpu, color: settings.cpuColor.color)
                }
                if settings.showMEM {
                    metricRow(title: "MEM", value: mem, color: settings.memColor.color)
                }
                if settings.showDisk {
                    metricRow(title: "DISK", value: disk, color: settings.diskColor.color)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if settings.showChart && !history.isEmpty {
                chart
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                if settings.showCPU {
                    metricRow(title: "CPU", value: cpu, color: settings.cpuColor.color)
                }
                if settings.showMEM {
                    metricRow(title: "MEM", value: mem, color: settings.memColor.color)
                }
                if settings.showDisk {
                    metricRow(title: "DISK", value: disk, color: settings.diskColor.color)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if settings.showChart && !history.isEmpty {
                chart
            }

            if settings.showProcesses && !processes.isEmpty {
                Divider()
                processList
            }

            Spacer(minLength: 0)
        }
    }

    private var currentProcesses: [TopProcess] {
        processMode == LiveBoxProcessMode.memory
            ? processes.sorted { $0.memPercent > $1.memPercent }
            : processes
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("TOP PROCESSES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                ProcessTab(mode: processMode)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(currentProcesses.prefix(settings.processCount).enumerated()), id: \.offset) { _, process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                processMode == LiveBoxProcessMode.memory
                                    ? .secondary.opacity(0.8)
                                    : settings.cpuColor.color
                            )
                        Text(String(format: "%.1f%%", process.memPercent))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                processMode == LiveBoxProcessMode.memory
                                    ? settings.memColor.color
                                    : .secondary.opacity(0.8)
                            )
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart(Array(history.enumerated()), id: \.offset) { index, sample in
            if settings.showCPU {
                LineMark(
                    x: .value("Time", index),
                    y: .value("CPU", sample.cpu),
                    series: .value("Metric", "CPU")
                )
                .foregroundStyle(settings.cpuColor.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if settings.showMEM {
                LineMark(
                    x: .value("Time", index),
                    y: .value("MEM", sample.mem),
                    series: .value("Metric", "MEM")
                )
                .foregroundStyle(settings.memColor.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if settings.showDisk {
                LineMark(
                    x: .value("Time", index),
                    y: .value("DISK", sample.disk),
                    series: .value("Metric", "DISK")
                )
                .foregroundStyle(settings.diskColor.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
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

/// CPU | MEM segmented tabs (matches the window widget's ProcessTab).
private struct ProcessTab: View {
    let mode: String

    var body: some View {
        HStack(spacing: 2) {
            tabButton("CPU", LiveBoxProcessMode.cpu)
            tabButton("MEM", LiveBoxProcessMode.memory)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(0.08))
        )
    }

    private func tabButton(_ title: String, _ target: String) -> some View {
        Button(intent: SetProcessModeIntent(mode: target)) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(mode == target ? Color.black : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(mode == target ? .white : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
