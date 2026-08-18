import XCTest

final class SystemMetricsCoreTests: XCTestCase {
    private func ticks(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) -> CpuTicks {
        CpuTicks(user: user, system: system, idle: idle, nice: nice)
    }

    // MARK: - CpuTicks.total

    func testTotalSumsAllFourStates() {
        let ticks = self.ticks(user: 10, system: 20, idle: 30, nice: 40)
        XCTAssertEqual(ticks.total, 100)
    }

    func testTotalOfZeroTicksIsZero() {
        XCTAssertEqual(CpuTicks().total, 0)
    }

    // MARK: - cpuUsagePercent

    func testNilPreviousReturnsZero() {
        let current = self.ticks(user: 10, system: 0, idle: 0, nice: 0)
        XCTAssertEqual(cpuUsagePercent(previous: nil, current: current), 0)
    }

    func testZeroDeltaTotalReturnsZero() {
        let previous = self.ticks(user: 10, system: 20, idle: 30, nice: 40)
        XCTAssertEqual(cpuUsagePercent(previous: previous, current: previous), 0)
    }

    func testKnownDeltaReturnsExpectedPercent() {
        let previous = self.ticks(user: 100, system: 100, idle: 800, nice: 0)
        let current = self.ticks(user: 108, system: 100, idle: 802, nice: 0)
        // +8 busy of +10 total → 80%
        XCTAssertEqual(cpuUsagePercent(previous: previous, current: current), 80, accuracy: 0.001)
    }

    func testAllIdleDeltaReturnsZero() {
        let previous = self.ticks(user: 10, system: 10, idle: 100, nice: 0)
        let current = self.ticks(user: 10, system: 10, idle: 120, nice: 0)
        XCTAssertEqual(cpuUsagePercent(previous: previous, current: current), 0)
    }

    func testAllBusyDeltaReturnsHundred() {
        let previous = self.ticks(user: 100, system: 0, idle: 0, nice: 0)
        let current = self.ticks(user: 110, system: 0, idle: 0, nice: 0)
        XCTAssertEqual(cpuUsagePercent(previous: previous, current: current), 100)
    }

    // MARK: - perCoreUsagePercents

    func testPerCoreReturnsOnePercentPerSharedCore() {
        let previous = [
            self.ticks(user: 100, system: 0, idle: 900, nice: 0),
            self.ticks(user: 200, system: 0, idle: 800, nice: 0),
        ]
        let current = [
            self.ticks(user: 108, system: 0, idle: 902, nice: 0),
            self.ticks(user: 205, system: 0, idle: 805, nice: 0),
        ]
        let result = perCoreUsagePercents(previous: previous, current: current)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 80, accuracy: 0.001)
        XCTAssertEqual(result[1], 50, accuracy: 0.001)
    }

    func testPerCoreZeroDeltaCoreIsZero() {
        let previous = [
            self.ticks(user: 100, system: 0, idle: 900, nice: 0),
            self.ticks(user: 200, system: 0, idle: 800, nice: 0),
        ]
        let current = [
            self.ticks(user: 100, system: 0, idle: 900, nice: 0),
            self.ticks(user: 205, system: 0, idle: 805, nice: 0),
        ]
        let result = perCoreUsagePercents(previous: previous, current: current)
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[1], 50, accuracy: 0.001)
    }

    func testPerCoreShrinkingCoreCountKeepsSharedPrefix() {
        let previous = [
            self.ticks(user: 100, system: 0, idle: 900, nice: 0),
            self.ticks(user: 200, system: 0, idle: 800, nice: 0),
            self.ticks(user: 300, system: 0, idle: 700, nice: 0),
        ]
        let current = [
            self.ticks(user: 108, system: 0, idle: 902, nice: 0),
            self.ticks(user: 205, system: 0, idle: 805, nice: 0),
        ]
        let result = perCoreUsagePercents(previous: previous, current: current)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 80, accuracy: 0.001)
        XCTAssertEqual(result[1], 50, accuracy: 0.001)
    }

    func testPerCoreEmptyInputsReturnsEmpty() {
        XCTAssertEqual(perCoreUsagePercents(previous: [], current: []), [])
    }
}
