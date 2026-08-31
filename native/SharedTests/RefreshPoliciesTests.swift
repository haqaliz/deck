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
    ///
    /// The data witness is held healthy here so this table keeps asserting what
    /// it always asserted: the **process** witness's behaviour, unchanged by a
    /// second witness arriving beside it. The two-witness rules have their own
    /// class below.
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
            processes: lastRefreshAt.map { AgentEvidence.ran(at: $0) } ?? .never,
            data: .ran(at: now),
            registeredAt: registeredAt,
            processRefreshInterval: interval,
            now: now
        )
    }

    /// The process witness's own verdict, for the rules a *combined* verdict
    /// cannot observe: with the data witness healthy beside it, one witness
    /// sitting in its grace window resolves to `.healthy` rather than
    /// `.unknown`. Both are silent — the notice draws on `.down` alone — so the
    /// property these tests protect is asserted twice below: the ladder returns
    /// `.unknown`, and the pair says nothing to the user.
    private func processVerdict(
        lastRefreshAt: Date?,
        registeredAt: Date?,
        interval: Int = 15
    ) -> AgentLivenessPolicy.WitnessVerdict {
        AgentLivenessPolicy.verdict(
            evidence: lastRefreshAt.map { AgentEvidence.ran(at: $0) } ?? .never,
            limit: AgentLivenessPolicy.threshold(processRefreshInterval: interval),
            registeredAt: registeredAt,
            now: now
        )
    }

    /// The verdict this table used to spell as a bare last-refresh date: the
    /// process agent alone, with the data agent healthy.
    private func processAgentDown(_ lastRefresh: Date?) -> AgentLiveness {
        .down(AgentLiveness.Down(
            scope: .processes,
            processes: lastRefresh.map { AgentEvidence.ran(at: $0) } ?? .never,
            data: .ran(at: now)
        ))
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
        let last = now.addingTimeInterval(-604_800)
        XCTAssertEqual(processVerdict(lastRefreshAt: last, registeredAt: nil), .unknown)
        XCTAssertNotEqual(
            resolve(lastRefreshAt: last, registeredAt: nil), .down(
                AgentLiveness.Down(scope: .processes, processes: .ran(at: last), data: .ran(at: now))
            )
        )
    }

    // MARK: Rule 5 — the grace window

    /// A fresh install, and the state the bundle rename puts every user into:
    /// registered seconds ago, first tick not yet due.
    func testNothingWrittenInsideTheGraceWindowIsSilent() {
        let registered = now.addingTimeInterval(-30)
        XCTAssertEqual(processVerdict(lastRefreshAt: nil, registeredAt: registered), .unknown)
        XCTAssertNotEqual(
            resolve(lastRefreshAt: nil, registeredAt: registered), processAgentDown(nil)
        )
    }

    // MARK: Rule 6 — down

    /// Registered long ago, nothing ever written: the agent never ran once.
    func testNothingEverWrittenPastTheGraceWindowIsDown() {
        XCTAssertEqual(
            resolve(lastRefreshAt: nil, registeredAt: now.addingTimeInterval(-600)),
            processAgentDown(nil)
        )
    }

    /// The measured six-hour fault: it ran, then stopped.
    func testStaleRefreshIsDownAndCarriesTheLastRefresh() {
        let last = now.addingTimeInterval(-21_600)
        XCTAssertEqual(
            resolve(lastRefreshAt: last, registeredAt: now.addingTimeInterval(-86_400)),
            processAgentDown(last)
        )
    }

    func testStalenessUsesTheConfiguredInterval() {
        // 200s old: past the 120s floor at interval 15, inside 240s at interval 60.
        let last = now.addingTimeInterval(-200)
        let registered = now.addingTimeInterval(-86_400)
        XCTAssertEqual(
            resolve(lastRefreshAt: last, registeredAt: registered, interval: 15),
            processAgentDown(last)
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
            processAgentDown(last)
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
            processAgentDown(nil)
        )
    }

    func testOneSecondUnderTheGraceThresholdIsSilent() {
        let registered = now.addingTimeInterval(-119)
        XCTAssertEqual(processVerdict(lastRefreshAt: nil, registeredAt: registered), .unknown)
        XCTAssertNotEqual(
            resolve(lastRefreshAt: nil, registeredAt: registered), processAgentDown(nil)
        )
    }
}

/// Two witnesses, and what the notice is allowed to claim from them.
///
/// The process witness (`processes.json`) has existed since v1.30 and proves
/// only that `com.deck.agent.processes` ran. The data witness
/// (`agent-heartbeat.json`) is the 60s agent's own, and without it a dead
/// `com.deck.agent` is invisible: it writes ten snapshots and the host app
/// writes every one of them, so a stale snapshot cannot tell "the agent stopped"
/// from "Deck is closed".
final class AgentLivenessTwoWitnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func resolve(
        processes: AgentEvidence,
        data: AgentEvidence,
        registeredAt: Date? = Date(timeIntervalSince1970: 1_700_000_000 - 86_400),
        interval: Int = 15
    ) -> AgentLiveness {
        AgentLivenessPolicy.resolve(
            intent: true,
            state: .enabled,
            processes: processes,
            data: data,
            registeredAt: registeredAt,
            processRefreshInterval: interval,
            now: now
        )
    }

    private var fresh: AgentEvidence { .ran(at: now.addingTimeInterval(-10)) }
    private var stale: AgentEvidence { .ran(at: now.addingTimeInterval(-21_600)) }

    // MARK: The threshold is the data agent's own

    /// The 60s agent's cadence is fixed in its plist and has nothing to do with
    /// `livebox.processRefreshInterval`. Borrowing the process threshold would
    /// call it down after 120s at the 5s default — two missed ticks — and
    /// flicker on every slow fetch.
    func testDataThresholdIsFourOfTheDataAgentsOwnInterval() {
        XCTAssertEqual(AgentLivenessPolicy.dataAgentInterval, 60)
        XCTAssertEqual(AgentLivenessPolicy.dataThreshold, 240)
    }

    func testTheDataThresholdIgnoresTheProcessInterval() {
        // 200s old: inside 240s either way, whatever the LiveBox setting says.
        let last = AgentEvidence.ran(at: now.addingTimeInterval(-200))
        XCTAssertEqual(resolve(processes: fresh, data: last, interval: 5), .healthy)
        XCTAssertEqual(resolve(processes: fresh, data: last, interval: 60), .healthy)
    }

    func testExactlyAtTheDataThresholdIsDown() {
        let last = AgentEvidence.ran(at: now.addingTimeInterval(-240))
        XCTAssertEqual(
            resolve(processes: fresh, data: last),
            .down(AgentLiveness.Down(scope: .data, processes: fresh, data: last))
        )
    }

    func testOneSecondUnderTheDataThresholdIsHealthy() {
        XCTAssertEqual(
            resolve(processes: fresh, data: .ran(at: now.addingTimeInterval(-239))),
            .healthy
        )
    }

    // MARK: Scope — which half stopped

    /// The blind spot this whole feature exists to close: LiveBox keeps ticking
    /// while eight widgets go stale, and before the heartbeat Deck said nothing.
    func testOnlyTheDataAgentDownIsScopedToTheDataAgent() {
        XCTAssertEqual(
            resolve(processes: fresh, data: stale),
            .down(AgentLiveness.Down(scope: .data, processes: fresh, data: stale))
        )
    }

    func testOnlyTheProcessAgentDownIsScopedToTheProcessAgent() {
        XCTAssertEqual(
            resolve(processes: stale, data: fresh),
            .down(AgentLiveness.Down(scope: .processes, processes: stale, data: fresh))
        )
    }

    /// The measured fault took both down together — one cause, one notice.
    func testBothDownIsScopedToBoth() {
        XCTAssertEqual(
            resolve(processes: stale, data: stale),
            .down(AgentLiveness.Down(scope: .both, processes: stale, data: stale))
        )
    }

    func testBothHealthyIsHealthy() {
        XCTAssertEqual(resolve(processes: fresh, data: fresh), .healthy)
    }

    // MARK: Combining verdicts

    /// A witness inside its grace window is not evidence of a fault, and it is
    /// not evidence of health either. One healthy witness beside it means Deck
    /// has no complaint to make yet.
    func testAnUnknownWitnessBesideAHealthyOneIsHealthy() {
        XCTAssertEqual(
            resolve(processes: fresh, data: .never, registeredAt: now.addingTimeInterval(-30)),
            .healthy
        )
    }

    func testBothUnknownIsUnknown() {
        XCTAssertEqual(
            resolve(
                processes: .never, data: .never, registeredAt: now.addingTimeInterval(-30)
            ),
            .unknown
        )
    }

    /// Down outranks unknown: a witness still inside its grace window cannot
    /// excuse one that is demonstrably stale. Registered 200s ago is past the
    /// process witness's 120s limit and inside the data witness's 240s one, so
    /// this also pins that the two windows really are separate.
    func testDownOutranksUnknown() {
        XCTAssertEqual(
            resolve(processes: stale, data: .never, registeredAt: now.addingTimeInterval(-200)),
            .down(AgentLiveness.Down(scope: .processes, processes: stale, data: .never))
        )
    }

    // MARK: A witness that has never written anything at all

    /// **The release that introduces the heartbeat must not accuse the users who
    /// install it.** An upgraded install has a days-old registration clock and
    /// both agents `.enabled`, and no build before this one ever wrote a
    /// heartbeat — so the grace window is long spent and the data witness is
    /// `.never` on a perfectly healthy machine.
    ///
    /// "The 60s agent has never written once, while the fast agent is
    /// demonstrably alive" is genuinely indistinguishable from "this feature
    /// just shipped", so Deck does not guess. The cost is real and bounded: a
    /// 60s agent that never runs *even once* goes unreported here — and is not
    /// silent, because its eight widgets each say the agent has not run.
    func testAHeartbeatThatNeverExistedIsNotAnAccusationWhileTheProcessAgentIsAlive() {
        XCTAssertEqual(resolve(processes: fresh, data: .never), .healthy)
    }

    /// The gate that stops that rule from weakening the check: with no healthy
    /// witness there is no live agent to make the absence ambiguous, so the
    /// fault is reported. This is the state the bundle rename produces.
    func testBothWitnessesSilentIsStillReported() {
        XCTAssertEqual(
            resolve(processes: .never, data: .never),
            .down(AgentLiveness.Down(scope: .both, processes: .never, data: .never))
        )
    }

    /// And the fault this feature exists for is untouched by that rule: a
    /// heartbeat that *existed* and went stale is evidence, not ambiguity.
    func testAStaleHeartbeatIsReportedEvenWithAHealthyProcessAgent() {
        XCTAssertEqual(
            resolve(processes: fresh, data: stale),
            .down(AgentLiveness.Down(scope: .data, processes: fresh, data: stale))
        )
    }

    /// An unreadable heartbeat is not an absent one: something wrote it, so the
    /// ambiguity that excuses `.never` does not apply.
    func testAnUnreadableHeartbeatIsReportedEvenWithAHealthyProcessAgent() {
        XCTAssertEqual(
            resolve(processes: fresh, data: .unreadable),
            .down(AgentLiveness.Down(scope: .data, processes: fresh, data: .unreadable))
        )
    }

    // MARK: The global guards stay ahead of both witnesses

    /// Keeping these structural is what stops a Login Items veto from raising a
    /// second notice that is wrong about its own cause.
    func testTheVetoStillOwnsItsStateWithTwoWitnessesDown() {
        XCTAssertEqual(
            AgentLivenessPolicy.resolve(
                intent: true,
                state: .requiresApproval,
                processes: stale,
                data: stale,
                registeredAt: now.addingTimeInterval(-86_400),
                processRefreshInterval: 15,
                now: now
            ),
            .unknown
        )
    }

    func testIntentOffIsStillNeverAFault() {
        XCTAssertEqual(
            AgentLivenessPolicy.resolve(
                intent: false,
                state: .enabled,
                processes: stale,
                data: stale,
                registeredAt: now.addingTimeInterval(-86_400),
                processRefreshInterval: 15,
                now: now
            ),
            .unknown
        )
    }

    // MARK: Which evidence the notice reports

    /// With one agent down, the answer is that agent's own evidence — not the
    /// healthy one's, which would report a refresh that says nothing about the
    /// thing that stopped.
    func testAScopedDownReportsItsOwnAgentsEvidence() {
        XCTAssertEqual(
            resolve(processes: fresh, data: stale).downValue?.reported, stale
        )
        XCTAssertEqual(
            resolve(processes: stale, data: fresh).downValue?.reported, stale
        )
    }

    /// Both down: "how long has this been broken" is answered by the last time
    /// *anything* ran, so the more recent timestamp wins.
    func testBothDownReportsTheMoreRecentTimestamp() {
        let older = AgentEvidence.ran(at: now.addingTimeInterval(-86_400))
        let newer = AgentEvidence.ran(at: now.addingTimeInterval(-21_600))
        XCTAssertEqual(resolve(processes: older, data: newer).downValue?.reported, newer)
        XCTAssertEqual(resolve(processes: newer, data: older).downValue?.reported, newer)
    }

    /// A timestamp outranks both non-dates.
    func testATimestampOutranksNoEvidence() {
        XCTAssertEqual(resolve(processes: stale, data: .never).downValue?.reported, stale)
        XCTAssertEqual(resolve(processes: .unreadable, data: stale).downValue?.reported, stale)
    }

    /// `.unreadable` outranks `.never`, because "No refresh has been recorded"
    /// is exactly the false claim the corrupt-vs-absent split exists to remove:
    /// something wrote that file.
    func testUnreadableOutranksNever() {
        XCTAssertEqual(
            resolve(processes: .never, data: .unreadable).downValue?.reported, .unreadable
        )
        XCTAssertEqual(
            resolve(processes: .unreadable, data: .never).downValue?.reported, .unreadable
        )
    }

    func testNeitherEverRanReportsNever() {
        XCTAssertEqual(resolve(processes: .never, data: .never).downValue?.reported, .never)
    }
}

private extension AgentLiveness {
    var downValue: Down? {
        if case .down(let down) = self { return down }
        return nil
    }
}

/// When the grace-period clock is (re)started.
///
/// Two distinct triggers, and collapsing them into one is a real bug: a guard
/// of "write only when nil" looks like the right way to keep the write
/// one-time, and it silently defeats the rename case, where the migrated
/// settings carry a non-nil timestamp from the *old* install.
final class AgentRegistrationClockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Trigger 1 — we just registered

    /// The bundle rename, exactly: ContainerMigration carries a days-old
    /// timestamp into a brand-new container that has no processes.json, and
    /// the new labels register for the first time. If registering does not
    /// restart the clock, every user of the rename release is told background
    /// refresh has stopped, seconds after launch, while it is starting
    /// normally.
    func testRegisteringRestartsAClockCarriedOverByTheRename() {
        let migrated = now.addingTimeInterval(-864_000) // ten days old
        XCTAssertEqual(
            AgentRegistrationClock.stamp(
                stored: migrated, didRegister: true, state: .enabled, now: now
            ),
            now
        )
    }

    func testRegisteringFromNothingStartsTheClock() {
        XCTAssertEqual(
            AgentRegistrationClock.stamp(
                stored: nil, didRegister: true, state: .enabled, now: now
            ),
            now
        )
    }

    // MARK: Trigger 2 — adopting an existing registration

    /// The upgrade path. An install that already had both agents registered
    /// before this check shipped never calls register() again, so without
    /// adoption the field stays nil forever and the check is permanently
    /// silent.
    func testAdoptsAnAlreadyEnabledRegistrationWhenThereIsNoClock() {
        XCTAssertEqual(
            AgentRegistrationClock.stamp(
                stored: nil, didRegister: false, state: .enabled, now: now
            ),
            now
        )
    }

    // MARK: Otherwise — leave it alone

    /// A2: an ordinary launch must not rewrite settings. `.onChange(of:
    /// settings)` saves the file and reloads every widget timeline.
    func testAnOrdinaryLaunchLeavesTheClockUntouched() {
        let existing = now.addingTimeInterval(-7_200)
        XCTAssertEqual(
            AgentRegistrationClock.stamp(
                stored: existing, didRegister: false, state: .enabled, now: now
            ),
            existing
        )
    }

    /// Nothing is registered, so there is no clock to start. Liveness returns
    /// `.unknown` for these states anyway; this only keeps the field honest.
    func testNoRegistrationDoesNotStartAClock() {
        for state in [AgentRegistrationState.notFound, .notRegistered, .requiresApproval] {
            XCTAssertNil(
                AgentRegistrationClock.stamp(
                    stored: nil, didRegister: false, state: state, now: now
                ),
                "\(state) should not start the clock"
            )
        }
    }

    func testAVetoDoesNotDisturbAnExistingClock() {
        let existing = now.addingTimeInterval(-7_200)
        XCTAssertEqual(
            AgentRegistrationClock.stamp(
                stored: existing, didRegister: false, state: .requiresApproval, now: now
            ),
            existing
        )
    }
}

/// Which pre-SMAppService LaunchAgent plists still need clearing.
///
/// The bug this replaces: the cleanup ran unconditionally, and before the
/// bundle rename `DeckBundle.Legacy.agentLabel` **is** `DeckBundle.agentLabel`.
/// So every launch of Deck ran `launchctl bootout` on the two jobs SMAppService
/// was currently running, and nothing put them back — the registration survives
/// a bootout as `.enabled`, so reconciliation correctly did nothing and
/// background refresh stayed dead until a toggle cycle or a login.
final class LegacyAgentCleanupTests: XCTestCase {
    private let agent = "com.deck.agent"
    private let fastAgent = "com.deck.agent.processes"

    /// v1.33+ installs: SMAppService registered the agents from the bundle and
    /// there is no hand-written plist anywhere. Touching launchd here is what
    /// killed them.
    func testCleanInstallIsLeftCompletelyAlone() {
        XCTAssertEqual(
            LegacyAgentCleanup.labelsNeedingCleanup(
                candidates: [agent, fastAgent],
                plistExists: { _ in false }
            ),
            []
        )
    }

    /// Upgraded from <=1.32: the hand-written plist is real and shares the label
    /// with the SMAppService registration, so a stale bootstrap would collide
    /// with the new job. This is the case the cleanup exists for.
    func testUpgradedInstallCleansBothLabels() {
        XCTAssertEqual(
            LegacyAgentCleanup.labelsNeedingCleanup(
                candidates: [agent, fastAgent],
                plistExists: { _ in true }
            ),
            [agent, fastAgent]
        )
    }

    /// A half-migrated install: one plist was already removed by an earlier
    /// launch, the other was not. Only the survivor is touched.
    func testOnlyTheLabelsWithAPlistAreCleaned() {
        XCTAssertEqual(
            LegacyAgentCleanup.labelsNeedingCleanup(
                candidates: [agent, fastAgent],
                plistExists: { $0 == fastAgent }
            ),
            [fastAgent]
        )
    }

    /// Order is the caller's order, so the bootouts stay deterministic.
    func testOrderFollowsTheCandidateList() {
        XCTAssertEqual(
            LegacyAgentCleanup.labelsNeedingCleanup(
                candidates: [fastAgent, agent],
                plistExists: { _ in true }
            ),
            [fastAgent, agent]
        )
    }

    /// The condition is the plist, not "is this label still current". After the
    /// rename the legacy labels differ from the current ones, and a leftover
    /// plist under an old label must still be cleaned.
    func testPostRenameLeftoverIsStillCleaned() {
        XCTAssertEqual(
            LegacyAgentCleanup.labelsNeedingCleanup(
                candidates: ["com.deck.agent"],
                plistExists: { $0 == "com.deck.agent" }
            ),
            ["com.deck.agent"]
        )
    }
}
