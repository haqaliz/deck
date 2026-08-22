import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct CalBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    /// One line explaining the last read attempt, or nil when all is well.
    let chip: String?
    let split: AgendaSplit
    let settings: CalBoxSettings
}

// MARK: - Provider
//
// Events arrive via the agent-pumped snapshot: reading EventKit is TCC-gated
// and the widget sandbox can neither hold the grant nor show a prompt.
//
// One entry per reload is enough: the 60s policy re-runs the provider, which
// re-splits the stored snapshot against the current time, so the lists stay
// correct — and keep rolling over at midnight — even with the agent dead.

struct CalBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalBoxEntry {
        let now = Date()
        let events = [
            CalEvent(id: "1", title: "Design review", start: now.addingTimeInterval(2520), end: now.addingTimeInterval(4320), isAllDay: false, calendarTitle: "Work", calendarID: "a", color: RGBA(red: 0.35, green: 0.55, blue: 0.95)),
            CalEvent(id: "2", title: "1:1 with Sam", start: now.addingTimeInterval(9000), end: now.addingTimeInterval(10800), isAllDay: false, calendarTitle: "Work", calendarID: "a", color: RGBA(red: 0.35, green: 0.55, blue: 0.95)),
            CalEvent(id: "3", title: "Dentist", start: now.addingTimeInterval(19800), end: now.addingTimeInterval(23400), isAllDay: false, calendarTitle: "Home", calendarID: "b", color: RGBA(red: 0.95, green: 0.45, blue: 0.35)),
        ]
        return makeEntry(from: CalBoxSnapshot(writtenAt: now, events: events), settings: CalBoxSettings(), chip: nil, now: now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalBoxEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalBoxEntry>) -> Void) {
        let now = Date()
        let snapshot = CalBoxSnapshotStore.load()
        let settings = DeckSettings.load().calbox
        let chip = FetchChip.text(
            source: .calbox,
            status: FetchStatusStore.load(.calbox),
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )

        guard let snapshot else {
            completion(Timeline(entries: [unavailableEntry(settings: settings, chip: chip, now: now)],
                                policy: .after(now.addingTimeInterval(60))))
            return
        }

        // One entry, like every other Deck widget. An earlier version emitted
        // an entry at every event boundary so a live countdown could roll over
        // at the exact second; that archived 24 full views into a 1.4 MB
        // timeline — 24x TaskBox's — which WidgetKit accepted and then drew as
        // an empty widget. The countdown is gone and the lists only need to be
        // right to the minute, which the 60s reload already gives.
        completion(Timeline(
            entries: [makeEntry(from: snapshot, settings: settings, chip: chip, now: now)],
            policy: .after(now.addingTimeInterval(60))
        ))
    }

    private func currentEntry() -> CalBoxEntry {
        let now = Date()
        let settings = DeckSettings.load().calbox
        let chip = FetchChip.text(
            source: .calbox,
            status: FetchStatusStore.load(.calbox),
            dataWrittenAt: CalBoxSnapshotStore.load()?.writtenAt,
            now: now
        )
        guard let snapshot = CalBoxSnapshotStore.load() else {
            return unavailableEntry(settings: settings, chip: chip, now: now)
        }
        return makeEntry(from: snapshot, settings: settings, chip: chip, now: now)
    }

    private func unavailableEntry(settings: CalBoxSettings, chip: String?, now: Date) -> CalBoxEntry {
        CalBoxEntry(
            date: now,
            available: false,
            stale: false,
            writtenAt: nil,
            chip: chip,
            split: AgendaSplit(allDay: [], today: [], tomorrow: []),
            settings: settings
        )
    }

    private func makeEntry(from snapshot: CalBoxSnapshot, settings: CalBoxSettings, chip: String?, now: Date) -> CalBoxEntry {
        CalBoxEntry(
            date: now,
            available: true,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            writtenAt: snapshot.writtenAt,
            chip: chip,
            split: Agenda.split(events: snapshot.events, now: now, calendar: .current),
            settings: settings
        )
    }
}

// MARK: - Widget

struct CalBoxWidget: Widget {
    let kind = "CalBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalBoxProvider()) { entry in
            CalBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("CalBox")
        .description("Today's and tomorrow's events from your calendars.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct CalBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalBoxEntry

    /// Rows on the large face before it starts saying "+N more".
    private static let largeTodayCap = 8

    var body: some View {
        Group {
            if entry.available {
                switch family {
                case .systemSmall: smallView
                case .systemMedium: mediumView
                default: largeView
                }
            } else {
                unavailableView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    // MARK: Faces
    //
    // Two labelled sections and nothing else. An earlier face led with a live
    // countdown to the next event under an unlabelled block; the block read as
    // belonging to nothing, and the countdown restated what the row beneath it
    // already said ("20:00  Dinner time").

    private var smallView: some View {
        sections(todayLimit: 3, tomorrowLimit: 2)
    }

    private var mediumView: some View {
        sections(todayLimit: 5, tomorrowLimit: 4)
    }

    private var largeView: some View {
        sections(todayLimit: CalBoxSettings.maxCount, tomorrowLimit: CalBoxSettings.maxCount)
    }

    /// Both sections, each capped by the user's setting and by what the face
    /// can physically hold — past that the rows are clipped by the frame
    /// rather than by the setting.
    private func sections(todayLimit: Int, tomorrowLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let chip = entry.chip {
                Text(chip)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if entry.settings.showToday {
                section(
                    title: "TODAY",
                    events: entry.split.today,
                    allDay: entry.settings.showAllDay ? entry.split.allDay : [],
                    limit: min(entry.settings.todayCount, todayLimit),
                    emptyText: "Nothing left today"
                )
            }
            if entry.settings.showTomorrow {
                if entry.settings.showToday { Divider() }
                section(
                    title: "TOMORROW",
                    events: entry.split.tomorrow,
                    allDay: [],
                    limit: min(entry.settings.tomorrowCount, tomorrowLimit),
                    emptyText: "Nothing scheduled"
                )
            }
            Spacer(minLength: 0)
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No calendar data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Open Deck settings to pick your calendars.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Pieces

    /// One titled section: all-day rows first (they have no time to sort by),
    /// then timed rows, then an overflow count.
    @ViewBuilder
    private func section(
        title: String,
        events: [CalEvent],
        allDay: [CalEvent],
        limit: Int,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            if allDay.isEmpty && events.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            ForEach(allDay.prefix(limit), id: \.id) { event in
                row(event, time: "all-day")
            }
            // All-day rows spend the section's budget before timed ones do.
            let remaining = max(0, limit - min(allDay.count, limit))
            ForEach(events.prefix(remaining), id: \.id) { event in
                row(event, time: Self.timeString(event.start))
            }
            let hidden = (allDay.count + events.count) - (min(allDay.count, limit) + min(events.count, remaining))
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ event: CalEvent, time: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor(for: event))
                .frame(width: 7, height: 7)
            Text(time)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(event.title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private func dotColor(for event: CalEvent) -> Color {
        entry.settings.useCalendarColors ? event.color.color : entry.settings.accentColor.color
    }

    private static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

