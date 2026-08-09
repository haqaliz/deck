import XCTest
@testable import BatBoxCore

final class BatteryMathTests: XCTestCase {
    func testPercentSimple() {
        XCTAssertEqual(try XCTUnwrap(BatteryMath.percent(current: 71, maxCapacity: 100)), 71, accuracy: 0.001)
    }

    func testPercentClampsAtOneHundred() {
        XCTAssertEqual(try XCTUnwrap(BatteryMath.percent(current: 120, maxCapacity: 100)), 100, accuracy: 0.001)
    }

    func testPercentClampsAtZero() {
        XCTAssertEqual(try XCTUnwrap(BatteryMath.percent(current: 0, maxCapacity: 100)), 0, accuracy: 0.001)
    }

    func testPercentZeroMaxIsNil() {
        XCTAssertNil(BatteryMath.percent(current: 50, maxCapacity: 0))
    }

    func testPercentRoundsToWholeNumber() {
        XCTAssertEqual(try XCTUnwrap(BatteryMath.percent(current: 68, maxCapacity: 100)), 68, accuracy: 0.001)
    }

    func testTierHighAboveFifty() {
        XCTAssertEqual(BatteryMath.tier(percent: 71), .high)
        XCTAssertEqual(BatteryMath.tier(percent: 50.001), .high)
    }

    func testTierMediumAtFifty() {
        XCTAssertEqual(BatteryMath.tier(percent: 50), .medium)
    }

    func testTierMediumAboveTwenty() {
        XCTAssertEqual(BatteryMath.tier(percent: 35), .medium)
        XCTAssertEqual(BatteryMath.tier(percent: 20.001), .medium)
    }

    func testTierLowBelowTwenty() {
        XCTAssertEqual(BatteryMath.tier(percent: 19.999), .low)
        XCTAssertEqual(BatteryMath.tier(percent: 5), .low)
    }

    func testTimeMinutesFromSeconds() {
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 324), 5)
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 3500), 58)
        XCTAssertEqual(BatteryMath.timeMinutes(seconds: 3600), 60)
    }

    func testTimeMinutesZeroIsNil() {
        XCTAssertNil(BatteryMath.timeMinutes(seconds: 0))
    }
}
