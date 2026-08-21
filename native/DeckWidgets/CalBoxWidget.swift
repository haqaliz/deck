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
    let next: CalEvent?
    let split: AgendaSplit
    let settings: CalBoxSettings
}

// MARK: - Provider
//
// Events arrive via the agent-pumped snapshot: reading EventKit is TCC-gated
// and the widget sandbox can neither hold the grant nor show a prompt.
//
// Unlike the other pumped widgets, one entry per tick is not enough here. A
// countdown is only true at the instant it is rendered, so the timeline carries
// an entry at every event boundary and at midnight (TimelineBoundaries) — the
// face then rolls over at the right second even if the agent never runs again.

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

        let dates = TimelineBoundaries.entries(events: snapshot.events, now: now, calendar: .current)
        let entries = dates.map { makeEntry(from: snapshot, settings: settings, chip: chip, now: $0) }
        // The 60s floor still applies: it is what picks up a new snapshot.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
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
            next: nil,
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
            next: NextEvent.select(events: snapshot.events, now: now),
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
        .description("Your next event, with a live countdown and today's agenda.")
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

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            countdownBlock
            Spacer(minLength: 0)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            countdownBlock
            allDayRow
            if entry.settings.showAgenda {
                eventList(entry.agendaAfterNext, title: "NEXT UP", limit: entry.settings.eventCount)
            }
            Spacer(minLength: 0)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            countdownBlock
            allDayRow
            if entry.settings.showAgenda {
                eventList(entry.agendaAfterNext, title: "TODAY", limit: Self.largeTodayCap)
            }
            if entry.settings.showTomorrow && !entry.split.tomorrow.isEmpty {
                Divider()
                eventList(entry.split.tomorrow, title: "TOMORROW", limit: 3)
            }
            Spacer(minLength: 0)
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CalBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No calendar data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Open Deck settings to pick your calendars.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Pieces

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("CALBOX")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            Spacer(minLength: 4)
            if let chip = entry.chip {
                Text(chip)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if entry.stale, let writtenAt = entry.writtenAt {
                Text("· \(Self.timeString(writtenAt))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var countdownBlock: some View {
        if let next = entry.next {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor(for: next))
                        .frame(width: 7, height: 7)
                    Text(next.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Only Text(_:style:) ticks on its own. Rendering
                // Countdown.text here would freeze it between timeline
                // entries -- and entries land on event boundaries, so a
                // countdown could sit unchanged for an hour and be an hour
                // wrong. Liveness is the whole point of this widget, so the
                // visible text is a system timer; Countdown.text supplies the
                // accessibility label, where exact wording matters more than
                // the last few seconds of precision.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(next.start > entry.date ? next.start : next.end, style: .timer)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize()
                    Text(next.start > entry.date ? "TO GO" : "LEFT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(next.title), \(Countdown.text(start: next.start, now: entry.date))")

                Text("\(Self.timeString(next.start)) – \(Self.timeString(next.end))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            // A clear day is a success, not a failure: no chip, no apology.
            Text("Nothing left today")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var allDayRow: some View {
        if entry.settings.showAllDay && !entry.split.allDay.isEmpty && family != .systemSmall {
            HStack(spacing: 6) {
                ForEach(entry.split.allDay.prefix(2), id: \.id) { event in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(dotColor(for: event))
                            .frame(width: 6, height: 6)
                        Text(event.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if entry.split.allDay.count > 2 {
                    Text("+\(entry.split.allDay.count - 2)")
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func eventList(_ events: [CalEvent], title: String, limit: Int) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                ForEach(events.prefix(limit), id: \.id) { event in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dotColor(for: event))
                            .frame(width: 7, height: 7)
                        Text(Self.timeString(event.start))
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
                if events.count > limit {
                    Text("+\(events.count - limit) more")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
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

private extension CalBoxEntry {
    /// Today's remaining events minus the one already shown in the countdown
    /// block — repeating it as the first list row is pure noise.
    var agendaAfterNext: [CalEvent] {
        guard let next else { return split.today }
        return split.today.filter { $0.id != next.id }
    }
}
