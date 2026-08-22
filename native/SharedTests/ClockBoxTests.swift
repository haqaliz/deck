import XCTest

// ClockBox pure logic. Ported from ZoneRowsTests (HomeBoxSnapshotTests.swift)
// when the world-clock half of HomeBox became its own widget, and extended
// with the cases the old zone rows never had to answer: offset-from-local,
// relative day, and the small-face city pick.
//
// Every test pins an explicit `at:` date. Nothing here may read the wall
// clock — a clock library whose tests depend on when they run is untestable.

final class ClockBoxCoreTests: XCTestCase {
    /// 2026-08-14 12:34:56 UTC.
    private var noonUTC: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12, minute: 34, second: 56))!
    }

    /// 2026-01-14 12:34:56 UTC — northern-hemisphere winter, so zones that
    /// observe DST sit at a different offset than they do at `noonUTC`.
    private var winterUTC: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 1, day: 14, hour: 12, minute: 34, second: 56))!
    }

    // MARK: - resolve

    func testResolveMapsIdentifierToZone() {
        XCTAssertEqual(ClockBoxCore.resolve(id: "Europe/Amsterdam")?.identifier, "Europe/Amsterdam")
    }

    func testResolveInvalidIdentifierReturnsNil() {
        XCTAssertNil(ClockBoxCore.resolve(id: "Mars/Olympus"))
        XCTAssertNil(ClockBoxCore.resolve(id: ""))
        XCTAssertNil(ClockBoxCore.resolve(id: "   "))
    }

    func testLocalSentinelResolvesToCurrentZone() {
        XCTAssertEqual(ClockBoxCore.resolve(id: ClockBoxCore.localID), TimeZone.current)
    }

    // MARK: - display names

    func testCuratedCityNameWins() {
        XCTAssertEqual(ClockBoxCore.displayName(id: "America/Toronto"), "Toronto")
        XCTAssertEqual(ClockBoxCore.displayName(id: "Asia/Tehran"), "Tehran")
    }

    /// An id outside the curated table still renders something sane rather
    /// than the raw identifier.
    func testUncuratedIdentifierFallsBackToLastPathComponent() {
        XCTAssertEqual(ClockBoxCore.displayName(id: "America/Argentina/Buenos_Aires"), "Buenos Aires")
    }

    /// The local sentinel is labelled with the real city, matching the native
    /// widget, not the word "Local".
    func testLocalSentinelIsLabelledWithItsCity() {
        let name = ClockBoxCore.displayName(id: ClockBoxCore.localID)
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, ClockBoxCore.localID)
        XCTAssertFalse(name.contains("/"))
    }

    // MARK: - time

    func testFormatsTimeInEachZone() {
        XCTAssertEqual(ClockBoxCore.timeLabel(id: "UTC", at: noonUTC), "12:34")
        XCTAssertEqual(ClockBoxCore.timeLabel(id: "Europe/Amsterdam", at: noonUTC), "14:34")
        XCTAssertEqual(ClockBoxCore.timeLabel(id: "Asia/Tokyo", at: noonUTC), "21:34")
    }

    // MARK: - offset from local (NOT from UTC)

    func testOffsetIsRelativeToTheReferenceZoneNotUTC() {
        let tehran = TimeZone(identifier: "Asia/Tehran")!
        // Toronto is 7h30m behind Tehran in August 2026.
        XCTAssertEqual(
            ClockBoxCore.offsetLabel(id: "America/Toronto", relativeTo: tehran, at: noonUTC),
            "-7:30"
        )
    }

    func testSameZoneRendersZeroHours() {
        let tehran = TimeZone(identifier: "Asia/Tehran")!
        XCTAssertEqual(
            ClockBoxCore.offsetLabel(id: "Asia/Tehran", relativeTo: tehran, at: noonUTC),
            "+0HRS"
        )
    }

    func testPositiveOffsetIsSigned() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ClockBoxCore.offsetLabel(id: "Asia/Tokyo", relativeTo: utc, at: noonUTC), "+9:00")
    }

    /// Kathmandu is +5:45 — minutes must never be rounded to a whole or half
    /// hour.
    func testNonHourOffsetKeepsExactMinutes() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ClockBoxCore.offsetLabel(id: "Asia/Kathmandu", relativeTo: utc, at: noonUTC), "+5:45")
    }

    /// The whole reason offsets are computed with `secondsFromGMT(for:)`: New
    /// York is 4h behind UTC in August and 5h behind in January. A static
    /// offset would be wrong for half the year.
    func testOffsetFollowsDaylightSaving() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ClockBoxCore.offsetLabel(id: "America/New_York", relativeTo: utc, at: noonUTC), "-4:00")
        XCTAssertEqual(ClockBoxCore.offsetLabel(id: "America/New_York", relativeTo: utc, at: winterUTC), "-5:00")
    }

    /// Both sides shift, and not necessarily on the same dates: Amsterdam
    /// observes DST, Tehran (since 2022) does not.
    func testOffsetHandlesBothZonesShiftingIndependently() {
        let tehran = TimeZone(identifier: "Asia/Tehran")!
        XCTAssertEqual(
            ClockBoxCore.offsetLabel(id: "Europe/Amsterdam", relativeTo: tehran, at: noonUTC),
            "-1:30"
        )
        XCTAssertEqual(
            ClockBoxCore.offsetLabel(id: "Europe/Amsterdam", relativeTo: tehran, at: winterUTC),
            "-2:30"
        )
    }

    // MARK: - relative day

    func testRelativeDayToday() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ClockBoxCore.relativeDay(id: "Europe/Amsterdam", relativeTo: utc, at: noonUTC), .today)
    }

    /// At 12:34 UTC it is already 21:34 in Tokyo — same day. At 23:34 UTC it
    /// is 08:34 the next morning there.
    func testRelativeDayTomorrow() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let lateUTC = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 23, minute: 34))!
        XCTAssertEqual(ClockBoxCore.relativeDay(id: "Asia/Tokyo", relativeTo: utc, at: lateUTC), .tomorrow)
    }

    func testRelativeDayYesterday() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let earlyUTC = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 2, minute: 15))!
        XCTAssertEqual(ClockBoxCore.relativeDay(id: "America/Los_Angeles", relativeTo: utc, at: earlyUTC), .yesterday)
    }

    // MARK: - rows

    func testRowsBuildsOnePerIdentifierInOrder() {
        let rows = ClockBoxCore.rows(ids: ["UTC", "Europe/Amsterdam"], relativeTo: TimeZone(secondsFromGMT: 0)!, at: noonUTC)
        XCTAssertEqual(rows.map(\.name), ["UTC", "Amsterdam"])
        XCTAssertEqual(rows.map(\.time), ["12:34", "14:34"])
    }

    func testRowsDropInvalidIdentifiers() {
        let rows = ClockBoxCore.rows(
            ids: ["UTC", "Not/AZone", "", "Mars/Olympus"],
            relativeTo: TimeZone(secondsFromGMT: 0)!,
            at: noonUTC
        )
        XCTAssertEqual(rows.map(\.name), ["UTC"])
    }

    /// Storage holds up to 6; each face applies its own limit.
    func testRowsCapAtSixKeepingOrder() {
        let rows = ClockBoxCore.rows(
            ids: ["UTC", "Asia/Tokyo", "Europe/Amsterdam", "America/New_York", "Asia/Tehran",
                  "Australia/Sydney", "Europe/Paris"],
            relativeTo: TimeZone(secondsFromGMT: 0)!,
            at: noonUTC
        )
        XCTAssertEqual(rows.count, ClockBoxCore.maxCities)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.map(\.name).last, "Sydney")
    }

    /// Medium shows 3, large shows 6 — the caller passes its own limit rather
    /// than the core knowing about widget families (Shared has no WidgetKit).
    func testRowsRespectAnExplicitLimit() {
        let ids = ["UTC", "Asia/Tokyo", "Europe/Amsterdam", "America/New_York", "Asia/Tehran", "Europe/Paris"]
        let medium = ClockBoxCore.rows(ids: ids, relativeTo: TimeZone(secondsFromGMT: 0)!, at: noonUTC, limit: ClockBoxCore.mediumCapacity)
        XCTAssertEqual(medium.count, 3)
        XCTAssertEqual(medium.map(\.name), ["UTC", "Tokyo", "Amsterdam"])

        let large = ClockBoxCore.rows(ids: ids, relativeTo: TimeZone(secondsFromGMT: 0)!, at: noonUTC, limit: ClockBoxCore.largeCapacity)
        XCTAssertEqual(large.count, 6)
    }

    func testCapacitiesAreThreeAndSix() {
        XCTAssertEqual(ClockBoxCore.mediumCapacity, 3)
        XCTAssertEqual(ClockBoxCore.largeCapacity, 6)
        XCTAssertEqual(ClockBoxCore.maxCities, 6)
    }

    func testRowsEmptyInputYieldsNoRows() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(ClockBoxCore.rows(ids: [], relativeTo: utc, at: noonUTC).isEmpty)
        XCTAssertTrue(ClockBoxCore.rows(ids: ["Bad/Zone"], relativeTo: utc, at: noonUTC).isEmpty)
    }

    // MARK: - main clock (drives the small face)

    /// An explicit main choice wins, whatever its position in the list.
    func testExplicitMainWins() {
        XCTAssertEqual(
            ClockBoxCore.mainCityID(ids: ["Asia/Tokyo", "UTC", "Europe/Paris"], preferred: "Europe/Paris"),
            "Europe/Paris"
        )
    }

    /// The user may legitimately choose their own zone as the main clock.
    func testExplicitMainMayBeLocal() {
        XCTAssertEqual(
            ClockBoxCore.mainCityID(ids: [ClockBoxCore.localID, "UTC"], preferred: ClockBoxCore.localID),
            ClockBoxCore.localID
        )
    }

    /// A main that is no longer in the city list must not win — it would show
    /// a clock the user has since removed.
    func testStaleMainFallsBackToAuto() {
        XCTAssertEqual(
            ClockBoxCore.mainCityID(ids: ["Asia/Tokyo", "UTC"], preferred: "Europe/Paris"),
            "Asia/Tokyo"
        )
    }

    /// Auto (no explicit choice) keeps the old rule: first non-local, because
    /// a small widget showing your own zone at +0HRS tells you nothing.
    func testAutoPrefersFirstNonLocal() {
        XCTAssertEqual(ClockBoxCore.mainCityID(ids: [ClockBoxCore.localID, "UTC"], preferred: nil), "UTC")
        XCTAssertEqual(ClockBoxCore.mainCityID(ids: [ClockBoxCore.localID, "UTC"], preferred: ""), "UTC")
        XCTAssertEqual(ClockBoxCore.mainCityID(ids: ["Asia/Tokyo", "UTC"], preferred: nil), "Asia/Tokyo")
    }

    func testAutoFallsBackToLocalWhenItIsTheOnlyEntry() {
        XCTAssertEqual(ClockBoxCore.mainCityID(ids: [ClockBoxCore.localID], preferred: nil), ClockBoxCore.localID)
    }

    func testMainIsNilWhenNothingIsSelected() {
        XCTAssertNil(ClockBoxCore.mainCityID(ids: [], preferred: nil))
        XCTAssertNil(ClockBoxCore.mainCityID(ids: [], preferred: "Europe/Paris"))
    }

    /// An invalid explicit main is ignored rather than blanking the face.
    func testInvalidMainFallsBackToAuto() {
        XCTAssertEqual(ClockBoxCore.mainCityID(ids: ["UTC"], preferred: "Mars/Olympus"), "UTC")
    }

    func testMainSkipsInvalidIdentifiers() {
        XCTAssertNil(ClockBoxCore.mainCityID(ids: ["Bad/Zone", ""], preferred: nil))
    }

    // MARK: - curated city table

    func testCuratedTableIsNonEmptyAndAllIdentifiersResolve() {
        XCTAssertGreaterThan(ClockBoxCities.curated.count, 50)
        for city in ClockBoxCities.curated {
            XCTAssertNotNil(TimeZone(identifier: city.id), "unresolvable curated id: \(city.id)")
        }
    }

    func testCuratedTableHasNoDuplicateIdentifiers() {
        let ids = ClockBoxCities.curated.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCuratedNamesCarryTheirCountry() {
        let toronto = ClockBoxCities.curated.first { $0.id == "America/Toronto" }
        XCTAssertEqual(toronto?.displayName, "Toronto, Canada")
    }
}
