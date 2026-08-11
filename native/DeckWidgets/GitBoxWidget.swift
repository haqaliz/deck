import WidgetKit
import SwiftUI
import Charts

// MARK: - Timeline entry

struct GitBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let todayCount: Int
    let streak: Int
    let days: [GitBoxSnapshot.DayCount]
    let repos: [GitBoxSnapshot.RepoInfo]
    let settings: GitBoxSettings
}

// MARK: - Provider

struct GitBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> GitBoxEntry {
        GitBoxEntry(
            date: .now,
            available: true,
            todayCount: 12,
            streak: 5,
            days: (0..<15).map { i in
                GitBoxSnapshot.DayCount(day: "day\(i)", count: Int((i % 5) * 3))
            },
            repos: [
                GitBoxSnapshot.RepoInfo(shortName: "deck", path: "/Users/aliz/dev/at/deck", todayCount: 8),
                GitBoxSnapshot.RepoInfo(shortName: "manifold", path: "/Users/aliz/dev/manifold/manifold", todayCount: 4),
            ],
            settings: GitBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GitBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GitBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> GitBoxEntry {
        let snapshot = GitBoxSnapshotStore.load()
        let settings = DeckSettings.load().gitbox
        guard let snapshot, snapshot.writtenAt.timeIntervalSinceNow > -300 else {
            return GitBoxEntry(
                date: .now,
                available: false,
                todayCount: 0,
                streak: 0,
                days: [],
                repos: [],
                settings: settings
            )
        }
        return GitBoxEntry(
            date: .now,
            available: true,
            todayCount: snapshot.todayCount,
            streak: snapshot.streak,
            days: snapshot.days,
            repos: snapshot.repos,
            settings: settings
        )
    }
}

// MARK: - Widget

struct GitBoxWidget: Widget {
    let kind = "GitBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GitBoxProvider()) { entry in
            GitBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("GitBox")
        .description("Commits per day for the last 14 days with today's count, streak and active repos.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct GitBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GitBoxEntry

    var body: some View {
        Group {
            if !entry.available {
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
            Text("GitBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No git data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Check repo paths in Deck settings.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            countRow(title: "TODAY", value: entry.todayCount, color: entry.settings.todayColor.color)
            countRow(title: "STREAK", value: entry.streak, color: entry.settings.barColor.color)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                countRow(title: "TODAY", value: entry.todayCount, color: entry.settings.todayColor.color)
                countRow(title: "STREAK", value: entry.streak, color: entry.settings.barColor.color)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showChart && !entry.days.isEmpty {
                chart
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                countRow(title: "TODAY", value: entry.todayCount, color: entry.settings.todayColor.color)
                countRow(title: "STREAK", value: entry.streak, color: entry.settings.barColor.color)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showChart && !entry.days.isEmpty {
                chart
            }

            if entry.settings.showRepos && !entry.repos.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("REPOS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    ForEach(Array(entry.repos.prefix(entry.settings.repoCount).enumerated()), id: \.offset) { _, repo in
                        HStack(spacing: 6) {
                            Text(repo.shortName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text("\(repo.todayCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(entry.settings.todayColor.color)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var chart: some View {
        Chart(Array(entry.days.enumerated()), id: \.offset) { index, day in
            BarMark(
                x: .value("Day", index),
                y: .value("Commits", day.count)
            )
            .foregroundStyle(
                day.day == entry.days.last?.day
                    ? entry.settings.todayColor.color
                    : entry.settings.barColor.color
            )
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 70)
    }

    private func countRow(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .foregroundStyle(.primary)
        }
    }
}
