import XCTest
@testable import HomeBoxCore

final class ZoneRowsTests: XCTestCase {
    /// 2026-08-14 12:34:56 UTC.
    private var noonUTC: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12, minute: 34, second: 56))!
    }

    func testFormatsTimeInEachZone() {
        let rows = ZoneRows.build(identifiers: ["UTC", "Europe/Amsterdam"], at: noonUTC)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].label, "UTC")
        XCTAssertEqual(rows[0].time, "12:34")
        XCTAssertEqual(rows[1].label, "Amsterdam")
        XCTAssertEqual(rows[1].time, "14:34")
    }

    func testLocalIdentifierResolvesToCurrentZoneFirst() {
        let rows = ZoneRows.build(identifiers: ["UTC", "local"], at: noonUTC)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].label, "Local")
        let local = TimeZone.current
        let seconds = local.secondsFromGMT(for: noonUTC)
        let shifted = noonUTC.addingTimeInterval(TimeInterval(seconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.hour, .minute], from: shifted)
        let expected = String(format: "%02d:%02d", components.hour!, components.minute!)
        XCTAssertEqual(rows[0].time, expected)
        XCTAssertEqual(rows[1].label, "UTC")
    }

    func testInvalidIdentifiersAreDropped() {
        let rows = ZoneRows.build(identifiers: ["UTC", "Not/AZone", "", "Mars/Olympus"], at: noonUTC)
        XCTAssertEqual(rows.map(\.label), ["UTC"])
    }

    func testCapsAtThreeRowsKeepingOrder() {
        let rows = ZoneRows.build(
            identifiers: ["UTC", "Asia/Tokyo", "Europe/Amsterdam", "America/New_York"],
            at: noonUTC
        )
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.label), ["UTC", "Tokyo", "Amsterdam"])
    }

    func testEmptyInputYieldsNoRows() {
        XCTAssertTrue(ZoneRows.build(identifiers: [], at: noonUTC).isEmpty)
        XCTAssertTrue(ZoneRows.build(identifiers: ["Bad/Zone"], at: noonUTC).isEmpty)
    }
}
