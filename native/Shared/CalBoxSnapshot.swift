import AppKit
import EventKit
import Foundation

// MARK: - CalBox snapshot
//
// Reading the calendar is TCC-gated and reaches another app's data, so it is
// the sandbox-blocked, agent-pumped path: DeckAgent reads EventKit every 60s
// and writes this snapshot into the widget container; the CalBox widget only
// ever renders the snapshot and never touches EventKit itself.


// MARK: - CalBox models
//
// Deliberately EventKit-free: every decision CalBox makes (which event is next,
// what the countdown says, how the agenda splits) operates on these plain
// values, so it is testable without a calendar store. The EKEvent -> CalEvent
// mapping is the only untested seam and lives in HostCalendarLoader.

struct CalEvent: Codable, Equatable, Sendable {
    /// Unique per *occurrence* — see `EventNormalisation.occurrenceID`.
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
    var calendarID: String
    var color: RGBA

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarTitle: String,
        calendarID: String,
        color: RGBA
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.calendarID = calendarID
        self.color = color
    }
}


// MARK: - Turning raw calendar rows into renderable ones

enum EventNormalisation {
    /// An id unique per *occurrence*.
    ///
    /// EventKit expands a recurrence rule into one event per occurrence, but
    /// every occurrence carries the same `eventIdentifier` — a probe of the
    /// live store found 17 events in 48h sharing only 10 identifiers. Feeding
    /// that to a SwiftUI `ForEach` means duplicate keys and dropped rows, so
    /// the start time is part of the identity.
    static func occurrenceID(eventIdentifier: String, start: Date) -> String {
        "\(eventIdentifier)@\(start.timeIntervalSince1970)"
    }

    /// Collapses events identical in title, start, end and source calendar,
    /// keeping the first and preserving order.
    ///
    /// Not hypothetical: `Aliz workout time` is genuinely present twice at
    /// 08:00 in one Google calendar on this machine. Two events alike in all
    /// four fields are indistinguishable on the face, so showing both is just
    /// a duplicated row. Identical titles in *different* calendars are kept —
    /// the same meeting on a work and a personal calendar is worth seeing once
    /// per calendar dot.
    static func dedupe(_ events: [CalEvent]) -> [CalEvent] {
        var seen = Set<String>()
        var result: [CalEvent] = []
        for event in events {
            let key = "\(event.title)|\(event.start.timeIntervalSince1970)|\(event.end.timeIntervalSince1970)|\(event.calendarID)"
            if seen.insert(key).inserted {
                result.append(event)
            }
        }
        return result
    }
}


// MARK: - The headline pick

enum NextEvent {
    /// The event the countdown counts down to, or nil when there is nothing
    /// left.
    ///
    /// Rules, in order:
    /// 1. All-day events are excluded outright — an all-day "Holidays in Iran"
    ///    must never be the thing counting down.
    /// 2. The smallest `end > now` wins, so an event already in progress beats
    ///    one that has not started: it is the thing you are supposed to be
    ///    doing right now.
    /// 3. Ties break by earlier start, then by title, then by id — without a
    ///    total order the face flickers between two events on consecutive ticks.
    static func select(events: [CalEvent], now: Date) -> CalEvent? {
        events
            .filter { !$0.isAllDay && $0.end > now }
            .min { a, b in
                if a.end != b.end { return a.end < b.end }
                if a.start != b.start { return a.start < b.start }
                if a.title != b.title { return a.title < b.title }
                return a.id < b.id
            }
    }
}


// MARK: - Countdown wording

enum Countdown {
    /// The non-relative wording beneath the event title: `in 2h 05m`,
    /// `in 42m`, `now`, or `12m in` once it has started.
    ///
    /// Minute granularity throughout — second-precision on a desktop widget
    /// buys nothing and invites re-render churn. Anything within a minute
    /// either side reads as `now`, which is what a person would say.
    static func text(start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)

        if abs(delta) < 60 { return "now" }

        if delta < 0 {
            let minutes = Int(-delta) / 60
            return "\(minutes)m in"
        }

        let totalMinutes = Int(delta) / 60
        if totalMinutes <= 60 { return "in \(totalMinutes)m" }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "in %dh %02dm", hours, minutes)
    }
}


// MARK: - Splitting the horizon into what the faces show

struct AgendaSplit: Equatable {
    var allDay: [CalEvent]
    var today: [CalEvent]
    var tomorrow: [CalEvent]

    init(allDay: [CalEvent], today: [CalEvent], tomorrow: [CalEvent]) {
        self.allDay = allDay
        self.today = today
        self.tomorrow = tomorrow
    }
}

enum Agenda {
    /// Partitions the snapshot into the three groups the faces render.
    ///
    /// Finished events are dropped; an event in progress stays in `today` and
    /// the face marks it. Day membership is decided by an event's **start**, so
    /// an overnight deploy window that begins tonight belongs to today — that
    /// is the day you need to see it on, not tomorrow.
    static func split(events: [CalEvent], now: Date, calendar: Calendar) -> AgendaSplit {
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
            let startOfDayAfter = calendar.date(byAdding: .day, value: 2, to: startOfToday)
        else {
            return AgendaSplit(allDay: [], today: [], tomorrow: [])
        }

        let live = events.filter { $0.end > now }.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title < rhs.title
        }

        return AgendaSplit(
            allDay: live.filter { $0.isAllDay && $0.start < startOfTomorrow },
            today: live.filter { !$0.isAllDay && $0.start < startOfTomorrow },
            tomorrow: live.filter { !$0.isAllDay && $0.start >= startOfTomorrow && $0.start < startOfDayAfter }
        )
    }
}


// MARK: - When the widget must re-render

enum TimelineBoundaries {
    /// A stated cap rather than "whatever WidgetKit allows".
    static let maxEntries = 24

    /// The instants at which the face genuinely changes: now, every event
    /// start and end still ahead, and the next midnight.
    ///
    /// This is what keeps the countdown honest when the agent is not running.
    /// A single entry plus a 60s reload policy would leave "next event"
    /// pointing at something that already ended; emitting an entry at each
    /// boundary rolls it over at the right second regardless. Midnight is
    /// included because the today/tomorrow split on the large face would
    /// otherwise stay wrong until the next event starts — hours, on a quiet
    /// night.
    static func entries(events: [CalEvent], now: Date, calendar: Calendar) -> [Date] {
        var candidates: Set<Date> = [now]

        let startOfToday = calendar.startOfDay(for: now)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) {
            candidates.insert(midnight)
        }

        for event in events {
            if event.start > now { candidates.insert(event.start) }
            if event.end > now { candidates.insert(event.end) }
        }

        return Array(candidates.sorted().prefix(maxEntries))
    }
}


// MARK: - Snapshot + store

struct CalBoxSnapshot: Codable, Equatable {
    var writtenAt: Date
    /// Normalised, chronological, day-aligned horizon (see `HostCalendarLoader`).
    var events: [CalEvent]
}

// Access state is deliberately not a field here: `FetchStatus` already records
// it, and two sources of truth for "can we read the calendar" is how they drift
// apart — a snapshot written before a revocation would keep claiming access.

enum CalBoxSnapshotStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("calbox.json")
    }

    static func load() -> CalBoxSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CalBoxSnapshot.self, from: data)
    }

    static func save(_ snapshot: CalBoxSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = AtomicFile.write(data, to: fileURL)
    }
}

// MARK: - EventKit read (host/agent only — unsandboxed)
//
// The widget extension never calls into here: it has no calendar entitlement
// and no way to show a TCC prompt. DeckAgent carries the usage-description key
// in a __TEXT,__info_plist section (project.yml) because a `type: tool` target
// has no bundle to put it in.

/// One row of the settings-window calendar picker.
struct CalendarChoice: Equatable, Identifiable {
    var id: String
    var title: String
    var sourceTitle: String
    var allowsContentModifications: Bool
    var color: RGBA
}

enum HostCalendarLoader {
    enum CalendarError: Error {
        /// No calendars ticked — nothing to read, and not a failure.
        case notConfigured
        /// macOS refused: never granted, revoked, or restricted by policy.
        case accessDenied
        case readFailed(String)
    }

    /// How far ahead the snapshot reaches, in whole days from the start of
    /// today. Day-aligned on purpose: a sliding "now + 48h" window would let a
    /// far-future event drift in and out on every tick and churn the file.
    static let horizonDays = 3
    /// Bounds the snapshot regardless of how busy the calendar is.
    static let maxEvents = 60

    /// Requests access once, so callers can prompt before reading.
    @discardableResult
    static func requestAccess(store: EKEventStore = EKEventStore()) async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Every event calendar, for the settings picker. Empty when access is not
    /// granted.
    static func calendars(store: EKEventStore = EKEventStore()) -> [CalendarChoice] {
        store.calendars(for: .event).map { calendar in
            CalendarChoice(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: calendar.source?.title ?? "Other",
                allowsContentModifications: calendar.allowsContentModifications,
                color: rgba(from: calendar.cgColor)
            )
        }
    }

    /// Reads the selected calendars over the horizon and returns a normalised
    /// snapshot.
    static func fetch(
        calendarIDs: [String],
        now: Date = Date(),
        calendar: Calendar = .current,
        store: EKEventStore = EKEventStore()
    ) async throws -> CalBoxSnapshot {
        guard !calendarIDs.isEmpty else { throw CalendarError.notConfigured }

        guard await requestAccess(store: store) else { throw CalendarError.accessDenied }

        let selected = store.calendars(for: .event)
            .filter { calendarIDs.contains($0.calendarIdentifier) }
        // Ticked calendars that no longer exist (account removed) are not an
        // error — but an empty `calendars:` predicate means "all calendars",
        // which would silently show everything, so guard it explicitly.
        guard !selected.isEmpty else { throw CalendarError.notConfigured }

        let startOfToday = calendar.startOfDay(for: now)
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: startOfToday) else {
            throw CalendarError.readFailed("Could not compute the horizon")
        }

        let predicate = store.predicateForEvents(withStart: now, end: horizonEnd, calendars: selected)
        let raw = store.events(matching: predicate)

        let mapped: [CalEvent] = raw.compactMap { event -> CalEvent? in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            // A meeting you said no to must never be the thing counting down.
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined {
                return nil
            }
            let identifier = event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)/\(start.timeIntervalSince1970)"
            return CalEvent(
                id: EventNormalisation.occurrenceID(eventIdentifier: identifier, start: start),
                title: event.title ?? "(No title)",
                start: start,
                end: end,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                calendarID: event.calendar.calendarIdentifier,
                color: rgba(from: event.calendar.cgColor)
            )
        }

        let normalised = EventNormalisation
            .dedupe(mapped)
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title < rhs.title
            }
            .prefix(maxEvents)

        return CalBoxSnapshot(writtenAt: Date(), events: Array(normalised))
    }

    private static func rgba(from cgColor: CGColor?) -> RGBA {
        guard let cgColor, let ns = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return RGBA(red: 0.35, green: 0.55, blue: 0.95)
        }
        return RGBA(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent),
            alpha: Double(ns.alphaComponent)
        )
    }
}
