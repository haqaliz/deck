import XCTest

final class ProcessRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNilLastSampleAlwaysSamples() {
        XCTAssertTrue(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: nil, configuredInterval: 15, now: now
        ))
    }

    func testExactBoundarySamples() {
        let last = now.addingTimeInterval(-15)
        XCTAssertTrue(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: last, configuredInterval: 15, now: now
        ))
    }

    func testOneSecondUnderSkips() {
        let last = now.addingTimeInterval(-14)
        XCTAssertFalse(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: last, configuredInterval: 15, now: now
        ))
    }

    func testFarUnderSkips() {
        let last = now.addingTimeInterval(-1)
        XCTAssertFalse(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: last, configuredInterval: 60, now: now
        ))
    }

    func testFiveSecondIntervalBoundary() {
        let last = now.addingTimeInterval(-5)
        XCTAssertTrue(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: last, configuredInterval: 5, now: now
        ))
        XCTAssertFalse(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: now.addingTimeInterval(-4.9), configuredInterval: 5, now: now
        ))
    }

    func testSixtySecondInterval() {
        let last = now.addingTimeInterval(-59)
        XCTAssertFalse(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: last, configuredInterval: 60, now: now
        ))
        XCTAssertTrue(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: now.addingTimeInterval(-60), configuredInterval: 60, now: now
        ))
    }

    func testFutureDatedLastSampleSkips() {
        let last = now.addingTimeInterval(10)
        XCTAssertFalse(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: last, configuredInterval: 5, now: now
        ))
    }

    func testZeroIntervalAlwaysSamples() {
        XCTAssertTrue(ProcessRefreshPolicy.shouldSample(
            lastSampleAt: now, configuredInterval: 0, now: now
        ))
    }
}

final class AgentReconcilePolicyTests: XCTestCase {
    func testIntentOnAndEnabledDoesNothing() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: true, state: .enabled),
            []
        )
    }

    func testIntentOnAndRequiresApprovalDoesNothing() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: true, state: .requiresApproval),
            []
        )
    }

    func testIntentOnAndNotFoundRegisters() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: true, state: .notFound),
            [.register]
        )
    }

    func testIntentOnAndNotRegisteredAdoptsOff() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: true, state: .notRegistered),
            [.adoptIntent(false)]
        )
    }

    func testIntentOffAndEnabledAdoptsOn() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: false, state: .enabled),
            [.adoptIntent(true)]
        )
    }

    func testIntentOffAndNotRegisteredDoesNothing() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: false, state: .notRegistered),
            []
        )
    }

    func testIntentOffAndNotFoundDoesNothing() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: false, state: .notFound),
            []
        )
    }

    func testIntentOffAndRequiresApprovalDoesNothing() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: false, state: .requiresApproval),
            []
        )
    }
}