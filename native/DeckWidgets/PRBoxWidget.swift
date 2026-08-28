import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct PRBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    /// One line for two providers — see `PRFetchChip`.
    let chip: String?
    let authoredCount: Int
    let reviewingCount: Int
    let authoredCapped: Bool
    let reviewingCapped: Bool
    let pullRequests: [PullRequestItem]
    /// Which Azure projects could not be read, when the others could.
    let note: String?
    let settings: PRBoxSettings
}

// MARK: - Provider
//
// Pull requests arrive via the agent-pumped snapshot (the widget sandbox has
// no network entitlement). A snapshot that exists is always rendered — data is
// never blanked for being old; the age hint past 5 min and the fetch chip
// carry the honesty instead.

struct PRBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> PRBoxEntry {
        PRBoxEntry(
            date: .now,
            available: true,
            stale: false,
            writtenAt: .now,
            chip: nil,
            authoredCount: 2,
            reviewingCount: 3,
            authoredCapped: false,
            reviewingCapped: false,
            pullRequests: [
                PullRequestItem(
                    id: "github:deck#41", number: 41, title: "Review queue widget",
                    repo: "deck", role: .authored, provider: .github, isDraft: false,
                    createdAt: .now.addingTimeInterval(-7200), url: ""
                ),
                PullRequestItem(
                    id: "azureDevOps:manifold#4397", number: 4397,
                    title: "Add Xcelerate to the connection UI",
                    repo: "manifold", role: .reviewing, provider: .azureDevOps, isDraft: false,
                    createdAt: .now.addingTimeInterval(-864_000), url: ""
                ),
                PullRequestItem(
                    id: "github:deck#38", number: 38, title: "wip: agent cadence",
                    repo: "deck", role: .authored, provider: .github, isDraft: true,
                    createdAt: .now.addingTimeInterval(-172_800), url: ""
                ),
            ],
            note: nil,
            settings: PRBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PRBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PRBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> PRBoxEntry {
        let snapshot = PRBoxSnapshotStore.load()
        let allSettings = DeckSettings.load()
        let settings = allSettings.prbox
        let now = Date()
        // A provider is on when it has an account. Reading `enabled` here would
        // render both providers as off forever: the picker replaced the toggle
        // and the migration clears it.
        let chip = PRFetchChip.text(
            github: FetchStatusStore.load(.prboxGitHub),
            azure: FetchStatusStore.load(.prboxAzure),
            githubEnabled: allSettings.prBoxGitHubIsOn,
            azureEnabled: allSettings.prBoxAzureIsOn,
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )

        guard let snapshot else {
            return PRBoxEntry(
                date: now, available: false, stale: false, writtenAt: nil, chip: chip,
                authoredCount: 0, reviewingCount: 0,
                authoredCapped: false, reviewingCapped: false,
                pullRequests: [], note: nil, settings: settings
            )
        }

        return PRBoxEntry(
            date: now,
            available: true,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            writtenAt: snapshot.writtenAt,
            chip: chip,
            authoredCount: snapshot.authoredCount,
            reviewingCount: snapshot.reviewingCount,
            authoredCapped: snapshot.authoredCapped,
            reviewingCapped: snapshot.reviewingCapped,
            pullRequests: snapshot.pullRequests,
            note: snapshot.note,
            settings: settings
        )
    }
}

// MARK: - Widget

struct PRBoxWidget: Widget {
    let kind = "PRBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRBoxProvider()) { entry in
            PRBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PRBox")
        .description("Your open pull requests and the ones waiting on your review, from GitHub and Azure DevOps.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct PRBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PRBoxEntry

    /// The small face has no rows, so the whole widget is the tap target and
    /// it opens the top pull request — the one the counts are about. Medium
    /// and large link per row instead, so a widget-wide URL there would
    /// hijack clicks meant for a specific row.
    private var smallDestination: URL? {
        guard family == .systemSmall else { return nil }
        return entry.pullRequests.first.flatMap { PRFormatting.destination(for: $0) }
    }

    var body: some View {
        Group {
            if entry.available {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    listView(face: .medium)
                default:
                    listView(face: .large)
                }
            } else {
                unavailableView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(smallDestination)
    }

    /// No snapshot at all: either nothing is configured yet or the agent has
    /// not written one. The chip already distinguishes those.
    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No pull requests")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Turn on a provider in Deck settings.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Counts only. Three truncated titles at this width are unreadable, and
    /// the two numbers are the glanceable fact.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerLine
            VStack(alignment: .leading, spacing: 6) {
                countRow(
                    label: "MINE",
                    value: PRFormatting.countLabel(entry.authoredCount, capped: entry.authoredCapped),
                    color: entry.settings.mineColor.color
                )
                countRow(
                    label: "REVIEW",
                    value: PRFormatting.countLabel(entry.reviewingCount, capped: entry.reviewingCapped),
                    color: entry.settings.reviewColor.color
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func listView(face: PRBoxFace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            countsRow
            if entry.pullRequests.isEmpty {
                Text("No open PRs")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if entry.settings.showList {
                prList(maxCount: entry.settings.rowCount(for: face))
            }
            Spacer(minLength: 0)
        }
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // No widget title — the counts below lead the face; the chip and
            // the age hint stay right-aligned where they already were.
            Spacer(minLength: 4)
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

    private var countsRow: some View {
        HStack(spacing: 14) {
            countRow(
                label: "MINE",
                value: PRFormatting.countLabel(entry.authoredCount, capped: entry.authoredCapped),
                color: entry.settings.mineColor.color
            )
            countRow(
                label: "REVIEW",
                value: PRFormatting.countLabel(entry.reviewingCount, capped: entry.reviewingCapped),
                color: entry.settings.reviewColor.color
            )
            Spacer(minLength: 0)
        }
    }

    private func countRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func prList(maxCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("QUEUE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            ForEach(Array(entry.pullRequests.prefix(maxCount).enumerated()), id: \.offset) { _, pr in
                // A row whose provider gave no usable URL stays plain text
                // rather than becoming a link that goes nowhere.
                if let destination = PRFormatting.destination(for: pr) {
                    Link(destination: destination) { row(for: pr) }
                        .buttonStyle(.plain)
                } else {
                    row(for: pr)
                }
            }
            // Which projects are missing from the queue above. The small face
            // has no room, and its chip already covers a provider failing
            // outright.
            if let note = entry.note, family != .systemSmall {
                Text(note)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func row(for pr: PullRequestItem) -> some View {
        HStack(spacing: 6) {
            // The dot is the role, not the provider: the role is what you do
            // about the row.
            Circle()
                .fill(pr.role == .authored ? entry.settings.mineColor.color : entry.settings.reviewColor.color)
                .frame(width: 7, height: 7)
            // A two-letter tag rather than a logo: neither provider has an SF
            // Symbol, and vendoring brand marks into an Apache-2.0 repo is a
            // question this widget does not need to answer.
            Text(tag(for: pr.provider))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            // A repository name is only unique within its project, so with an
            // account covering several the bare name can be ambiguous. Off by
            // default: with one project it is noise on every row.
            Text(rowLabel(for: pr))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Text(pr.isDraft ? "\(pr.title) · DRAFT" : pr.title)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(pr.isDraft ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(PRFormatting.age(from: pr.createdAt, to: entry.date))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func rowLabel(for pr: PullRequestItem) -> String {
        guard entry.settings.azure.showProject,
              let project = pr.project, !project.isEmpty
        else { return "\(pr.repo) #\(pr.number)" }
        return "\(project)/\(pr.repo) #\(pr.number)"
    }

    private func tag(for provider: PRProvider) -> String {
        switch provider {
        case .github: "GH"
        case .azureDevOps: "AZ"
        case .unknown: "··"
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
