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
