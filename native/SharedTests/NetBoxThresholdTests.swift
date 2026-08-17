import XCTest

// Fresh suite: warn/alarm tier for network rates (NetBox threshold coloring,
// ROADMAP.md:82). Written from behavior — the helper ships before the view
// code. Reuses ThresholdTier's rules; adds the "no reading" guard for
// non-positive rates and decimal MB/s thresholds (×1,000,000, matching
// NetBoxFormatters).

final class NetBoxThresholdTierTests: XCTestCase {
    func testZeroRateIsNormalForAnyThresholds() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 0, warnMBps: 50, alarmMBps: 100), .normal)
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 0, warnMBps: 0, alarmMBps: 0), .normal)
    }

    func testNegativeRateIsNormalForAnyThresholds() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: -100, warnMBps: 50, alarmMBps: 100), .normal)
    }

    func testZeroThresholdsFloorToOneMBps() {
        // A hand-edited 0 threshold behaves as 1 MB/s: tiny rates stay
        // normal, but 1 MB/s or more still tints (floored, not ignored).
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 1, warnMBps: 0, alarmMBps: 0), .normal)
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 999_999, warnMBps: 0, alarmMBps: 0), .normal)
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 1_000_000, warnMBps: 0, alarmMBps: 0), .alarm)
    }

    func testBelowWarnIsNormal() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 49_999_999, warnMBps: 50, alarmMBps: 100), .normal)
    }

    func testAtWarnIsWarn() {
        // 50 MB/s = exactly 50,000,000 B/s in decimal units.
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 50_000_000, warnMBps: 50, alarmMBps: 100), .warn)
    }

    func testBetweenWarnAndAlarmIsWarn() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 75_000_000, warnMBps: 50, alarmMBps: 100), .warn)
    }

    func testAtAlarmIsAlarm() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 100_000_000, warnMBps: 50, alarmMBps: 100), .alarm)
    }

    func testAboveAlarmIsAlarm() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 250_000_000, warnMBps: 50, alarmMBps: 100), .alarm)
    }

    func testAlarmWinsWhenWarnIsAboveAlarm() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 85_000_000, warnMBps: 90, alarmMBps: 80), .alarm)
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 75_000_000, warnMBps: 90, alarmMBps: 80), .normal)
    }

    func testKilobyteScaleRatesStayNormalUnderLowThresholds() {
        XCTAssertEqual(NetBoxThresholdTier.tier(rate: 512_000, warnMBps: 50, alarmMBps: 100), .normal)
    }
}
