import XCTest

// Fresh suite: GitLogParser + the GitBox math/formatters never had scratch
// tests (GitBox predates the scratch-package pattern). Written from behavior.
// The merged code has no GitBox formatters — counts are formatted inline in
// the widget — so the formatter coverage lives in OpenCodeFormattersTests.

final class GitLogParserTests: XCTestCase {
    func testCountsValidDayLines() {
        let raw = """
        2026-08-14
        2026-08-14
        2026-08-13
        2026-08-12
        """
        let counts = GitLogParser.dayCounts(from: raw)
        XCTAssertEqual(counts["2026-08-14"], 2)
        XCTAssertEqual(counts["2026-08-13"], 1)
        XCTAssertEqual(counts["2026-08-12"], 1)
        XCTAssertEqual(counts.count, 3)
    }

    func testSkipsNonDayLines() {
        let raw = """
        2026-08-14
        not-a-day
        2026-13-45
        2026-08-1
        2026-08-14 trailing
        """
        let counts = GitLogParser.dayCounts(from: raw)
        XCTAssertEqual(counts["2026-08-14"], 1)
        XCTAssertEqual(counts.count, 1)
    }

    func testSkipsImpossibleCalendarDates() {
        // 2026-02-30 and 2026-04-31 don't exist — rejected by the formatter.
        let raw = """
        2026-02-30
        2026-04-31
        2026-02-28
        """
        let counts = GitLogParser.dayCounts(from: raw)
        XCTAssertEqual(counts["2026-02-28"], 1)
        XCTAssertEqual(counts.count, 1)
    }

    func testEmptyInputYieldsNoCounts() {
        XCTAssertEqual(GitLogParser.dayCounts(from: ""), [:])
        XCTAssertEqual(GitLogParser.dayCounts(from: "\n\n"), [:])
    }
}

final class GitBoxWindowTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 12))!
    }

    func testDaysBackBuildsConsecutiveWindowEndingToday() {
        let window = HostGitBoxSampler.daysBack(5, today: date(14), calendar: utcCalendar)
        XCTAssertEqual(window, ["2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"])
    }

    func testDaysBackZeroOrNegativeIsEmpty() {
        XCTAssertEqual(HostGitBoxSampler.daysBack(0, today: date(14), calendar: utcCalendar), [])
        XCTAssertEqual(HostGitBoxSampler.daysBack(-3, today: date(14), calendar: utcCalendar), [])
    }

    func testDayLabelFormatsPadded() {
        XCTAssertEqual(HostGitBoxSampler.dayLabel(date(3), calendar: utcCalendar), "2026-08-03")
    }

    func testShortNameTakesLastPathComponent() {
        XCTAssertEqual(HostGitBoxSampler.shortName(path: "/Users/aliz/dev/at/deck"), "deck")
        XCTAssertEqual(HostGitBoxSampler.shortName(path: "/Users/aliz/dev/at/deck/"), "deck")
        XCTAssertEqual(HostGitBoxSampler.shortName(path: "deck"), "deck")
    }
}

final class GitBoxStreakTests: XCTestCase {
    /// 2026-08-10 … 2026-08-14.
    private var window: [String] {
        ["2026-08-10", "2026-08-11", "2026-08-12", "2026-08-13", "2026-08-14"]
    }

    func testNoCommitsYieldsZero() {
        XCTAssertEqual(HostGitBoxSampler.streak(counts: [:], window: window), 0)
    }

    func testEmptyTodayAnchorsAtYesterday() {
        let counts = ["2026-08-13": 2]
        XCTAssertEqual(HostGitBoxSampler.streak(counts: counts, window: window), 1)
    }

    func testTodayCountsExtendsTheRun() {
        let counts = ["2026-08-14": 1, "2026-08-13": 3, "2026-08-12": 1]
        XCTAssertEqual(HostGitBoxSampler.streak(counts: counts, window: window), 3)
    }

    func testGapBreaksTheRun() {
        let counts = ["2026-08-14": 1, "2026-08-12": 1, "2026-08-11": 1]
        XCTAssertEqual(HostGitBoxSampler.streak(counts: counts, window: window), 1)
    }

    func testFullWindowRun() {
        let counts = Dictionary(uniqueKeysWithValues: window.map { ($0, 1) })
        XCTAssertEqual(HostGitBoxSampler.streak(counts: counts, window: window), 5)
    }

    func testEmptyWindowYieldsZero() {
        XCTAssertEqual(HostGitBoxSampler.streak(counts: ["2026-08-14": 1], window: []), 0)
    }
}
