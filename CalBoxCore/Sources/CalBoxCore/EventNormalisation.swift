import Foundation

// MARK: - Turning raw calendar rows into renderable ones

public enum EventNormalisation {
    /// An id unique per *occurrence*.
    ///
    /// EventKit expands a recurrence rule into one event per occurrence, but
    /// every occurrence carries the same `eventIdentifier` — a probe of the
    /// live store found 17 events in 48h sharing only 10 identifiers. Feeding
    /// that to a SwiftUI `ForEach` means duplicate keys and dropped rows, so
    /// the start time is part of the identity.
    public static func occurrenceID(eventIdentifier: String, start: Date) -> String {
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
    public static func dedupe(_ events: [CalEvent]) -> [CalEvent] {
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
