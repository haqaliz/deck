import XCTest

// Pure-logic suite for the SESSIONS slice: row mapping (order by total
// tokens, top-N cap, title filtering, epoch-ms → Date) and the relative-time
// formatter. Mirrors the ToolCountTests style against Shared parsers.

final class OpenBoxSessionCoreTests: XCTestCase {
    private func row(_ title: String?, _ input: Int64?, _ output: Int64?, _ timeMs: Int64?) -> [String: Any] {
        var r: [String: Any] = [:]
        if let title { r["title"] = title }
        if let input { r["tokens_input"] = input }
        if let output { r["tokens_output"] = output }
        if let timeMs { r["time_created"] = timeMs }
        return r
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let hourMs: Int64 = 3_600_000

    // MARK: - Mapper

    func testEmptyRowsMapToEmpty() {
        XCTAssertEqual(OpenBoxSessionList.map([], now: now, limit: 3), [])
    }

    func testRowsOrderByTotalTokensDescending() {
        let rows: [[String: Any]] = [
            row("small", 100, 100, 1_700_000_000_000), // 200
            row("big", 500, 100, 1_700_000_000_000), // 600
            row("mid", 200, 200, 1_700_000_000_000), // 400
        ]
        XCTAssertEqual(OpenBoxSessionList.map(rows, now: now, limit: 3).map(\.title), ["big", "mid", "small"])
    }

    func testMapperCapsAtLimitKeepingTopByTokens() {
        let rows: [[String: Any]] = [
            row("a", 10, 0, 1_700_000_000_000),
            row("b", 20, 0, 1_700_000_000_000),
            row("c", 30, 0, 1_700_000_000_000),
            row("d", 40, 0, 1_700_000_000_000),
            row("e", 50, 0, 1_700_000_000_000),
        ]
        XCTAssertEqual(OpenBoxSessionList.map(rows, now: now, limit: 3).map(\.title), ["e", "d", "c"])
    }

    func testNilAndEmptyTitlesAreDropped() {
        let rows: [[String: Any]] = [
            row("keep", 10, 0, 1_700_000_000_000),
            row(nil, 999, 0, 1_700_000_000_000),
            row("", 888, 0, 1_700_000_000_000),
        ]
        XCTAssertEqual(OpenBoxSessionList.map(rows, now: now, limit: 3).map(\.title), ["keep"])
    }

    func testTimeCreatedDecodesFromEpochMilliseconds() {
        let ms: Int64 = 1_700_000_123_000
        let rows: [[String: Any]] = [row("s", 1, 0, ms)]
        XCTAssertEqual(OpenBoxSessionList.map(rows, now: now, limit: 3).first?.timeCreated,
                       Date(timeIntervalSince1970: 1_700_000_123))
    }

    func testMissingTokenFieldsDefaultToZero() {
        let rows: [[String: Any]] = [
            ["title": "s"],
        ]
        let mapped = OpenBoxSessionList.map(rows, now: now, limit: 3)
        XCTAssertEqual(mapped.first?.input, 0)
        XCTAssertEqual(mapped.first?.output, 0)
    }

    // MARK: - Relative time

    func testRelativeTimeJustNowUnderMinute() {
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(-30)), "just now")
    }

    func testRelativeTimeMinutes() {
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(-90)), "1m ago")
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(-600)), "10m ago")
    }

    func testRelativeTimeHours() {
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(-7200)), "2h ago")
    }

    func testRelativeTimeDays() {
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(-86_400)), "1d ago")
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(-3 * 86_400)), "3d ago")
    }

    func testRelativeTimeFutureClampsToJustNow() {
        XCTAssertEqual(OpenBoxSessionList.relativeTime(from: now, to: now.addingTimeInterval(300)), "just now")
    }
}
