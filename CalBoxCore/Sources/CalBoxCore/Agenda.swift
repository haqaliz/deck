import Foundation

// MARK: - Splitting the horizon into what the faces show

public struct AgendaSplit: Equatable {
    public var allDay: [CalEvent]
    public var today: [CalEvent]
    public var tomorrow: [CalEvent]

    public init(allDay: [CalEvent], today: [CalEvent], tomorrow: [CalEvent]) {
        self.allDay = allDay
        self.today = today
        self.tomorrow = tomorrow
    }
}

public enum Agenda {
    /// Partitions the snapshot into the three groups the faces render.
    ///
    /// Finished events are dropped; an event in progress stays in `today` and
    /// the face marks it. Day membership is decided by an event's **start**, so
    /// an overnight deploy window that begins tonight belongs to today — that
    /// is the day you need to see it on, not tomorrow.
    public static func split(events: [CalEvent], now: Date, calendar: Calendar) -> AgendaSplit {
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
