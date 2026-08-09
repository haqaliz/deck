import XCTest
@testable import GitBoxCore

final class GitMathTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, from date: Date) -> String {
        let day = calendar.date(byAdding: .day, value: offset, to: date)!
        return GitMath.dayLabel(day, calendar: calendar)
    }

    func testDayLabelFormatsPadded() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        XCTAssertEqual(GitMath.dayLabel(date, calendar: calendar), "2026-08-05")
    }

    func testDaysBack14EndsAtToday() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let window = GitMath.daysBack(14, today: today, calendar: calendar)
        XCTAssertEqual(window.count, 14)
        XCTAssertEqual(window.first, "2026-07-28")
        XCTAssertEqual(window.last, "2026-08-10")
    }

    func testDaysBack1IsToday() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        XCTAssertEqual(GitMath.daysBack(1, today: today, calendar: calendar), ["2026-08-10"])
    }

    func testBucketOrdersAndDropsOutOfWindow() {
        let counts = [
            "2026-08-09": 3,
            "2026-08-10": 1,
            "2026-07-01": 99,
        ]
        let window = ["2026-08-08", "2026-08-09", "2026-08-10"]
        XCTAssertEqual(GitMath.bucket(counts: counts, window: window), [0, 3, 1])
    }

    func testStreakTodayFull() {
        let window = [day(-1, from: base), day(0, from: base)]
        let counts = [day(-1, from: base): 2, day(0, from: base): 1]
        XCTAssertEqual(GitMath.streak(counts: counts, window: window), 2)
    }

    func testStreakGraceTodayEmptyCountsFromYesterday() {
        let window = [day(-2, from: base), day(-1, from: base), day(0, from: base)]
        let counts = [day(-2, from: base): 1, day(-1, from: base): 1]
        XCTAssertEqual(GitMath.streak(counts: counts, window: window), 2)
    }

    func testStreakGraceTodayAndYesterdayEmptyIsZero() {
        let window = [day(-1, from: base), day(0, from: base)]
        let counts = [day(-1, from: base): 0]
        XCTAssertEqual(GitMath.streak(counts: counts, window: window), 0)
    }

    func testStreakGapBreaksRun() {
        let window = [day(-2, from: base), day(-1, from: base), day(0, from: base)]
        let counts = [day(-2, from: base): 4, day(-1, from: base): 0]
        XCTAssertEqual(GitMath.streak(counts: counts, window: window), 0)
    }

    func testStreakNoCommitsIsZero() {
        let window = [day(-2, from: base), day(-1, from: base), day(0, from: base)]
        XCTAssertEqual(GitMath.streak(counts: [:], window: window), 0)
    }

    func testStreakEmptyWindowIsZero() {
        XCTAssertEqual(GitMath.streak(counts: ["2026-08-10": 1], window: []), 0)
    }

    func testStreakLongRunCappedByWindow() {
        let window = [day(-3, from: base), day(-2, from: base), day(-1, from: base), day(0, from: base)]
        let counts = [day(-3, from: base): 1, day(-2, from: base): 1, day(-1, from: base): 1, day(0, from: base): 1]
        XCTAssertEqual(GitMath.streak(counts: counts, window: window), 4)
    }

    private var base: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
    }
}
