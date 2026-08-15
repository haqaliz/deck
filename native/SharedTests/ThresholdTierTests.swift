import XCTest

// Fresh suite: threshold tier logic for LiveBox threshold coloring
// (ROADMAP.md:69). Written from behavior — the helper ships before the view
// code so NetBox threshold coloring (ROADMAP.md:81) reuses the same rules.

final class ThresholdTierTests: XCTestCase {
    func testBelowWarnIsNormal() {
        XCTAssertEqual(ThresholdTier.tier(value: 79, warn: 80, alarm: 90), .normal)
    }

    func testAtWarnIsWarn() {
        XCTAssertEqual(ThresholdTier.tier(value: 80, warn: 80, alarm: 90), .warn)
    }

    func testBetweenWarnAndAlarmIsWarn() {
        XCTAssertEqual(ThresholdTier.tier(value: 85, warn: 80, alarm: 90), .warn)
    }

    func testAtAlarmIsAlarm() {
        XCTAssertEqual(ThresholdTier.tier(value: 90, warn: 80, alarm: 90), .alarm)
    }

    func testAboveAlarmIsAlarm() {
        XCTAssertEqual(ThresholdTier.tier(value: 97, warn: 80, alarm: 90), .alarm)
    }

    func testAlarmWinsWhenWarnIsAboveAlarm() {
        // Precedence rule (prd.md §2): alarm wins if warn > alarm.
        XCTAssertEqual(ThresholdTier.tier(value: 85, warn: 90, alarm: 80), .alarm)
        XCTAssertEqual(ThresholdTier.tier(value: 75, warn: 90, alarm: 80), .normal)
    }

    func testZeroValueIsNormal() {
        XCTAssertEqual(ThresholdTier.tier(value: 0, warn: 80, alarm: 90), .normal)
    }

    func testFullValueIsAlarm() {
        XCTAssertEqual(ThresholdTier.tier(value: 100, warn: 80, alarm: 90), .alarm)
    }

    func testWarnColorIsAmber() {
        XCTAssertEqual(ThresholdTier.warnColor.red, 1.0)
        XCTAssertGreaterThan(ThresholdTier.warnColor.green, 0.6)
        XCTAssertLessThan(ThresholdTier.warnColor.blue, 0.3)
    }

    func testAlarmColorIsRed() {
        XCTAssertEqual(ThresholdTier.alarmColor.red, 1.0)
        XCTAssertLessThan(ThresholdTier.alarmColor.green, 0.4)
        XCTAssertLessThan(ThresholdTier.alarmColor.blue, 0.4)
    }
}
