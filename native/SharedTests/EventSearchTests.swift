import XCTest

// Calendar events: title, location and notes, a year back and a year ahead.
// Local (EventKit): nothing is sent anywhere. Off by default, because event
// titles would show in a panel that can be on screen while sharing.

final class EventSearchTests: XCTestCase {
    /// 2026-01-15 12:00 UTC (a Thursday).
    private let now = Date(timeIntervalSince1970: 1_768_478_400)
    private let utc = TimeZone(identifier: "UTC")!
    private let posix = Locale(identifier: "en_US_POSIX")

    private func event(_ id: String, _ title: String, daysFromNow: Double = 1, location: String = "",
                       notes: String = "", calendar: String = "Work", allDay: Bool = false,
                       meeting: String = "") -> EventHit {
        let start = now.addingTimeInterval(daysFromNow * 86_400)
        return EventHit(id: id, title: title, start: start, end: start.addingTimeInterval(1800),
                        isAllDay: allDay, calendarTitle: calendar, location: location,
                        notes: notes, meetingURL: meeting)
    }

    private func search(_ q: String, _ events: [EventHit]) -> [SearchResult] {
        EventSearch.results(query: q, events: events, now: now, timeZone: utc, locale: posix)
    }

    func testMatchesTitleLocationNotesAndCalendar() {
        let events = [
            event("1", "Team standup"),
            event("2", "Lunch", location: "Standup Cafe"),
            event("3", "Planning", notes: "Bring the standup notes"),
            event("4", "Dentist", calendar: "Standup Club"),
            event("5", "Something else"),
        ]
        XCTAssertEqual(Set(search("standup", events).map(\.id)), ["event:1", "event:2", "event:3", "event:4"])
    }

    func testATitleHitOutranksANotesHit() {
        let events = [event("n", "Planning", notes: "standup"), event("t", "Standup")]
        XCTAssertEqual(SpotlightRanking.sorted(search("standup", events)).first?.id, "event:t")
    }

    /// Same relevance: the one nearest to today comes first, past or future.
    func testNearerEventsComeFirstAmongEqualMatches() {
        let events = [event("far", "Standup", daysFromNow: 200), event("near", "Standup", daysFromNow: -2),
                      event("mid", "Standup", daysFromNow: 30)]
        XCTAssertEqual(SpotlightRanking.sorted(search("standup", events)).map(\.id),
                       ["event:near", "event:mid", "event:far"])
    }

    func testTheSubtitleHasTheDateTheCalendarAndAllDay() {
        let timed = search("standup", [event("1", "Standup", daysFromNow: 1)])[0]
        XCTAssertEqual(timed.subtitle, "Fri 16 Jan 12:00 · Work")
        let allDay = search("holiday", [event("2", "Holiday", daysFromNow: 1, allDay: true)])[0]
        XCTAssertEqual(allDay.subtitle, "Fri 16 Jan · All day · Work")
    }

    func testEnterOpensAKnownMeetingLinkOtherwiseCopiesTheTitle() throws {
        let ok = search("standup", [event("1", "Standup", meeting: "https://meet.google.com/abc-defg-hij")])[0]
        XCTAssertEqual(ok.action, .open(try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))))
        XCTAssertEqual(search("standup", [event("2", "Standup")])[0].action, .copy("Standup"))
    }

    /// The link is built from calendar notes, which anyone who invites you can write.
    func testAnUnsafeLinkIsNeverOpenable() {
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "https://", "not a url"] {
            let hit = search("standup", [event("1", "Standup", meeting: bad)])[0]
            XCTAssertEqual(hit.action, .copy("Standup"), bad)
        }
    }

    func testNoMatchIsNothing() {
        XCTAssertTrue(search("zzzz", [event("1", "Standup")]).isEmpty)
    }

    func testTheTotalIsCappedAndIDsAreDistinct() {
        let many = (0..<80).map { event("e\($0)", "Standup \($0)", daysFromNow: Double($0)) }
        let hits = search("standup", many)
        XCTAssertLessThanOrEqual(hits.count, EventSearch.totalLimit)
        XCTAssertEqual(Set(hits.map(\.id)).count, hits.count)
    }

    func testTheSearchWindowIsAYearEitherSideOfNow() {
        let w = EventSearch.window(now: now)
        XCTAssertEqual(w.start, now.addingTimeInterval(-365 * 86_400))
        XCTAssertEqual(w.end, now.addingTimeInterval(365 * 86_400))
    }

    func testLongNotesAreTruncatedBeforeMatching() {
        XCTAssertLessThanOrEqual(EventSearch.truncatedNotes(String(repeating: "x", count: 5000)).count,
                                 EventSearch.maxNotesLength)
        XCTAssertEqual(EventSearch.truncatedNotes(nil), "")
    }
}

final class CalendarAccessTests: XCTestCase {
    // EKAuthorizationStatus raw values: notDetermined 0, restricted 1, denied 2,
    // fullAccess 3, writeOnly 4. Pinned: a renumbering would otherwise silently
    // turn "denied" into "allowed".
    func testOnlyFullAccessCanRead() {
        XCTAssertTrue(CalendarAccess.canRead(rawStatus: 3))
        for raw in [0, 1, 2, 4, 99] { XCTAssertFalse(CalendarAccess.canRead(rawStatus: raw), "\(raw)") }
    }

    func testOnlyNotDeterminedMayBePromptedFor() {
        XCTAssertTrue(CalendarAccess.shouldPrompt(rawStatus: 0))
        for raw in [1, 2, 3, 4] { XCTAssertFalse(CalendarAccess.shouldPrompt(rawStatus: raw), "\(raw)") }
    }

    /// Write-only access cannot read events: reported as "can't read", not as granted.
    func testWriteOnlyIsADenial() {
        XCTAssertFalse(CalendarAccess.canRead(rawStatus: 4))
    }
}
