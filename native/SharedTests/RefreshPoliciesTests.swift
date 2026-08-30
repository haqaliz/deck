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

    /// A user veto in System Settings → Login Items lands here, not on
    /// `.notRegistered` — the BTM record reads `[enabled, disallowed]`, so
    /// Deck's registration survives the veto. Neither side is rewritten: the
    /// toggle stays as the user set it and the app reports the drift.
    func testIntentOnAndRequiresApprovalReportsBlocked() {
        XCTAssertEqual(
            AgentReconcilePolicy.resolve(intent: true, state: .requiresApproval),
            [.reportBlocked]
        )
    }

    /// The report is the *only* thing that happens — it must not drag the
    /// toggle off with it, because the same state means "registered, not yet
    /// approved" on a fresh install.
    func testRequiresApprovalNeverAdoptsIntent() {
        let actions = AgentReconcilePolicy.resolve(intent: true, state: .requiresApproval)
        XCTAssertFalse(actions.contains { if case .adoptIntent = $0 { return true } else { return false } })
        XCTAssertFalse(actions.contains(.register))
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
// MARK: - Agent liveness
//
// The third way the agents can be down: registered but never loaded by
// launchd. `SMAppService.status` reports `.enabled` throughout, so the only
// evidence is what a live agent leaves behind — `processes.json`, whose single
// writer is the fast agent.

final class AgentLivenessPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Everything healthy unless a test says otherwise; each test varies one
    /// axis so a failure names the rule it broke.
    private func resolve(
        intent: Bool = true,
        state: AgentRegistrationState = .enabled,
        lastRefreshAt: Date?,
        registeredAt: Date?,
        interval: Int = 15
    ) -> AgentLiveness {
        AgentLivenessPolicy.resolve(
            intent: intent,
            state: state,
            lastRefreshAt: lastRefreshAt,
            registeredAt: registeredAt,
            processRefreshInterval: interval,
            now: now
        )
    }

    // MARK: Threshold

    func testThresholdFloorsAtTwoMinutes() {
        XCTAssertEqual(AgentLivenessPolicy.threshold(processRefreshInterval: 5), 120)
        XCTAssertEqual(AgentLivenessPolicy.threshold(processRefreshInterval: 15), 120)
    }

    func testThresholdIsFourIntervalsAboveTheFloor() {
        XCTAssertEqual(AgentLivenessPolicy.threshold(processRefreshInterval: 60), 240)
    }

    // MARK: Rule 1 — not our business

    func testIntentOffIsNeverAFault() {
        XCTAssertEqual(
            resolve(
                intent: false,
                lastRefreshAt: now.addingTimeInterval(-86_400),
                registeredAt: now.addingTimeInterval(-86_400)
            ),
            .unknown
        )
    }

    // MARK: Rule 2 — the other notices own the other states

    /// The Login Items veto has its own notice. Two notices for one condition,
    /// the second wrong about the cause, is the ShipBox C1 mistake.
    func testRequiresApprovalIsOwnedByTheVetoNotice() {
        XCTAssertEqual(
            resolve(
                state: .requiresApproval,
                lastRefreshAt: now.addingTimeInterval(-604_800),
                registeredAt: now.addingTimeInterval(-604_800)
            ),
            .unknown
        )
    }

    func testNotRegisteredIsOwnedByReconcile() {
        XCTAssertEqual(
            resolve(
                state: .notRegistered,
                lastRefreshAt: now.addingTimeInterval(-604_800),
                registeredAt: now.addingTimeInterval(-604_800)
            ),
            .unknown
        )
    }

    func testNotFoundIsOwnedByReconcile() {
        XCTAssertEqual(
            resolve(
                state: .notFound,
                lastRefreshAt: nil,
                registeredAt: now.addingTimeInterval(-604_800)
            ),
            .unknown
        )
    }

    // MARK: Rule 3 — healthy

    func testRecentRefreshIsHealthy() {
        XCTAssertEqual(
            resolve(
                lastRefreshAt: now.addingTimeInterval(-20),
                registeredAt: now.addingTimeInterval(-7_200)
            ),
            .healthy
        )
    }

    /// Rule 3 runs BEFORE the grace window, so a Restart that worked clears the
    /// notice at the next agent tick instead of waiting the grace period out.
    func testHealthyWinsOverTheGraceWindow() {
        XCTAssertEqual(
            resolve(
                lastRefreshAt: now.addingTimeInterval(-5),
                registeredAt: now.addingTimeInterval(-10)
            ),
            .healthy
        )
    }

    /// A snapshot stamped in the future means a bad clock, not a dead agent.
    /// Never accuse macOS of anything on the strength of a clock.
    func testRefreshInTheFutureIsHealthy() {
        XCTAssertEqual(
            resolve(
                lastRefreshAt: now.addingTimeInterval(3_600),
                registeredAt: now.addingTimeInterval(-7_200)
            ),
            .healthy
        )
    }

    // MARK: Rule 4 — no clock to judge against

    func testMissingRegistrationTimestampIsSilent() {
        XCTAssertEqual(
            resolve(
                lastRefreshAt: now.addingTimeInterval(-604_800),
                registeredAt: nil
            ),
            .unknown
        )
    }

    // MARK: Rule 5 — the grace window

    /// A fresh install, and the state the bundle rename puts every user into:
    /// registered seconds ago, first tick not yet due.
    func testNothingWrittenInsideTheGraceWindowIsSilent() {
        XCTAssertEqual(
            resolve(lastRefreshAt: nil, registeredAt: now.addingTimeInterval(-30)),
            .unknown
        )
    }

    // MARK: Rule 6 — down

    /// Registered long ago, nothing ever written: the agent never ran once.
    func testNothingEverWrittenPastTheGraceWindowIsDown() {
        XCTAssertEqual(
            resolve(lastRefreshAt: nil, registeredAt: now.addingTimeInterval(-600)),
            .down(lastRefresh: nil)
        )
    }

    /// The measured six-hour fault: it ran, then stopped.
    func testStaleRefreshIsDownAndCarriesTheLastRefresh() {
        let last = now.addingTimeInterval(-21_600)
        XCTAssertEqual(
            resolve(lastRefreshAt: last, registeredAt: now.addingTimeInterval(-86_400)),
            .down(lastRefresh: last)
        )
    }

    func testStalenessUsesTheConfiguredInterval() {
        // 200s old: past the 120s floor at interval 15, inside 240s at interval 60.
        let last = now.addingTimeInterval(-200)
        let registered = now.addingTimeInterval(-86_400)
        XCTAssertEqual(
            resolve(lastRefreshAt: last, registeredAt: registered, interval: 15),
            .down(lastRefresh: last)
        )
        XCTAssertEqual(
            resolve(lastRefreshAt: last, registeredAt: registered, interval: 60),
            .healthy
        )
    }

    // MARK: Boundaries, pinned so a refactor cannot drift them

    func testExactlyAtTheStalenessThresholdIsDown() {
        let last = now.addingTimeInterval(-120)
        XCTAssertEqual(
            resolve(lastRefreshAt: last, registeredAt: now.addingTimeInterval(-86_400)),
            .down(lastRefresh: last)
        )
    }

    func testOneSecondUnderTheStalenessThresholdIsHealthy() {
        XCTAssertEqual(
            resolve(
                lastRefreshAt: now.addingTimeInterval(-119),
                registeredAt: now.addingTimeInterval(-86_400)
            ),
            .healthy
        )
    }

    func testExactlyAtTheGraceThresholdIsDown() {
        XCTAssertEqual(
            resolve(lastRefreshAt: nil, registeredAt: now.addingTimeInterval(-120)),
            .down(lastRefresh: nil)
        )
    }

    func testOneSecondUnderTheGraceThresholdIsSilent() {
        XCTAssertEqual(
            resolve(lastRefreshAt: nil, registeredAt: now.addingTimeInterval(-119)),
            .unknown
        )
    }
}
