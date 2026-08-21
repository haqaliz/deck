import Foundation

// MARK: - CalBox models
//
// Deliberately EventKit-free: every decision CalBox makes (which event is next,
// what the countdown says, how the agenda splits) operates on these plain
// values, so it is testable without a calendar store. The EKEvent -> CalEvent
// mapping is the only untested seam and lives in HostCalendarLoader.

public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct CalEvent: Codable, Equatable, Sendable {
    /// Unique per *occurrence* — see `EventNormalisation.occurrenceID`.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarTitle: String
    public var calendarID: String
    public var color: RGBA

    public init(
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
