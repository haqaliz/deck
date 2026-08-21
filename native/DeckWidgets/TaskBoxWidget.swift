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
    /// Every open item assigned to the user — may exceed `tasks.count`.
    let totalCount: Int
    let sprint: String?
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
            totalCount: 12,
            sprint: "Sprint 1",
            tasks: [
                sample("1001", "Sample backlog item", "New", "Product Backlog Item", now),
                sample("1002", "Sample task in progress", "In Progress", "Task", now),
                sample("1003", "Sample bug", "Committed", "Bug", now),
                sample("1004", "Sample task", "To Do", "Task", now),
            ],
            settings: TaskBoxSettings()
        )
    }

    private func sample(
        _ id: String, _ title: String, _ state: String, _ type: String, _ now: Date
    ) -> TaskItem {
        TaskItem(id: id, title: title, state: state, itemType: type, url: "",
                 provider: .azureDevOps, changedAt: now)
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
                chip: chip, scope: "", totalCount: 0, sprint: nil,
                tasks: [], settings: settings
            )
        }

        return TaskBoxEntry(
            date: now,
            available: true,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            writtenAt: snapshot.writtenAt,
            chip: chip,
            scope: snapshot.scope,
            totalCount: snapshot.totalCount,
            sprint: snapshot.sprint,
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

    /// A medium widget is ~170pt tall: past six rows the list would be clipped
    /// by the frame rather than by the setting, so it is capped here while the
    /// large face honours the full count.
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            legendRow
            taskList(maxCount: min(entry.settings.taskCount, 6))
            Spacer(minLength: 0)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            legendRow
            taskList(maxCount: entry.settings.taskCount)
            Spacer(minLength: 0)
        }
    }

    /// Left: how much is on your plate. Right: the sprint you are in.
    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(TaskFormatting.totalLine(totalCount: entry.totalCount))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 4)
            if let chip = entry.chip {
                Text(chip)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // A small face has room for one thing on the right: the reason a
            // fetch failed beats the sprint number.
            if let sprint = entry.sprint, !(family == .systemSmall && entry.chip != nil) {
                Text(sprint)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if entry.stale, let writtenAt = entry.writtenAt {
                Text("\u{00B7} \(timeString(writtenAt))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var legendRow: some View {
        if entry.settings.showLegend && !entry.tasks.isEmpty {
            Divider()
            HStack(spacing: 10) {
                ForEach(visibleLanes, id: \.self) { lane in
                    laneCount(lane)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// "Done" and "Other" are only worth a chip when something actually landed
    /// there — otherwise they are permanent zeroes explaining nothing. The open
    /// lanes always show, so the legend keeps a stable width.
    private var visibleLanes: [TaskLane] {
        TaskLane.allCases.filter { lane in
            switch lane {
            case .done, .other: (counts[lane] ?? 0) > 0
            default: true
            }
        }
    }

    private var counts: [TaskLane: Int] {
        TaskFormatting.laneCounts(tasks: entry.tasks, mapping: entry.settings.stateMapping)
    }

    private func laneCount(_ lane: TaskLane) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(entry.settings.color(for: lane).color)
                .frame(width: 7, height: 7)
            Text(lane.label)
                .foregroundStyle(.secondary)
            Text("\(counts[lane] ?? 0)")
                .foregroundStyle(.primary)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        // Labels never wrap: an "OVERDUE" that broke across two lines is what
        // this row looked like before.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
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
                taskRow(task)
            }
        }
    }

    /// Row shape: state dot, completion slot, work item number, then the title.
    /// Only finished rows carry a glyph; the rest leave the slot empty so every
    /// number stays in one column.
    private func taskRow(_ task: TaskItem) -> some View {
        let lane = entry.settings.stateMapping.lane(for: task.state)
        return HStack(spacing: 5) {
            Circle()
                .fill(entry.settings.color(for: lane).color)
                .frame(width: 7, height: 7)
            Group {
                if lane.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(entry.settings.color(for: lane).color)
                }
            }
            .frame(width: 10)
            Text(task.id)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(task.title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 2)
                // Finished work reads as finished rather than as another
                // outstanding row.
                .strikethrough(lane.isComplete, color: .secondary)
                .foregroundStyle(lane.isComplete ? Color.secondary : Color.primary)
            Spacer(minLength: 0)
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
