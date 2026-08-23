import XCTest

// PRBox is the first widget whose data comes from two sources at once, so it
// is the first that can be half-broken. The face has room for one line, and
// the counts are a union — a REVIEW count of 2 while GitHub is down is not
// wrong, it is partial, and only this line can say so. Hence: name the
// provider that failed.

final class PRFetchChipTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)
    private var recent: Date { now.addingTimeInterval(-60) }

    private func status(_ outcome: FetchOutcome, _ source: FetchSource) -> FetchStatus {
        FetchStatus(source: source, outcome: outcome, attemptedAt: recent)
    }

    private func chip(
        github: FetchStatus? = nil,
        azure: FetchStatus? = nil,
        githubEnabled: Bool = true,
        azureEnabled: Bool = true,
        dataWrittenAt: Date? = nil
    ) -> String? {
        PRFetchChip.text(
            github: github,
            azure: azure,
            githubEnabled: githubEnabled,
            azureEnabled: azureEnabled,
            dataWrittenAt: dataWrittenAt ?? recent,
            now: now
        )
    }

    // MARK: - Nothing to say

    func testBothProvidersHealthyIsSilent() {
        XCTAssertNil(chip(github: status(.ok, .prboxGitHub), azure: status(.ok, .prboxAzure)))
    }

    func testOnlyEnabledProviderHealthyIsSilent() {
        XCTAssertNil(chip(github: status(.ok, .prboxGitHub), azureEnabled: false))
    }

    /// A disabled provider's stale failure must not speak. Someone who turned
    /// GitHub off after a bad token should not keep reading about it.
    func testDisabledProviderFailureIsIgnored() {
        XCTAssertNil(
            chip(
                github: status(.authOrTarget, .prboxGitHub),
                azure: status(.ok, .prboxAzure),
                githubEnabled: false
            )
        )
    }

    // MARK: - Not configured

    func testNeitherProviderEnabledSaysNotConfigured() {
        XCTAssertEqual(
            chip(githubEnabled: false, azureEnabled: false, dataWrittenAt: nil),
            "Not configured"
        )
    }

    // MARK: - One provider down — name it

    /// The counts silently exclude the failed provider's pull requests, so the
    /// line has to say which half is missing.
    func testGitHubFailureIsNamed() {
        let line = chip(github: status(.authOrTarget, .prboxGitHub), azure: status(.ok, .prboxAzure))
        XCTAssertEqual(line, "GitHub: check token")
    }

    func testAzureFailureIsNamed() {
        let line = chip(github: status(.ok, .prboxGitHub), azure: status(.unreachable, .prboxAzure))
        XCTAssertEqual(line, "Azure: can't reach Azure DevOps")
    }

    /// An enabled provider that has never reported is not yet a failure — the
    /// other provider's data still renders without a scary line.
    func testEnabledProviderWithNoStatusYetIsSilent() {
        XCTAssertNil(chip(github: nil, azure: status(.ok, .prboxAzure)))
    }

    // MARK: - Both down

    func testBothFailingWithTheSameReasonReadsAsOneLine() {
        let line = chip(
            github: status(.unreachable, .prboxGitHub),
            azure: status(.unreachable, .prboxAzure)
        )
        XCTAssertEqual(line, "GitHub + Azure: offline")
    }

    /// Two different reasons cannot both fit, so the line names one and admits
    /// there is another rather than pretending they share a cause.
    func testBothFailingDifferentlyNamesOneAndCountsTheOther() {
        let line = chip(
            github: status(.authOrTarget, .prboxGitHub),
            azure: status(.unreachable, .prboxAzure)
        )
        XCTAssertEqual(line, "GitHub: check token +1 more")
    }

    // MARK: - Silent agent wins over everything

    /// If the agent stopped running, every per-provider reason is stale by
    /// definition and pointing at a token would send the user to the wrong
    /// place.
    func testSilentAgentOutranksAProviderFailure() {
        let old = now.addingTimeInterval(-FetchChip.deadAgentThreshold - 60)
        let line = PRFetchChip.text(
            github: FetchStatus(source: .prboxGitHub, outcome: .authOrTarget, attemptedAt: old),
            azure: nil,
            githubEnabled: true,
            azureEnabled: false,
            dataWrittenAt: old,
            now: now
        )
        XCTAssertEqual(line, "Agent hasn't run")
    }

    /// Calls the API directly: the `chip` helper defaults `dataWrittenAt`, so
    /// it cannot express the "no snapshot at all" case this test is about.
    func testNoDataAndNoStatusWithAProviderEnabledSaysAgentHasntRun() {
        let line = PRFetchChip.text(
            github: nil,
            azure: nil,
            githubEnabled: true,
            azureEnabled: false,
            dataWrittenAt: nil,
            now: now
        )
        XCTAssertEqual(line, "Agent hasn't run")
    }
}

// MARK: - Copy totality

final class PRBoxFetchCopyTests: XCTestCase {
    /// Both switches over `FetchSource` in `FetchStatusCopy` are exhaustive, so
    /// a new source that compiles could still ship an empty reason. Every
    /// failing outcome must produce a line and a settings sentence.
    func testEveryFailureOutcomeHasCopyForBothNewSources() {
        let failures: [FetchOutcome] = [.notConfigured, .authOrTarget, .unreachable, .badResponse]
        for source in [FetchSource.prboxGitHub, .prboxAzure] {
            for outcome in failures {
                XCTAssertNotNil(
                    FetchStatusCopy.line(source: source, outcome: outcome),
                    "no line for \(source.rawValue)/\(outcome.rawValue)"
                )
                XCTAssertNotNil(
                    FetchStatusCopy.hint(source: source, outcome: outcome),
                    "no hint for \(source.rawValue)/\(outcome.rawValue)"
                )
            }
        }
    }

    func testOkProducesNoCopy() {
        for source in [FetchSource.prboxGitHub, .prboxAzure] {
            XCTAssertNil(FetchStatusCopy.line(source: source, outcome: .ok))
            XCTAssertNil(FetchStatusCopy.hint(source: source, outcome: .ok))
        }
    }

    /// The Azure hint deliberately does not name a PAT scope: the probe ran
    /// with a token of unknown scope, so shipping "Code (Read) is enough" as
    /// instruction would be untested advice a user cannot debug.
    func testAzureHintDoesNotClaimAnUnverifiedScope() {
        let hint = FetchStatusCopy.hint(source: .prboxAzure, outcome: .notConfigured) ?? ""
        XCTAssertFalse(hint.contains("Code (Read)"))
    }
}
