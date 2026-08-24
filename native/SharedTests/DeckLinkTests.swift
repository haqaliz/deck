import XCTest

// One rule for every clickable row in Deck.
//
// Widget rows link to things that live on the web, and every one of those URLs
// arrives from a snapshot file on disk. That file is data, not instruction, so
// the same restriction applies wherever a row becomes a link: http(s), with a
// host, or it is not a link at all.

final class DeckLinkTests: XCTestCase {
    func testAcceptsHTTPS() {
        XCTAssertEqual(
            DeckLink.webURL(from: "https://github.com/haqaliz/deck/pull/33"),
            URL(string: "https://github.com/haqaliz/deck/pull/33")
        )
    }

    func testAcceptsPlainHTTPForSelfHostedServers() {
        XCTAssertEqual(
            DeckLink.webURL(from: "http://ghe.internal/org/repo/pull/2"),
            URL(string: "http://ghe.internal/org/repo/pull/2")
        )
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(
            DeckLink.webURL(from: "  https://example.com/x  "),
            URL(string: "https://example.com/x")
        )
    }

    func testRejectsEmpty() {
        XCTAssertNil(DeckLink.webURL(from: ""))
        XCTAssertNil(DeckLink.webURL(from: "    "))
    }

    func testRejectsNonWebSchemes() {
        XCTAssertNil(DeckLink.webURL(from: "file:///etc/passwd"))
        XCTAssertNil(DeckLink.webURL(from: "javascript:alert(1)"))
        XCTAssertNil(DeckLink.webURL(from: "ftp://example.com/x"))
        XCTAssertNil(DeckLink.webURL(from: "mailto:someone@example.com"))
    }

    /// Calendar invites often carry a `message://` URL pointing back at the
    /// Mail message that created them. Useful to a person, not something a
    /// widget row should launch.
    func testRejectsMessageURLs() {
        XCTAssertNil(DeckLink.webURL(from: "message://%3C1234@mail.example.com%3E"))
    }

    func testRejectsHostlessURLs() {
        XCTAssertNil(DeckLink.webURL(from: "https://"))
        XCTAssertNil(DeckLink.webURL(from: "not a url at all"))
    }

    func testSchemeMatchingIsCaseInsensitive() {
        XCTAssertNotNil(DeckLink.webURL(from: "HTTPS://example.com/x"))
    }
}

// MARK: - TaskBox rows

final class TaskBoxLinkTests: XCTestCase {
    private func task(url: String) -> TaskItem {
        TaskItem(
            id: "7444", title: "Use feed API in all Providers", state: "Committed",
            itemType: "Product Backlog Item", url: url, provider: .azureDevOps,
            changedAt: nil
        )
    }

    /// The work-item URL the Azure loader already builds.
    func testWorkItemURLIsClickable() {
        let url = "https://dev.azure.com/org/proj/_workitems/edit/7444"
        XCTAssertEqual(TaskFormatting.destination(for: task(url: url)), URL(string: url))
    }

    func testTaskWithoutAURLIsNotClickable() {
        XCTAssertNil(TaskFormatting.destination(for: task(url: "")))
    }
}

// MARK: - CalBox rows

final class CalBoxLinkTests: XCTestCase {
    private func event(url: String) -> CalEvent {
        CalEvent(
            id: "abc/0", title: "Standup",
            start: Date(timeIntervalSince1970: 1_787_000_000),
            end: Date(timeIntervalSince1970: 1_787_001_800),
            isAllDay: false, calendarTitle: "Work", calendarID: "cal-1",
            color: RGBA(red: 0.2, green: 0.4, blue: 0.9), url: url
        )
    }

    /// The common useful case: the invite's URL is the video call.
    func testMeetingLinkIsClickable() {
        let url = "https://meet.google.com/abc-defg-hij"
        XCTAssertEqual(CalFormatting.destination(for: event(url: url)), URL(string: url))
    }

    /// Plenty of events carry no URL at all — those rows stay plain text.
    func testEventWithoutAURLIsNotClickable() {
        XCTAssertNil(CalFormatting.destination(for: event(url: "")))
    }

    func testEventWithAMailURLIsNotClickable() {
        XCTAssertNil(CalFormatting.destination(for: event(url: "message://%3Cabc@mail%3E")))
    }

    // MARK: Schema migration

    /// A `calbox.json` written before events carried a URL must still decode.
    /// The agent rewrites it within a minute, but the widget must not render
    /// an empty agenda in the meantime.
    func testEventFromAnOlderSnapshotDecodesWithoutAURL() throws {
        let json = """
        {"id":"abc/0","title":"Standup","start":0,"end":1800,"isAllDay":false,
         "calendarTitle":"Work","calendarID":"cal-1",
         "color":{"red":0.2,"green":0.4,"blue":0.9,"alpha":1}}
        """
        let event = try JSONDecoder().decode(CalEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.title, "Standup")
        XCTAssertEqual(event.url, "")
        XCTAssertNil(CalFormatting.destination(for: event))
    }

    func testRoundTripsWithAURL() throws {
        let original = event(url: "https://meet.google.com/abc-defg-hij")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CalEvent.self, from: data), original)
    }
}

// MARK: - Finding the meeting link in a calendar event
//
// `EKEvent.url` sounds like the right field and is empty in practice: measured
// across a real account, 0 of 10 events set it, 0 had a URL in `location`, and
// 9 of 10 carried one in `notes`.
//
// The notes are not a single link, though. Every Google invite in that sample
// contained three hosts — `meet.google.com` (the call), `support.google.com`
// ("Learn more about Meet") and `tel.meet` (dial-in) — so "the first URL in
// the notes" would sooner or later open a help page from a click on a meeting.
// Known conferencing hosts are matched instead, and an event with none simply
// is not a link.

final class CalendarLinkTests: XCTestCase {
    /// The shape a Google Meet invite actually arrives in.
    private let googleNotes = """
    Hi there, you have been invited.

    Join with Google Meet: https://meet.google.com/abc-defg-hij
    Or dial: (US) +1 555-555-5555 PIN: 123456789#
    More phone numbers: https://tel.meet/abc-defg-hij?pin=123456789

    Learn more about Meet at: https://support.google.com/a/users/answer/9282720
    """

    func testPrefersTheMeetingHostOverBoilerplate() {
        XCTAssertEqual(
            CalendarLink.meetingURL(url: nil, location: nil, notes: googleNotes),
            "https://meet.google.com/abc-defg-hij"
        )
    }

    /// The specific regression the probe warned about.
    func testNeverReturnsTheLearnMoreLink() {
        let found = CalendarLink.meetingURL(url: nil, location: nil, notes: googleNotes) ?? ""
        XCTAssertFalse(found.contains("support.google.com"))
        XCTAssertFalse(found.contains("tel.meet"))
    }

    func testEventURLWinsWhenPresent() {
        XCTAssertEqual(
            CalendarLink.meetingURL(
                url: "https://zoom.us/j/123", location: nil, notes: googleNotes
            ),
            "https://zoom.us/j/123"
        )
    }

    /// Zoom and Teams invites often put the link in the location field.
    func testFallsBackToLocation() {
        XCTAssertEqual(
            CalendarLink.meetingURL(
                url: nil, location: "https://acme.zoom.us/j/98765?pwd=xyz", notes: nil
            ),
            "https://acme.zoom.us/j/98765?pwd=xyz"
        )
    }

    func testRecognisesCommonProviders() {
        let hosts = [
            "https://meet.google.com/x",
            "https://zoom.us/j/1",
            "https://acme.zoom.us/j/1",
            "https://teams.microsoft.com/l/meetup-join/x",
            "https://acme.webex.com/meet/x",
            "https://whereby.com/room",
        ]
        for host in hosts {
            XCTAssertEqual(
                CalendarLink.meetingURL(url: nil, location: nil, notes: "Join: \(host)"),
                host,
                "did not recognise \(host)"
            )
        }
    }

    /// A physical room is not a link.
    func testPlainLocationIsNotAURL() {
        XCTAssertNil(CalendarLink.meetingURL(url: nil, location: "Meeting Room 3", notes: nil))
    }

    func testNotesWithOnlyUnrelatedLinksAreNotALink() {
        let notes = "Agenda: https://wiki.internal/agenda and https://support.google.com/x"
        XCTAssertNil(CalendarLink.meetingURL(url: nil, location: nil, notes: notes))
    }

    func testEmptyEventHasNoLink() {
        XCTAssertNil(CalendarLink.meetingURL(url: nil, location: nil, notes: nil))
        XCTAssertNil(CalendarLink.meetingURL(url: "", location: "", notes: ""))
    }

    /// `tel.meet` is a dial-in helper, not the call.
    func testDialInHostIsNotAMeetingLink() {
        XCTAssertNil(
            CalendarLink.meetingURL(url: nil, location: nil, notes: "https://tel.meet/abc?pin=1")
        )
    }

    /// A host must match the provider exactly or as a subdomain — never as a
    /// substring, or `zoom.us.evil.com` would pass.
    func testLookalikeHostIsRejected() {
        XCTAssertNil(
            CalendarLink.meetingURL(url: nil, location: nil, notes: "https://zoom.us.evil.com/j/1")
        )
        XCTAssertNil(
            CalendarLink.meetingURL(url: nil, location: nil, notes: "https://notzoom.us/j/1")
        )
    }
}
