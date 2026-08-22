import XCTest

// Ported from the CalBoxCore scratch package. Everything here is the pure
// logic behind the CalBox face: which event the countdown counts down to, how
// the agenda splits, which calendars start ticked, and when the widget's
// timeline must re-render.

// A fixed reference point so nothing here depends on the wall clock.
// 2026-08-22 09:00:00 UTC, exercised in UTC to keep day boundaries explicit.
private let utc = TimeZone(identifier: "UTC")!
private var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = utc
    return c
}()

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private let now = at(2026, 8, 22, 9)

private func event(
    _ title: String,
    _ start: Date,
    _ end: Date,
    allDay: Bool = false,
    calendarTitle: String = "Work",
    calendarID: String = "cal-work",
    id: String? = nil
) -> CalEvent {
    CalEvent(
        id: id ?? EventNormalisation.occurrenceID(eventIdentifier: title, start: start),
        title: title,
        start: start,
        end: end,
        isAllDay: allDay,
        calendarTitle: calendarTitle,
        calendarID: calendarID,
        color: RGBA(red: 0, green: 0, blue: 1)
    )
}

// MARK: - Calendar defaults

final class CalendarDefaultsTests: XCTestCase {
    // The first draft defaulted on a "Holidays…" title prefix, which breaks in
    // any non-English locale. Writability is the locale-independent signal.
    func testWritableCalendarIsOnByDefault() {
        XCTAssertTrue(CalendarDefaults.shouldEnableByDefault(allowsContentModifications: true))
    }

    func testReadOnlyCalendarIsOffByDefault() {
        XCTAssertFalse(CalendarDefaults.shouldEnableByDefault(allowsContentModifications: false))
    }

    private let available = [
        (id: "work", allowsContentModifications: true),
        (id: "google", allowsContentModifications: true),
        (id: "holidays", allowsContentModifications: false),
        (id: "birthdays", allowsContentModifications: false),
    ]

    // A freshly added widget must show something without a trip to settings.
    func testDefaultsApplyBeforeTheUserHasChosen() {
        XCTAssertEqual(
            CalendarDefaults.resolve(selected: [], hasChosen: false, available: available),
            ["work", "google"]
        )
    }

    // Once chosen, the stored list is authoritative -- including an empty one.
    func testEmptySelectionIsRespectedAfterChoosing() {
        XCTAssertEqual(
            CalendarDefaults.resolve(selected: [], hasChosen: true, available: available),
            []
        )
    }

    func testChosenSelectionWins() {
        XCTAssertEqual(
            CalendarDefaults.resolve(selected: ["holidays"], hasChosen: true, available: available),
            ["holidays"]
        )
    }
}

// MARK: - Occurrence identity

final class OccurrenceIDTests: XCTestCase {
    // The probe found 17 events in 48h sharing only 10 eventIdentifiers:
    // recurring occurrences reuse the identifier. Using it as a SwiftUI id
    // means duplicate keys and dropped rows.
    func testRecurringOccurrencesGetDistinctIDs() {
        let shared = "ABC:123"
        let first = EventNormalisation.occurrenceID(eventIdentifier: shared, start: at(2026, 8, 22, 8))
        let second = EventNormalisation.occurrenceID(eventIdentifier: shared, start: at(2026, 8, 23, 8))
        XCTAssertNotEqual(first, second)
    }

    func testSameOccurrenceIsStableAcrossCalls() {
        let a = EventNormalisation.occurrenceID(eventIdentifier: "ABC:123", start: at(2026, 8, 22, 8))
        let b = EventNormalisation.occurrenceID(eventIdentifier: "ABC:123", start: at(2026, 8, 22, 8))
        XCTAssertEqual(a, b)
    }
}

// MARK: - Normalisation

final class NormalisationTests: XCTestCase {
    // Observed in live data: "Aliz workout time" exists twice at 08:00 in one
    // Google calendar.
    func testExactDuplicateInSameCalendarCollapses() {
        let a = event("Aliz workout time", at(2026, 8, 22, 8), at(2026, 8, 22, 9), id: "x")
        let b = event("Aliz workout time", at(2026, 8, 22, 8), at(2026, 8, 22, 9), id: "y")
        XCTAssertEqual(EventNormalisation.dedupe([a, b]).count, 1)
    }

    func testSameTitleAndTimeInDifferentCalendarsIsKept() {
        let a = event("Standup", at(2026, 8, 22, 10), at(2026, 8, 22, 11), calendarID: "cal-a", id: "x")
        let b = event("Standup", at(2026, 8, 22, 10), at(2026, 8, 22, 11), calendarID: "cal-b", id: "y")
        XCTAssertEqual(EventNormalisation.dedupe([a, b]).count, 2)
    }

    func testDedupeKeepsFirstAndPreservesOrder() {
        let first = event("A", at(2026, 8, 22, 10), at(2026, 8, 22, 11), id: "first")
        let dupe = event("A", at(2026, 8, 22, 10), at(2026, 8, 22, 11), id: "second")
        let other = event("B", at(2026, 8, 22, 12), at(2026, 8, 22, 13), id: "third")
        let result = EventNormalisation.dedupe([first, dupe, other])
        XCTAssertEqual(result.map(\.id), ["first", "third"])
    }
}

// MARK: - Agenda split

final class AgendaTests: XCTestCase {
    func testPartitionsAllDayTodayAndTomorrow() {
        let allDay = event("Vitamin D", at(2026, 8, 22, 0), at(2026, 8, 23, 0), allDay: true)
        let today = event("Review", at(2026, 8, 22, 14), at(2026, 8, 22, 15))
        let tomorrow = event("Workout", at(2026, 8, 23, 8), at(2026, 8, 23, 9))
        let past = event("Breakfast", at(2026, 8, 22, 7), at(2026, 8, 22, 8))

        let split = Agenda.split(events: [past, allDay, tomorrow, today], now: now, calendar: cal)
        XCTAssertEqual(split.allDay.map(\.title), ["Vitamin D"])
        XCTAssertEqual(split.today.map(\.title), ["Review"])
        XCTAssertEqual(split.tomorrow.map(\.title), ["Workout"])
    }

    func testFinishedEventsDropped() {
        let past = event("Breakfast", at(2026, 8, 22, 7), at(2026, 8, 22, 8))
        let split = Agenda.split(events: [past], now: now, calendar: cal)
        XCTAssertTrue(split.today.isEmpty)
    }

    func testInProgressEventStaysInToday() {
        let running = event("Standup", at(2026, 8, 22, 8, 30), at(2026, 8, 22, 9, 30))
        let split = Agenda.split(events: [running], now: now, calendar: cal)
        XCTAssertEqual(split.today.map(\.title), ["Standup"])
    }

    // An event that starts today and ends tomorrow belongs to today: that is
    // the day you need to see it on.
    func testEventSpanningMidnightCountsAsToday() {
        let overnight = event("Deploy window", at(2026, 8, 22, 23), at(2026, 8, 23, 2))
        let split = Agenda.split(events: [overnight], now: now, calendar: cal)
        XCTAssertEqual(split.today.map(\.title), ["Deploy window"])
        XCTAssertTrue(split.tomorrow.isEmpty)
    }

    func testDayAfterTomorrowIsExcluded() {
        let far = event("Later", at(2026, 8, 24, 10), at(2026, 8, 24, 11))
        let split = Agenda.split(events: [far], now: now, calendar: cal)
        XCTAssertTrue(split.today.isEmpty)
        XCTAssertTrue(split.tomorrow.isEmpty)
    }

    func testTodayIsChronological() {
        let late = event("Late", at(2026, 8, 22, 16), at(2026, 8, 22, 17))
        let early = event("Early", at(2026, 8, 22, 10), at(2026, 8, 22, 11))
        let split = Agenda.split(events: [late, early], now: now, calendar: cal)
        XCTAssertEqual(split.today.map(\.title), ["Early", "Late"])
    }
}

// MARK: - Settings migration
//
// CalBox first shipped with a single agenda list (`showAgenda` + `eventCount`)
// before the face split into TODAY and TOMORROW. An existing settings.json
// must carry over rather than silently resetting someone's choice.

final class CalBoxSettingsDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> CalBoxSettings {
        try JSONDecoder().decode(CalBoxSettings.self, from: Data(json.utf8))
    }

    func testDefaults() throws {
        let s = try decode("{}")
        XCTAssertTrue(s.showToday)
        XCTAssertTrue(s.showTomorrow)
        XCTAssertEqual(s.todayCount, 6)
        XCTAssertEqual(s.tomorrowCount, 4)
        XCTAssertFalse(s.hasChosenCalendars)
    }

    func testLegacyEventCountBecomesTodayCount() throws {
        let s = try decode(#"{"eventCount": 8}"#)
        XCTAssertEqual(s.todayCount, 8)
    }

    func testLegacyShowAgendaBecomesShowToday() throws {
        let s = try decode(#"{"showAgenda": false}"#)
        XCTAssertFalse(s.showToday)
    }

    func testCurrentKeysWinOverLegacyOnes() throws {
        let s = try decode(#"{"eventCount": 8, "todayCount": 3, "showAgenda": false, "showToday": true}"#)
        XCTAssertEqual(s.todayCount, 3)
        XCTAssertTrue(s.showToday)
    }

    // A hand-edited file must not produce a face that clips.
    func testCountsAreClampedToTheAllowedRange() throws {
        XCTAssertEqual(try decode(#"{"todayCount": 99}"#).todayCount, CalBoxSettings.maxCount)
        XCTAssertEqual(try decode(#"{"tomorrowCount": 0}"#).tomorrowCount, 1)
        XCTAssertEqual(try decode(#"{"todayCount": -5}"#).todayCount, 1)
    }

    // Legacy keys are read once and then dropped, so a file migrates and stays
    // clean rather than carrying both shapes forever.
    func testLegacyKeysAreNotWrittenBack() throws {
        let s = try decode(#"{"eventCount": 8, "showAgenda": false}"#)
        let data = try JSONEncoder().encode(s)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("eventCount"))
        XCTAssertFalse(json.contains("showAgenda"))
        XCTAssertTrue(json.contains("todayCount"))
    }

    func testRoundTripPreservesChoices() throws {
        var s = CalBoxSettings()
        s.calendarIDs = ["a", "b"]
        s.hasChosenCalendars = true
        s.todayCount = 10
        s.tomorrowCount = 1
        s.showTomorrow = false
        let decoded = try JSONDecoder().decode(CalBoxSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}
