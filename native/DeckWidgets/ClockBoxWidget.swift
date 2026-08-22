import WidgetKit
import SwiftUI

// MARK: - Timeline entry
//
// ClockBox is the only Deck widget on neither data path: no agent snapshot, no
// syscall sampler, no network. Everything it shows is derived from `Date` and
// `TimeZone` at the entry's own timestamp, so the provider can compute every
// future entry up front.

struct ClockBoxEntry: TimelineEntry {
    let date: Date
    let rows: [ClockRow]
    let settings: ClockBoxSettings
}

// MARK: - Provider

struct ClockBoxProvider: TimelineProvider {
    /// One hour of entries. WidgetKit renders each at its own date, so the
    /// faces stay minute-accurate without a reload in between.
    private static let entryCount = 60

    func placeholder(in context: Context) -> ClockBoxEntry {
        makeEntry(at: .now, settings: ClockBoxSettings())
    }

    func getSnapshot(in context: Context, completion: @escaping (ClockBoxEntry) -> Void) {
        completion(makeEntry(at: .now, settings: DeckSettings.load().clockbox))
    }

    /// Entries land on **minute boundaries**, not `now + 60`.
    ///
    /// A `.after(now + 60)` policy is not phase-aligned: regenerate at :17 past
    /// and every face shows the previous minute for another 43 seconds. For a
    /// clock that is not a rough edge, it is the entire product. Pre-computing
    /// a boundary-aligned run also sidesteps the ~60s floor WidgetKit puts on
    /// timeline *regeneration* (CLAUDE.md) — the floor applies to reloads, not
    /// to how many entries one timeline may carry.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockBoxEntry>) -> Void) {
        let settings = DeckSettings.load().clockbox
        let now = Date()

        var entries = [makeEntry(at: now, settings: settings)]
        if let firstBoundary = Self.nextMinuteBoundary(after: now) {
            for step in 0..<Self.entryCount {
                let date = firstBoundary.addingTimeInterval(TimeInterval(step * 60))
                entries.append(makeEntry(at: date, settings: settings))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func nextMinuteBoundary(after date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.nextDate(
            after: date,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        )
    }

    private func makeEntry(at date: Date, settings: ClockBoxSettings) -> ClockBoxEntry {
        ClockBoxEntry(
            date: date,
            rows: ClockBoxCore.rows(ids: settings.cityIDs, relativeTo: .current, at: date),
            settings: settings
        )
    }
}

// MARK: - Widget

struct ClockBoxWidget: Widget {
    let kind = "ClockBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClockBoxProvider()) { entry in
            ClockBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ClockBox")
        .description("World clocks for up to six cities.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct ClockBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClockBoxEntry

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                emptyView
            } else {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    columns(limit: ClockBoxCore.mediumCapacity, timeSize: 20, spacing: 10)
                default:
                    largeView
                }
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    /// Never a blank widget: an unselected ClockBox says so and points at the
    /// only place that can fix it.
    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLOCKBOX")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text("No cities selected")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Pick cities in Deck settings")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Small shows the main clock — the one chosen in settings, or the first
    /// non-local city when left on auto.
    private var smallView: some View {
        let id = ClockBoxCore.mainCityID(
            ids: entry.settings.cityIDs,
            preferred: entry.settings.mainCityID
        )
        let row = entry.rows.first { $0.id == id } ?? entry.rows[0]
        return VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(row.time)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.settings.timeColor.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if entry.settings.showRelativeDay {
                Text(row.day.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if entry.settings.showOffset {
                Text(row.offset)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// One row of columns, capped at the face's capacity.
    private func columns(limit: Int, timeSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(entry.rows.prefix(limit)), id: \.id) { row in
                column(row, timeSize: timeSize)
            }
        }
    }

    /// Large fits six as two rows of three — six across would squeeze each
    /// column past legibility at this width.
    private var largeView: some View {
        let shown = Array(entry.rows.prefix(ClockBoxCore.largeCapacity))
        let top = Array(shown.prefix(3))
        let bottom = Array(shown.dropFirst(3))
        return VStack(alignment: .leading, spacing: 10) {
            Text("WORLD CLOCKS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            row(of: top, timeSize: 24, spacing: 12)
            if !bottom.isEmpty {
                Divider()
                row(of: bottom, timeSize: 24, spacing: 12)
            }
            Spacer(minLength: 0)
        }
    }

    private func row(of rows: [ClockRow], timeSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(rows, id: \.id) { row in
                column(row, timeSize: timeSize)
            }
            // Keeps a short final row left-aligned under the one above it
            // instead of spreading three columns across the full width.
            if rows.count < 3 {
                ForEach(0..<(3 - rows.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func column(_ row: ClockRow, timeSize: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(row.time)
                .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.settings.timeColor.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(row.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if entry.settings.showRelativeDay {
                Text(row.day.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if entry.settings.showOffset {
                Text(row.offset)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
