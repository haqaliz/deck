import XCTest
@testable import CalBoxCore

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

// MARK: - Next event

final class NextEventTests: XCTestCase {
    func testPicksSoonestUpcoming() {
        let later = event("Later", at(2026, 8, 22, 14), at(2026, 8, 22, 15))
        let sooner = event("Sooner", at(2026, 8, 22, 10), at(2026, 8, 22, 11))
        XCTAssertEqual(NextEvent.select(events: [later, sooner], now: now)?.title, "Sooner")
    }

    // A short event you are already inside is the thing you are supposed to
    // be doing, so it outranks one that hasn't started.
    func testShortInProgressBeatsUpcoming() {
        let inProgress = event("Standup", at(2026, 8, 22, 8, 30), at(2026, 8, 22, 9, 30))
        let upcoming = event("Review", at(2026, 8, 22, 10), at(2026, 8, 22, 11))
        XCTAssertEqual(NextEvent.select(events: [upcoming, inProgress], now: now)?.title, "Standup")
    }

    // "Holidays in Iran" must never be the thing counting down.
    // ...but a long block you happen to be inside should not hide what is
    // actually next. Observed on real data: a 22:30-06:30 "Aliz sleep time"
    // owned the countdown all night and hid breakfast.
    func testLongInProgressYieldsToUpcoming() {
        let overnight = event("Aliz sleep time", at(2026, 8, 21, 22, 30), at(2026, 8, 22, 18))
        let upcoming = event("Breakfast", at(2026, 8, 22, 10), at(2026, 8, 22, 11))
        XCTAssertEqual(NextEvent.select(events: [overnight, upcoming], now: now)?.title, "Breakfast")
    }

    // With nothing upcoming, the long block is still better than showing
    // "nothing left today" while you are demonstrably inside something.
    func testLongInProgressWinsWhenNothingIsUpcoming() {
        let overnight = event("Aliz sleep time", at(2026, 8, 21, 22, 30), at(2026, 8, 22, 18))
        XCTAssertEqual(NextEvent.select(events: [overnight], now: now)?.title, "Aliz sleep time")
    }

    func testInProgressEndingExactlyAtTheGraceBoundaryStillWins() {
        let ending = event("Workshop", at(2026, 8, 22, 7), now.addingTimeInterval(NextEvent.inProgressGrace))
        let upcoming = event("Breakfast", at(2026, 8, 22, 9, 30), at(2026, 8, 22, 10))
        XCTAssertEqual(NextEvent.select(events: [ending, upcoming], now: now)?.title, "Workshop")
    }

    func testAllDayNeverWins() {
        let allDay = event("Holidays in Iran", at(2026, 8, 22, 0), at(2026, 8, 23, 0), allDay: true)
        let timed = event("Review", at(2026, 8, 22, 14), at(2026, 8, 22, 15))
        XCTAssertEqual(NextEvent.select(events: [allDay, timed], now: now)?.title, "Review")
    }

    func testAllDayOnlyYieldsNil() {
        let allDay = event("Holidays in Iran", at(2026, 8, 22, 0), at(2026, 8, 23, 0), allDay: true)
        XCTAssertNil(NextEvent.select(events: [allDay], now: now))
    }

    func testFinishedEventsIgnored() {
        let done = event("Breakfast", at(2026, 8, 22, 7), at(2026, 8, 22, 8))
        XCTAssertNil(NextEvent.select(events: [done], now: now))
    }

    func testEmptyYieldsNil() {
        XCTAssertNil(NextEvent.select(events: [], now: now))
    }

    // Ties must break deterministically or the face flickers between two
    // events on consecutive ticks.
    func testTieBreaksStablyRegardlessOfInputOrder() {
        let a = event("Alpha", at(2026, 8, 22, 10), at(2026, 8, 22, 11), id: "a")
        let b = event("Beta", at(2026, 8, 22, 10), at(2026, 8, 22, 11), calendarID: "cal-b", id: "b")
        XCTAssertEqual(NextEvent.select(events: [a, b], now: now)?.title, "Alpha")
        XCTAssertEqual(NextEvent.select(events: [b, a], now: now)?.title, "Alpha")
    }
}

// MARK: - Countdown

final class CountdownTests: XCTestCase {
    func testMoreThanAnHour() {
        XCTAssertEqual(Countdown.text(start: at(2026, 8, 22, 11, 5), now: now), "in 2h 05m")
    }

    func testUnderAnHour() {
        XCTAssertEqual(Countdown.text(start: at(2026, 8, 22, 9, 42), now: now), "in 42m")
    }

    func testExactlyOneHourReadsAsMinutes() {
        XCTAssertEqual(Countdown.text(start: at(2026, 8, 22, 10), now: now), "in 60m")
    }

    func testWithinAMinuteReadsNow() {
        XCTAssertEqual(Countdown.text(start: at(2026, 8, 22, 9, 0), now: now), "now")
        XCTAssertEqual(Countdown.text(start: now.addingTimeInterval(59), now: now), "now")
        XCTAssertEqual(Countdown.text(start: now.addingTimeInterval(-59), now: now), "now")
    }

    func testStartedReadsElapsed() {
        XCTAssertEqual(Countdown.text(start: at(2026, 8, 22, 8, 48), now: now), "12m in")
    }

    func testJustOverAMinuteAway() {
        XCTAssertEqual(Countdown.text(start: now.addingTimeInterval(61), now: now), "in 1m")
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

// MARK: - Timeline boundaries

final class TimelineBoundariesTests: XCTestCase {
    func testIncludesNowStartsEndsAndMidnight() {
        let e = event("Review", at(2026, 8, 22, 14), at(2026, 8, 22, 15))
        let entries = TimelineBoundaries.entries(events: [e], now: now, calendar: cal)
        XCTAssertEqual(entries.first, now)
        XCTAssertTrue(entries.contains(at(2026, 8, 22, 14)))
        XCTAssertTrue(entries.contains(at(2026, 8, 22, 15)))
        XCTAssertTrue(entries.contains(at(2026, 8, 23, 0)), "next midnight must be an entry")
    }

    func testSortedAndDeduplicated() {
        let a = event("A", at(2026, 8, 22, 14), at(2026, 8, 22, 15))
        let b = event("B", at(2026, 8, 22, 14), at(2026, 8, 22, 15), calendarID: "cal-b")
        let entries = TimelineBoundaries.entries(events: [a, b], now: now, calendar: cal)
        XCTAssertEqual(entries, entries.sorted())
        XCTAssertEqual(entries.count, Set(entries).count)
    }

    func testPastBoundariesExcluded() {
        let done = event("Breakfast", at(2026, 8, 22, 7), at(2026, 8, 22, 8))
        let entries = TimelineBoundaries.entries(events: [done], now: now, calendar: cal)
        XCTAssertFalse(entries.contains(at(2026, 8, 22, 7)))
        XCTAssertFalse(entries.contains(at(2026, 8, 22, 8)))
    }

    func testCappedAt24() {
        let many = (0..<40).map { i in
            event("E\(i)", now.addingTimeInterval(Double(i + 1) * 600), now.addingTimeInterval(Double(i + 1) * 600 + 300), calendarID: "cal-\(i)")
        }
        let entries = TimelineBoundaries.entries(events: many, now: now, calendar: cal)
        XCTAssertEqual(entries.count, TimelineBoundaries.maxEntries)
        XCTAssertEqual(entries.count, 24)
    }

    func testNeverEmpty() {
        let entries = TimelineBoundaries.entries(events: [], now: now, calendar: cal)
        XCTAssertEqual(entries.first, now)
        XCTAssertFalse(entries.isEmpty)
    }
}
