import Foundation

// MARK: - When the widget must re-render

public enum TimelineBoundaries {
    /// A stated cap rather than "whatever WidgetKit allows".
    public static let maxEntries = 24

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
    public static func entries(events: [CalEvent], now: Date, calendar: Calendar) -> [Date] {
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
