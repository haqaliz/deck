import XCTest
@testable import GitBoxCore

final class GitLogParserTests: XCTestCase {
    func testCountsLinesPerDay() {
        let raw = "2026-08-10\n2026-08-10\n2026-08-09\n2026-08-08\n"
        XCTAssertEqual(GitLogParser.dayCounts(from: raw), [
            "2026-08-10": 2,
            "2026-08-09": 1,
            "2026-08-08": 1,
        ])
    }

    func testCountsSingleLine() {
        XCTAssertEqual(GitLogParser.dayCounts(from: "2026-08-10\n"), ["2026-08-10": 1])
    }

    func testEmptyIsEmpty() {
        XCTAssertEqual(GitLogParser.dayCounts(from: ""), [:])
        XCTAssertEqual(GitLogParser.dayCounts(from: "\n\n"), [:])
    }

    func testSkipsGarbageAndMalformedDates() {
        let raw = "2026-08-10\nnot a date\n2026-8-10\n2026-13-99\n\n2026-08-11\n"
        XCTAssertEqual(GitLogParser.dayCounts(from: raw), [
            "2026-08-10": 1,
            "2026-08-11": 1,
        ])
    }

    func testSkipsWhitespaceSurroundedDates() {
        XCTAssertEqual(GitLogParser.dayCounts(from: "  2026-08-10  \n"), [:])
    }
}
