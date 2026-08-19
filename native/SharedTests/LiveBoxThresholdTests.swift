import XCTest

// Per-metric threshold pairs for LiveBox threshold coloring: CPU / MEM / DISK
// each resolve from their own warn/alarm pair (plan_20260819.md Phase 2).

final class LiveBoxThresholdTierTests: XCTestCase {
    func testEachMetricResolvesFromItsOwnPair() {
        var s = LiveBoxSettings()
        s.cpuWarnThreshold = 30
        s.cpuAlarmThreshold = 60
        s.memWarnThreshold = 40
        s.memAlarmThreshold = 70
        s.diskWarnThreshold = 50
        s.diskAlarmThreshold = 80
        // Same value, different metric → different tier from its own pair.
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .cpu, value: 35, settings: s), .warn)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .mem, value: 35, settings: s), .normal)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .disk, value: 35, settings: s), .normal)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .mem, value: 75, settings: s), .alarm)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .disk, value: 75, settings: s), .warn)
    }

    func testBoundaryPerMetric() {
        var s = LiveBoxSettings()
        s.cpuWarnThreshold = 80
        s.cpuAlarmThreshold = 90
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .cpu, value: 79, settings: s), .normal)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .cpu, value: 80, settings: s), .warn)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .cpu, value: 90, settings: s), .alarm)

        s.memWarnThreshold = 70
        s.memAlarmThreshold = 85
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .mem, value: 69, settings: s), .normal)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .mem, value: 70, settings: s), .warn)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .mem, value: 85, settings: s), .alarm)
    }

    func testAlarmWinsWhenWarnAboveAlarm() {
        var s = LiveBoxSettings()
        s.diskWarnThreshold = 90
        s.diskAlarmThreshold = 80
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .disk, value: 85, settings: s), .alarm)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .disk, value: 75, settings: s), .normal)
    }

    func testDefaultSettingsMatchLegacySinglePair() {
        // Defaults are 80/90 for every metric — same behavior as the old shared pair.
        let s = LiveBoxSettings()
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .cpu, value: 85, settings: s), .warn)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .mem, value: 95, settings: s), .alarm)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .disk, value: 79, settings: s), .normal)
    }
}