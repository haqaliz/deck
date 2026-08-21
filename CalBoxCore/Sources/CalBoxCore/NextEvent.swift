import Foundation

// MARK: - The headline pick

public enum NextEvent {
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
    public static func select(events: [CalEvent], now: Date) -> CalEvent? {
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
