import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct TaskBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    /// One line explaining the last fetch attempt, or nil when all is well.
    let chip: String?
    let scope: String
    let tasks: [TaskItem]
    let settings: TaskBoxSettings
}

// MARK: - Provider
//
// Work items arrive via the agent-pumped snapshot (the widget sandbox has no
// network entitlement). A snapshot that exists is always rendered — data is
// never blanked for being old; the age hint past 5 min and the fetch-status
// chip carry the honesty instead.

struct TaskBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskBoxEntry {
        // Deliberately synthetic: the placeholder is what the widget gallery
        // puts on screen, so it must not look like anyone's real work.
        let now = Date.now
        return TaskBoxEntry(
            date: now,
            available: true,
            stale: false,
            writtenAt: now,
            chip: nil,
            scope: "Contoso",
            tasks: [
                sample("1", "Sample overdue task", days: -2, now: now),
                sample("2", "Sample task due today", days: 0, now: now),
                sample("3", "Sample upcoming task", days: 3, now: now),
                sample("4", "Sample undated task", days: nil, now: now),
            ],
            settings: TaskBoxSettings()
        )
    }

    private func sample(_ id: String, _ title: String, days: Int?, now: Date) -> TaskItem {
        TaskItem(
            id: id, title: title, state: "Active", itemType: "Task", url: "",
            provider: .azureDevOps,
            dueDate: days.map { now.addingTimeInterval(Double($0) * 86_400) },
            dueSource: days == nil ? .unset : .explicit,
            changedAt: now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> TaskBoxEntry {
        let snapshot = TaskBoxSnapshotStore.load()
        let settings = DeckSettings.load().taskbox
        let now = Date()
        let chip = FetchChip.text(
            source: .taskbox,
            status: FetchStatusStore.load(.taskbox),
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )

        guard let snapshot else {
            return TaskBoxEntry(
                date: now, available: false, stale: false, writtenAt: nil,
                chip: chip, scope: "", tasks: [], settings: settings
            )
        }

        return TaskBoxEntry(
            date: now,
            available: true,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            writtenAt: snapshot.writtenAt,
            chip: chip,
            scope: snapshot.scope,
            tasks: snapshot.tasks,
            settings: settings
        )
    }
}

// MARK: - Widget

struct TaskBoxWidget: Widget {
    let kind = "TaskBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskBoxProvider()) { entry in
            TaskBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TaskBox")
        .description("Azure DevOps work items assigned to you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct TaskBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskBoxEntry

    private var calendar: Calendar { .current }

    var body: some View {
        Group {
            if entry.available {
                if entry.tasks.isEmpty {
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
            Text("TaskBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No task data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Add org, project + PAT in Deck settings.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// The fetch worked and the query matched nothing — a real answer, and a
    /// different one from "no data".
    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            Text("Nothing assigned")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            taskList(maxCount: 2)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            taskList(maxCount: entry.settings.taskCount)
            Spacer(minLength: 0)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            if entry.settings.showList && !entry.tasks.isEmpty {
                Divider()
                totalsRow
            }
            taskList(maxCount: entry.settings.taskCount)
            Spacer(minLength: 0)
        }
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.scope.isEmpty ? "TaskBox" : entry.scope)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            // A small face has room for one hint, not two: the reason wins.
            if !entry.tasks.isEmpty && !(family == .systemSmall && entry.chip != nil) {
                Text(TaskFormatting.countsLine(
                    tasks: entry.tasks, now: entry.date, calendar: calendar,
                    soonWindowDays: entry.settings.soonWindowDays
                ))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            }
            if let chip = entry.chip {
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
            bucketCount(label: "OVERDUE", count: counts.overdue, color: entry.settings.overdueColor.color)
            bucketCount(label: "TODAY", count: counts.today, color: entry.settings.todayColor.color)
            bucketCount(label: "SOON", count: counts.soon, color: entry.settings.soonColor.color)
            bucketCount(label: "LATER", count: counts.later, color: entry.settings.laterColor.color)
            Spacer()
        }
    }

    private var counts: TaskFormatting.Counts {
        TaskFormatting.counts(
            tasks: entry.tasks, now: entry.date, calendar: calendar,
            soonWindowDays: entry.settings.soonWindowDays
        )
    }

    private func bucketCount(label: String, count: Int, color: Color) -> some View {
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

    private func taskList(maxCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.settings.showList {
                Text("TASKS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            ForEach(Array(entry.tasks.prefix(maxCount).enumerated()), id: \.offset) { _, task in
                let bucket = TaskFormatting.bucket(
                    due: task.dueDate, now: entry.date, calendar: calendar,
                    soonWindowDays: entry.settings.soonWindowDays
                )
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: bucket))
                        .frame(width: 7, height: 7)
                    Text(task.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(TaskFormatting.relativeDay(
                        due: task.dueDate, now: entry.date, calendar: calendar
                    ))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(urgent(bucket) ? Color.primary : Color.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    private func urgent(_ bucket: DueBucket) -> Bool {
        bucket == .overdue || bucket == .today
    }

    private func color(for bucket: DueBucket) -> Color {
        switch bucket {
        case .overdue: entry.settings.overdueColor.color
        case .today: entry.settings.todayColor.color
        case .soon: entry.settings.soonColor.color
        case .later: entry.settings.laterColor.color
        // Undated has no picker, matching ShipBox's neutral status.
        case .undated: Color.secondary
        }
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
}
