import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ShipBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    /// One line explaining the last fetch attempt, or nil when all is well.
    let chip: String?
    /// The repos this snapshot covers, in display order.
    let repos: [String]
    /// Names the repos that failed while others succeeded, or nil.
    let note: String?
    let runs: [ShipRun]
    let settings: ShipBoxSettings
}

// MARK: - Provider
//
// Runs arrive via the agent-pumped snapshot (the widget sandbox has no network
// entitlement). A snapshot that exists is always rendered — data is never
// blanked for being old; the age hint past 5 min and the fetch-status chip
// carry the honesty instead.

struct ShipBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShipBoxEntry {
        ShipBoxEntry(
            date: .now,
            available: true,
            stale: false,
            writtenAt: .now,
            chip: nil,
            repos: ["haqaliz/deck", "haqaliz/cyclo", "haqaliz/pong"],
            note: nil,
            runs: [
                ShipRun(repo: "haqaliz/deck", name: "Deck", runNumber: 15, branch: "master", status: .success, createdAt: .now.addingTimeInterval(-192), updatedAt: .now, htmlURL: ""),
                ShipRun(repo: "haqaliz/cyclo", name: "CI", runNumber: 88, branch: "main", status: .failure, createdAt: .now.addingTimeInterval(-600), updatedAt: .now.addingTimeInterval(-408), htmlURL: ""),
                ShipRun(repo: "haqaliz/pong", name: "Build", runNumber: 7, branch: "main", status: .running, createdAt: .now.addingTimeInterval(-60), updatedAt: .now, htmlURL: ""),
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
        let chip = FetchChip.text(
            source: .shipbox,
            status: FetchStatusStore.load(.shipbox),
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )

        guard let snapshot else {
            return ShipBoxEntry(
                date: now,
                available: false,
                stale: false,
                writtenAt: nil,
                chip: chip,
                repos: [],
                note: nil,
                runs: [],
                settings: settings
            )
        }

        return ShipBoxEntry(
            date: now,
            available: true,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            writtenAt: snapshot.writtenAt,
            chip: chip,
            repos: snapshot.repos,
            note: snapshot.note,
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
        .description("GitHub Actions run status across your repos.")
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
        // The small face's rows are too tight to be individual targets, so the
        // whole widget opens the newest run instead.
        .widgetURL(family == .systemSmall ? entry.runs.first.flatMap { DeckLink.webURL(from: $0.htmlURL) } : nil)
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ShipBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No build data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Paste a GitHub token in Deck settings.")
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

    /// One repo names itself; several are counted. Naming one of five would be
    /// arbitrary, and listing them all would eat the row.
    private var headerTitle: String {
        switch entry.repos.count {
        case 0: return "ShipBox"
        case 1: return entry.repos[0]
        default: return "\(entry.repos.count) repos"
        }
    }

    /// The small face has room for one hint, not two.
    ///
    /// The chip used to win unconditionally, which let a 2-row merged list
    /// render two green runs from a busy repo while another repo was red and
    /// the fail count — the only thing that would have shown it — was
    /// suppressed. A red count is a fact about the data; the chip is a fact
    /// about the fetch, and bad news about the data wins (PRD C4).
    private var smallShowsTotals: Bool {
        entry.chip == nil || RunFormatting.totals(for: entry.runs).failure > 0
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(headerTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !entry.runs.isEmpty && !(family == .systemSmall && !smallShowsTotals) {
                Text(RunFormatting.totalsLine(for: entry.runs))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if let chip = entry.chip, !(family == .systemSmall && smallShowsTotals) {
                Text(chip)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if entry.stale, let writtenAt = entry.writtenAt {
                Text("· \(timeString(writtenAt))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
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
                // A run with no usable URL stays plain text rather than
                // becoming a link that goes nowhere.
                if let destination = DeckLink.webURL(from: run.htmlURL) {
                    Link(destination: destination) { row(for: run) }
                        .buttonStyle(.plain)
                } else {
                    row(for: run)
                }
            }
            if let note = entry.note, family != .systemSmall {
                Text(note)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func row(for run: ShipRun) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: run.status))
                .frame(width: 7, height: 7)
            // The repo takes the workflow's place: with several repos in one
            // list, which repo a run belongs to matters more than which
            // workflow produced it, and both will not fit at 11pt.
            Text("\(label(for: run)) #\(run.runNumber)")
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

    private var repoLabels: [String: String] {
        ShipBoxLabels.labels(for: entry.repos)
    }

    /// Falls back to the workflow name for a snapshot with no repos at all —
    /// only reachable from a hand-edited file, but a blank row is worse.
    private func label(for run: ShipRun) -> String {
        repoLabels[run.repo] ?? (run.repo.isEmpty ? run.name : run.repo)
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
