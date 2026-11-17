import XCTest

/// The CPU/MEM/DISK/GPU threshold table and the GPU registry parser.
final class LiveBoxGPUTests: XCTestCase {

    func testGPUResolvesFromItsOwnThresholdPair() {
        var s = LiveBoxSettings()
        s.gpuWarnThreshold = 20
        s.gpuAlarmThreshold = 40
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .gpu, value: 19, settings: s), .normal)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .gpu, value: 25, settings: s), .warn)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .gpu, value: 45, settings: s), .alarm)
    }

    func testGPUDoesNotBorrowAnotherMetricsPair() {
        var s = LiveBoxSettings()
        s.cpuWarnThreshold = 10
        s.cpuAlarmThreshold = 20
        s.gpuWarnThreshold = 70
        s.gpuAlarmThreshold = 90
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .gpu, value: 25, settings: s), .normal)
        XCTAssertEqual(LiveBoxThresholdTier.tier(metric: .cpu, value: 25, settings: s), .alarm)
    }

    func testParserReadsDeviceUtilization() {
        XCTAssertEqual(
            GPUStatsParser.utilization(from: ["Device Utilization %": 42]),
            42
        )
    }

    func testParserClampsAndRejectsMissingOrInvalid() {
        XCTAssertEqual(GPUStatsParser.utilization(from: ["Device Utilization %": 150]), 100)
        XCTAssertEqual(GPUStatsParser.utilization(from: ["Device Utilization %": -5]), 0)
        XCTAssertNil(GPUStatsParser.utilization(from: [:]))
        XCTAssertNil(GPUStatsParser.utilization(from: ["Device Utilization %": "42"]))
        XCTAssertNil(GPUStatsParser.utilization(from: ["Device Utilization %": Double.nan]))
    }
}
