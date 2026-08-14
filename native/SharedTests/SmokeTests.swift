import XCTest

final class SmokeTests: XCTestCase {
    func testGitLogParserDayCounts() {
        let raw = """
        2026-08-14
        2026-08-14
        2026-08-13
        not-a-day
        """
        let counts = GitLogParser.dayCounts(from: raw)
        XCTAssertEqual(counts["2026-08-14"], 2)
        XCTAssertEqual(counts["2026-08-13"], 1)
        XCTAssertEqual(counts.count, 2)
    }
}
