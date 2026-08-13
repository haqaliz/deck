import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ClipBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let items: [ClipItem]
    let settings: ClipBoxSettings
}

// MARK: - Provider

struct ClipBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipBoxEntry {
        ClipBoxEntry(
            date: .now,
            available: true,
            items: [
                ClipItem(
                    id: UUID(),
                    date: .now.addingTimeInterval(-120),
                    kind: .text,
                    preview: "OpenBox token usage: 12.4k in, 3.1k out",
                    detail: "",
                    content: "OpenBox token usage: 12.4k in, 3.1k out"
                ),
                ClipItem(
                    id: UUID(),
                    date: .now.addingTimeInterval(-600),
                    kind: .file,
                    preview: "README.md",
                    detail: "file:///Users/aliz/dev/at/deck/README.md",
                    content: "file:///Users/aliz/dev/at/deck/README.md"
                ),
                ClipItem(
                    id: UUID(),
                    date: .now.addingTimeInterval(-1800),
                    kind: .image,
                    preview: "Image",
                    detail: "1.2 MB",
                    content: nil
                ),
            ],
            settings: ClipBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ClipBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> ClipBoxEntry {
        let snapshot = ClipBoxSnapshotStore.load()
        let settings = DeckSettings.load().clipbox
        guard let snapshot, snapshot.writtenAt.timeIntervalSinceNow > -300 else {
            return ClipBoxEntry(date: .now, available: false, items: [], settings: settings)
        }
        return ClipBoxEntry(date: .now, available: true, items: snapshot.items, settings: settings)
    }
}

// MARK: - Widget

struct ClipBoxWidget: Widget {
    let kind = "ClipBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClipBoxProvider()) { entry in
            ClipBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ClipBox")
        .description("Clipboard history: recent copies with previews, local only.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct ClipBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClipBoxEntry

    var body: some View {
        Group {
            if !entry.available {
                unavailableView
            } else if entry.items.isEmpty {
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
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ClipBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No clipboard data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Check that the Deck agent is running.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ClipBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No copies yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Copied items appear here.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        rows(limit: 2, previewLines: 1)
    }

    private var mediumView: some View {
        rows(limit: 3, previewLines: 1)
    }

    private var largeView: some View {
        rows(limit: max(entry.settings.historyCount, 1), previewLines: 2)
    }

    private func rows(limit: Int, previewLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("CLIPBOX")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                Text("\(entry.items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if entry.settings.showList {
                ForEach(Array(entry.items.prefix(limit).enumerated()), id: \.element.id) { _, item in
                    row(item, previewLines: previewLines)
                }
            } else {
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ item: ClipItem, previewLines: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(color(for: item.kind))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(item.preview)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(previewLines)
                        .truncationMode(.tail)
                    if !item.detail.isEmpty {
                        Text("· \(item.detail)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(relativeTime(item.date))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for kind: ClipKind) -> Color {
        switch kind {
        case .text: entry.settings.textColor.color
        case .image: entry.settings.imageColor.color
        case .file: entry.settings.fileColor.color
        case .other: entry.settings.otherColor.color
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        return switch seconds {
        case ..<60: "now"
        case ..<3600: "\(seconds / 60)m ago"
        case ..<86400: "\(seconds / 3600)h ago"
        default: "\(seconds / 86400)d ago"
        }
    }
}
