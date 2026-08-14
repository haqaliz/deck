import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ShipBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let repo: String
    let runs: [ShipRun]
    let settings: ShipBoxSettings
}

// MARK: - Provider
//
// Runs arrive via the agent-pumped snapshot (the widget sandbox has no network
// entitlement). Staleness windows: fresh <5 min, stale hint 5–30 min,
// unavailable >30 min.

struct ShipBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShipBoxEntry {
        ShipBoxEntry(
            date: .now,
            available: true,
            stale: false,
            repo: "haqaliz/deck",
            runs: [
                ShipRun(name: "Deck", runNumber: 15, branch: "master", status: .success, createdAt: .now.addingTimeInterval(-192), updatedAt: .now, htmlURL: ""),
                ShipRun(name: "Deck", runNumber: 14, branch: "master", status: .failure, createdAt: .now.addingTimeInterval(-600), updatedAt: .now.addingTimeInterval(-408), htmlURL: ""),
                ShipRun(name: "Deck", runNumber: 13, branch: "feat/homebox/aliz", status: .running, createdAt: .now.addingTimeInterval(-60), updatedAt: .now, htmlURL: ""),
            ],
            settings: ShipBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ShipBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShipBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> ShipBoxEntry {
        let snapshot = ShipBoxSnapshotStore.load()
        let settings = DeckSettings.load().shipbox
        let now = Date()

        guard let snapshot else {
            return ShipBoxEntry(
                date: now,
                available: false,
                stale: false,
                repo: "",
                runs: [],
                settings: settings
            )
        }

        let age = now.timeIntervalSince(snapshot.writtenAt)
        let available = age <= 30 * 60
        let stale = age > 5 * 60

        return ShipBoxEntry(
            date: now,
            available: available,
            stale: stale,
            repo: snapshot.repo,
            runs: snapshot.runs,
            settings: settings
        )
    }
}

// MARK: - Widget

struct ShipBoxWidget: Widget {
    let kind = "ShipBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShipBoxProvider()) { entry in
            ShipBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ShipBox")
        .description("GitHub Actions run status for a repo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct ShipBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShipBoxEntry

    var body: some View {
        Group {
            if entry.available {
                if entry.runs.isEmpty {
                    emptyView
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
            } else {
                unavailableView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ShipBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No build data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Paste a repo + token in Deck settings.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            Text("No runs yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            runsList(maxCount: 2)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            runsList(maxCount: entry.settings.runCount)
            Spacer(minLength: 0)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            if entry.settings.showList && !entry.runs.isEmpty {
                Divider()
                totalsRow
            }
            runsList(maxCount: entry.settings.runCount)
            Spacer(minLength: 0)
        }
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.repo.isEmpty ? "ShipBox" : entry.repo)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !entry.runs.isEmpty {
                Text(RunFormatting.totalsLine(for: entry.runs))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if entry.stale, let writtenAt = snapshotWrittenAt {
                Text("· \(timeString(writtenAt))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var snapshotWrittenAt: Date? {
        ShipBoxSnapshotStore.load()?.writtenAt
    }

    private var totalsRow: some View {
        HStack(spacing: 10) {
            statusCount(label: "PASS", count: totals.success, color: entry.settings.successColor.color)
            statusCount(label: "FAIL", count: totals.failure, color: entry.settings.failureColor.color)
            statusCount(label: "RUN", count: totals.running, color: entry.settings.runningColor.color)
            statusCount(label: "QUEUED", count: totals.queued, color: entry.settings.queuedColor.color)
            Spacer()
        }
    }

    private var totals: RunFormatting.Totals {
        RunFormatting.totals(for: entry.runs)
    }

    private func statusCount(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .foregroundStyle(.primary)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private func runsList(maxCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.settings.showList {
                Text("RUNS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            ForEach(Array(entry.runs.prefix(maxCount).enumerated()), id: \.offset) { _, run in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: run.status))
                        .frame(width: 7, height: 7)
                    Text("\(run.name) #\(run.runNumber)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(RunFormatting.detail(for: run))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(run.status == .failure ? Color.primary : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func color(for status: ShipStatus) -> Color {
        switch status {
        case .queued: entry.settings.queuedColor.color
        case .running: entry.settings.runningColor.color
        case .success: entry.settings.successColor.color
        case .failure: entry.settings.failureColor.color
        case .neutral: Color.secondary
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = Self.timeFormatter
        return formatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
