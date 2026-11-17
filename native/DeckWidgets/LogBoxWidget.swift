import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct LogBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    let chip: String?
    let snapshot: LogBoxSnapshot?
    let settings: LogBoxSettings
    /// Kibana's base. Empty when no Elastic account is picked.
    let uiURL: String
}

// MARK: - Provider

struct LogBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogBoxEntry {
        LogBoxEntry(
            date: .now, available: true, stale: false, writtenAt: .now, chip: nil,
            snapshot: LogBoxSnapshot(
                accountID: "preview", environment: LogEnvironment.prd.rawValue,
                writtenAt: .now, slowUpdatedAt: .now, smallMinutes: 15, largeMinutes: 1440,
                errorSmall: 33, warnSmall: 36651, errorLarge: 5077, warnLarge: 1876801,
                trend: (0..<36).map {
                    LogBoxPoint(at: .now.addingTimeInterval(Double($0) * 1800), count: $0 % 7)
                },
                services: [LogBoxCount(name: "jobrunner", count: 4203)],
                templates: [LogBoxCount(name: "Feed drain failed for {ConnectionId}", count: 439)],
                lastErrorAt: .now, recent: [], note: nil
            ),
            settings: LogBoxSettings(), uiURL: "https://kibana.example"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LogBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LogBoxEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(60))
        ))
    }

    private func makeEntry() -> LogBoxEntry {
        let settings = DeckSettings.load()
        let logbox = settings.logbox
        let snapshot = LogBoxSnapshotStore.load()
        let now = Date()
        let chip = FetchChip.text(
            source: .logbox,
            status: FetchStatusStore.load(.logbox),
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )
        let account = settings.account(for: .logboxElastic)
        let uiURL = (account?.uiURL.isEmpty == false ? account?.uiURL : account?.baseURL) ?? ""

        return LogBoxEntry(
            date: now,
            available: snapshot != nil,
            stale: snapshot.map { now.timeIntervalSince($0.writtenAt) > 5 * 60 } ?? false,
            writtenAt: snapshot?.writtenAt,
            chip: chip,
            snapshot: snapshot,
            settings: logbox,
            uiURL: uiURL
        )
    }
}

// MARK: - Widget

struct LogBoxWidget: Widget {
    let kind = "LogBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogBoxProvider()) { entry in
            LogBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("LogBox")
        .description("Manifold errors and warnings, with a link into Kibana.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct LogBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LogBoxEntry

    var body: some View {
        Group {
            if entry.available, let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: smallView(snapshot)
                case .systemMedium: mediumView(snapshot)
                default: largeView(snapshot)
                }
            } else {
                unavailableView
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        // Small has no room for per-row targets; the whole face opens the
        // current environment's Discover view.
        .widgetURL(family == .systemSmall ? link(for: nil) : nil)
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LogBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No log data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Pick an Elastic account in Deck settings.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func smallView(_ snapshot: LogBoxSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            header(snapshot)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(compact(snapshot.errorSmall))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("errors")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(compact(snapshot.warnSmall)) warn")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if entry.settings.showTrend, !snapshot.trend.isEmpty {
                LogTrendBars(points: snapshot.trend, color: entry.settings.accentColor.color)
                    .frame(height: 20)
            }
            Spacer(minLength: 0)
            bottomLine(snapshot)
        }
    }

    private func mediumView(_ snapshot: LogBoxSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(snapshot)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compact(snapshot.errorSmall))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("ERRORS · \(snapshot.smallMinutes)m")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(compact(snapshot.warnSmall)) WARN")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if entry.settings.showTrend, !snapshot.trend.isEmpty {
                    LogTrendBars(points: snapshot.trend, color: entry.settings.accentColor.color)
                        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 42)
                }
            }
            Divider()
            rows(snapshot, limit: 2)
            Spacer(minLength: 0)
        }
    }

    private func largeView(_ snapshot: LogBoxSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(snapshot)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compact(snapshot.errorSmall))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("ERRORS · \(snapshot.smallMinutes)m")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(compact(snapshot.errorLarge))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("LAST \(snapshot.largeMinutes / 60)h")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                Spacer()
                Text("\(compact(snapshot.warnSmall)) WARN · \(compact(snapshot.warnLarge)) IN \(snapshot.largeMinutes / 60)h")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if entry.settings.showTrend, !snapshot.trend.isEmpty {
                LogTrendBars(points: snapshot.trend, color: entry.settings.accentColor.color)
                    .frame(height: 48)
            }
            Divider()
            rows(snapshot, limit: entry.settings.textMode == .fullLines ? 5 : 4)
            Spacer(minLength: 0)
            footer(snapshot)
        }
    }

    // MARK: Shared pieces

    private func header(_ snapshot: LogBoxSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("LOGBOX")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(entry.settings.environment.displayName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(entry.settings.accentColor.color.opacity(0.18), in: Capsule())
                .foregroundStyle(entry.settings.accentColor.color)
            if entry.settings.face == .singleService, !entry.settings.service.isEmpty {
                Text(entry.settings.service)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 2)
            if let chip = entry.chip {
                Text(chip)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if entry.stale, let writtenAt = entry.writtenAt {
                Text(timeString(writtenAt))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func rows(_ snapshot: LogBoxSnapshot, limit: Int) -> some View {
        switch entry.settings.textMode {
        case .fullLines:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(snapshot.recent.prefix(limit).enumerated()), id: \.offset) { _, line in
                    linked(line.service) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(line.service)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(line.message)
                                .font(.system(size: 10, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        case .latestMessage:
            messageRow(snapshot)
        case .templates:
            if entry.settings.face == .brokenNow || entry.settings.face == .mirrorDashboard {
                countRows(snapshot.templates.isEmpty ? snapshot.services : snapshot.templates, limit: limit)
            } else {
                countRows(snapshot.services, limit: limit)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ snapshot: LogBoxSnapshot) -> some View {
        if let line = snapshot.recent.first {
            linked(line.service) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line.service)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(line.message)
                        .font(.system(size: 10, design: .rounded))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        } else {
            countRows(snapshot.templates, limit: 1)
        }
    }

    private func countRows(_ rows: [LogBoxCount], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows.prefix(limit), id: \.name) { row in
                linked(row.name) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 10, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(compact(row.count))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(entry.settings.accentColor.color)
                    }
                }
            }
        }
    }

    private func bottomLine(_ snapshot: LogBoxSnapshot) -> some View {
        HStack(spacing: 4) {
            if let service = snapshot.services.first?.name {
                Text(service)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let template = snapshot.templates.first?.name {
                Text(template)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let at = snapshot.lastErrorAt {
                Text(timeString(at))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func footer(_ snapshot: LogBoxSnapshot) -> some View {
        HStack(spacing: 4) {
            if let at = snapshot.lastErrorAt {
                Text("LAST \(timeString(at))")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            if let note = snapshot.note {
                Text("· \(note)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Links and formatting

    private func link(for service: String?) -> URL? {
        var query = "log.level:(error OR critical)"
        if let service, !service.isEmpty {
            let clean = service.replacingOccurrences(of: "\"", with: "")
            query += " AND service.name:\(clean)"
        }
        return InfraLinks.kibanaDiscover(
            uiURL: entry.uiURL,
            index: entry.settings.environment.index,
            query: query,
            fromMinutes: entry.settings.largeWindowMinutes
        )
    }

    /// A row is a link only when there is a real Kibana URL; otherwise it is
    /// plain text that does not pretend to be clickable.
    @ViewBuilder
    private func linked<Content: View>(
        _ service: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        if let url = link(for: service) ?? link(for: nil) {
            Link(destination: url, label: content)
        } else {
            content()
        }
    }

    /// `Link` requires a destination; when there is no Kibana URL the row
    /// should not look clickable at all, so `linked` renders plain content.
    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Trend

/// Bars rather than a Swift Charts `Chart`: a Chart in a widget face silently
/// drops the widget from the gallery (CLAUDE.md).
struct LogTrendBars: View {
    let points: [LogBoxPoint]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxCount = max(points.map(\.count).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(points.indices, id: \.self) { index in
                    let point = points[index]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(point.count == 0 ? 0.16 : 0.72))
                        .frame(
                            height: max(
                                1,
                                geo.size.height * CGFloat(point.count) / CGFloat(maxCount)
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
