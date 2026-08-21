import Foundation

// MARK: - The headline pick

public enum NextEvent {
    /// How soon an in-progress event must end to outrank what is coming up.
    ///
    /// A meeting you are sitting in is the thing you are supposed to be doing,
    /// so it should own the countdown. An eight-hour overnight block is not —
    /// observed on real data, a 22:30–06:30 "sleep time" event held the
    /// countdown all night and hid the next actual commitment. Ninety minutes
    /// is a long meeting and a short night.
    public static let inProgressGrace: TimeInterval = 90 * 60

    /// The event the countdown counts down to, or nil when there is nothing
    /// left.
    ///
    /// All-day events are excluded outright — an all-day "Holidays in Iran"
    /// must never be the thing counting down. Beyond that, in priority order:
    ///
    /// 1. an in-progress event ending within `inProgressGrace`,
    /// 2. otherwise the soonest upcoming event,
    /// 3. otherwise a long in-progress block — better than claiming the day is
    ///    clear while you are demonstrably inside something.
    ///
    /// Every comparison falls through to a total order (end, start, title, id)
    /// so the pick cannot flicker between two equal events on consecutive ticks.
    public static func select(events: [CalEvent], now: Date) -> CalEvent? {
        let live = events.filter { !$0.isAllDay && $0.end > now }
        let inProgress = live.filter { $0.start <= now }
        let upcoming = live.filter { $0.start > now }

        let endingSoon = inProgress.filter { $0.end <= now.addingTimeInterval(inProgressGrace) }
        if let soonest = endingSoon.min(by: byEnd) { return soonest }

        if let next = upcoming.min(by: byStart) { return next }

        return inProgress.min(by: byEnd)
    }

    private static func byEnd(_ a: CalEvent, _ b: CalEvent) -> Bool {
        if a.end != b.end { return a.end < b.end }
        if a.start != b.start { return a.start < b.start }
        if a.title != b.title { return a.title < b.title }
        return a.id < b.id
    }

    private static func byStart(_ a: CalEvent, _ b: CalEvent) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.end != b.end { return a.end < b.end }
        if a.title != b.title { return a.title < b.title }
        return a.id < b.id
    }
}
