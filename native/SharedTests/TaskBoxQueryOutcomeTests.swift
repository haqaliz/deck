import XCTest

/// A rejected TaskBox condition is its own outcome. It is neither
/// "check org, project + PAT" (the credential is fine) nor "unexpected
/// response" (the server said exactly what it didn't like).
final class TaskBoxQueryOutcomeTests: XCTestCase {
    func testALocallyRejectedConditionIsQueryRejected() {
        XCTAssertEqual(
            FetchClassifier.outcome(for: AzureDevOpsError.invalidQuery(.unbalancedParentheses)),
            .queryRejected
        )
    }

    func testAServerRejectedConditionIsQueryRejected() {
        XCTAssertEqual(
            FetchClassifier.outcome(for: AzureDevOpsError.queryRejected("TF51005: …")),
            .queryRejected
        )
        XCTAssertEqual(FetchClassifier.outcome(for: AzureDevOpsError.queryRejected(nil)), .queryRejected)
    }

    /// Only the WIQL call turns a 400 into a rejected query. Anywhere else a
    /// 400 keeps its old meaning.
    func testA400ElsewhereIsStillABadResponse() {
        XCTAssertEqual(FetchClassifier.outcome(for: AzureDevOpsError.serverError(400)), .badResponse)
    }

    func testTaskBoxSaysCheckTheQuery() {
        XCTAssertEqual(FetchStatusCopy.line(source: .taskbox, outcome: .queryRejected), "Check the query")
        let hint = FetchStatusCopy.hint(source: .taskbox, outcome: .queryRejected)
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint?.contains("Test") ?? false, "the hint points at the Test button")
    }

    /// No other source has a query, so none can say this.
    func testOtherSourcesAreSilent() {
        for source in FetchSource.allCases where source != .taskbox {
            XCTAssertNil(FetchStatusCopy.line(source: source, outcome: .queryRejected), source.rawValue)
            XCTAssertNil(FetchStatusCopy.hint(source: source, outcome: .queryRejected), source.rawValue)
        }
    }

    /// Several projects failing the same way collapse into one note.
    func testTheProjectNoteNamesTheQuery() {
        let note = AzureProjectNote.compose(
            failures: [.init(project: "Ops", outcome: .queryRejected)], source: .taskbox
        )
        XCTAssertEqual(note, "Ops: check the query")
    }

    /// An older build reading a status this build wrote shows no chip rather
    /// than a wrong one.
    func testTheRawValueRoundTrips() throws {
        let status = FetchStatus(source: .taskbox, outcome: .queryRejected, attemptedAt: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(FetchStatus.self, from: JSONEncoder().encode(status))
        XCTAssertEqual(decoded.outcome, .queryRejected)
    }
}

/// What the WIQL call does with each answer. Pure, so the 400 path is pinned
/// without a network.
final class WiqlResponseTests: XCTestCase {
    func testA200IsParsed() throws {
        let body = Data(#"{"workItems":[{"id":3},{"id":1}]}"#.utf8)
        XCTAssertEqual(try WiqlResponse.interpret(status: 200, body: body).ids, [3, 1])
    }

    func testA200ThatIsNotAWorkItemListIsAnInvalidPayload() {
        let body = Data(#"{"workItemRelations":[]}"#.utf8)
        XCTAssertThrowsError(try WiqlResponse.interpret(status: 200, body: body)) {
            XCTAssertEqual($0 as? AzureDevOpsError, .invalidPayload)
        }
    }

    func testA400IsARejectedQueryCarryingTheServersReason() {
        let body = Data(#"{"message":"TF51005: The query references a field that does not exist."}"#.utf8)
        XCTAssertThrowsError(try WiqlResponse.interpret(status: 400, body: body)) {
            XCTAssertEqual(
                $0 as? AzureDevOpsError,
                .queryRejected("TF51005: The query references a field that does not exist.")
            )
        }
    }

    func testA400WithoutAReadableBodyIsStillARejectedQuery() {
        XCTAssertThrowsError(try WiqlResponse.interpret(status: 400, body: Data())) {
            XCTAssertEqual($0 as? AzureDevOpsError, .queryRejected(nil))
        }
    }

    /// The bad-PAT sign-in page and every other status keep their meaning.
    func testOtherStatusesAreServerErrors() {
        for status in [203, 401, 404, 500] {
            XCTAssertThrowsError(try WiqlResponse.interpret(status: status, body: Data())) {
                XCTAssertEqual($0 as? AzureDevOpsError, .serverError(status))
            }
        }
    }

    /// The URL carries `$top`, so the cap is applied by the server.
    func testTheURLAsksForOneMoreThanTheCap() throws {
        let target = try AzureTarget.normalise(organization: "org", project: "My Project")
        XCTAssertEqual(
            WiqlResponse.url(target: target)?.absoluteString,
            "https://dev.azure.com/org/My%20Project/_apis/wit/wiql?api-version=7.1&$top=201"
        )
    }
}

/// The settings Test result line. The one place a valid-but-wrong condition
/// (probe P4: a misspelt state, 200 with zero rows) can be caught, so a zero is
/// printed plainly rather than smoothed over.
final class WiqlTestSummaryTests: XCTestCase {
    private func matched(_ project: String, _ count: Int, capped: Bool = false) -> WiqlTestResult {
        WiqlTestResult(project: project, outcome: .matched(count: count, capped: capped))
    }

    func testOneProjectCountsMatches() {
        XCTAssertEqual(WiqlTestSummary.line([matched("P", 11)]).text, "11 matches")
        XCTAssertEqual(WiqlTestSummary.line([matched("P", 1)]).text, "1 match")
        XCTAssertEqual(WiqlTestSummary.line([matched("P", 200, capped: true)]).text, "200+ matches")
    }

    func testZeroIsSaidPlainlyButIsNotAProblem() {
        let line = WiqlTestSummary.line([matched("P", 0)])
        XCTAssertEqual(line.text, "0 matches")
        XCTAssertFalse(line.isProblem)
    }

    func testSeveralProjectsAreNamed() {
        XCTAssertEqual(
            WiqlTestSummary.line([matched("Manifold", 11), matched("Ops", 0), matched("Big", 200, capped: true)]).text,
            "Manifold 11 · Ops 0 · Big 200+"
        )
    }

    func testTheServersReasonIsShownVerbatim() {
        let line = WiqlTestSummary.line([
            WiqlTestResult(project: "P", outcome: .rejected("TF51005: The query references a field that does not exist.")),
        ])
        XCTAssertEqual(line.text, "TF51005: The query references a field that does not exist.")
        XCTAssertTrue(line.isProblem)
    }

    func testARejectionWithoutAReasonStillSaysSo() {
        let line = WiqlTestSummary.line([WiqlTestResult(project: "P", outcome: .rejected(nil))])
        XCTAssertEqual(line.text, "Azure DevOps rejected the query.")
    }

    /// A field that exists in one project's process and not another's fails
    /// in only some of them — say which.
    func testARejectionAmongSeveralNamesItsProjectAndWins() {
        let line = WiqlTestSummary.line([
            matched("Manifold", 11),
            WiqlTestResult(project: "Ops", outcome: .rejected("TF51005: nope")),
        ])
        XCTAssertEqual(line.text, "Ops: TF51005: nope")
        XCTAssertTrue(line.isProblem)
    }

    func testAnyOtherFailureUsesTheSettingsHint() {
        let line = WiqlTestSummary.line([WiqlTestResult(project: "P", outcome: .failed(.unreachable))])
        XCTAssertEqual(line.text, FetchStatusCopy.hint(source: .taskbox, outcome: .unreachable))
        XCTAssertTrue(line.isProblem)
    }

    func testNoResultsSaysNothingWasTested() {
        XCTAssertEqual(WiqlTestSummary.line([]).text, "No projects to test.")
    }

    /// Classifying an error into a result reuses the loader's own mapping.
    func testErrorsClassifyIntoResults() {
        XCTAssertEqual(WiqlTestResult.Outcome(error: AzureDevOpsError.queryRejected("x")), .rejected("x"))
        XCTAssertEqual(WiqlTestResult.Outcome(error: AzureDevOpsError.serverError(401)), .failed(.authOrTarget))
        XCTAssertEqual(WiqlTestResult.Outcome(error: AzureDevOpsError.transport("offline")), .failed(.unreachable))
    }
}
