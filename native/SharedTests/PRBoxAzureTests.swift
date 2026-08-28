import XCTest

// Azure DevOps half of PRBox.
//
// The important test in this file is
// `testMissingIdentityIsAnErrorNotAnUnfilteredQuery`. The Git PR API has no
// `@Me` macro, and it does not reject an identity it cannot parse: measured
// against a live organization, `searchCriteria.creatorId=@me` returned HTTP 200
// with *every active pull request in the project* — 6 with no criteria, the
// same 6 with `@me`, and 0 for a well-formed but unknown GUID. So an
// unresolved identity must fail the fetch. Falling back to an unfiltered query
// would render the whole team's pull requests and look perfectly healthy doing
// it.
//
// Fixtures: `azure_connectiondata.json` and `azure_prs.json` are trimmed live
// responses; `azure_prs_votes.json` is hand-built on the same shape to cover
// the vote matrix.

private let me = "5d48bc9c-1cf3-419c-b2c5-43c4d36875d2"

final class AzureConnectionDataParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "missing fixture \(name).json"))
    }

    func testReadsAuthenticatedUserID() throws {
        XCTAssertEqual(ConnectionDataParser.parse(try fixture("azure_connectiondata")), me)
    }

    func testMissingUserReturnsNil() {
        XCTAssertNil(ConnectionDataParser.parse(Data("{}".utf8)))
    }

    func testMissingIDReturnsNil() {
        XCTAssertNil(ConnectionDataParser.parse(Data(#"{"authenticatedUser":{"displayName":"x"}}"#.utf8)))
    }

    /// An empty string would be interpolated into the query as a blank
    /// criterion, which is the unfiltered case again.
    func testEmptyIDReturnsNil() {
        XCTAssertNil(ConnectionDataParser.parse(Data(#"{"authenticatedUser":{"id":""}}"#.utf8)))
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ConnectionDataParser.parse(Data("not json".utf8)))
    }
}

// MARK: - The identity guard

final class AzureIdentityGuardTests: XCTestCase {
    /// The whole reason this widget resolves a GUID before it queries.
    ///
    /// Azure DevOps answers an unparseable `creatorId` with 200 and every
    /// active pull request in the project (measured: 6 unfiltered, 6 with
    /// `@me`, 0 with an unknown GUID). There is therefore no safe fallback —
    /// an identity that cannot be resolved has to fail the fetch, so the face
    /// says "check the PAT" instead of quietly listing the whole team's work.
    func testMissingIdentityIsAnErrorNotAnUnfilteredQuery() {
        XCTAssertThrowsError(try HostAzurePRLoader.requireIdentity(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? AzureDevOpsError, .invalidTarget)
        }
    }

    func testResolvedIdentityIsReturned() throws {
        let json = #"{"authenticatedUser":{"id":"abc"}}"#
        XCTAssertEqual(try HostAzurePRLoader.requireIdentity(Data(json.utf8)), "abc")
    }
}

final class AzurePRParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "missing fixture \(name).json"))
    }

    private let target = try! AzureTarget.normalise(organization: "ForesightAnalytics", project: "ForesightManifold")

    // MARK: - Shape

    func testParsesLivePayload() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs"), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(items.count, 5)
    }

    func testReadsRepoNameAndNumber() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs"), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(items.first?.number, 4475)
        XCTAssertEqual(items.first?.repo, "manifold-validation-swa")
    }

    func testDraftFlagIsHonored() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs"), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(items.filter(\.isDraft).map(\.number), [2509])
    }

    /// Azure stamps seven fractional digits ("2026-08-14T09:45:36.1569896Z"),
    /// which a plain ISO8601 formatter rejects outright — `AzureDate` already
    /// handles all three of its date spellings for TaskBox. The fraction is
    /// kept, not truncated, so the comparison allows for it: sub-second
    /// precision is irrelevant to a column that renders "10d".
    func testParsesFractionalSecondDates() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs"), role: .authored, me: me, target: target)
        )
        let parsed = try XCTUnwrap(items.first(where: { $0.number == 4397 })?.createdAt)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-14T09:45:36Z"))
        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    /// The payload carries no browsable URL at all — `url` is the REST
    /// endpoint and `repository.webUrl` is absent — so the link is built.
    func testBuildsWebURL() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs"), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(
            items.first(where: { $0.number == 4396 })?.url,
            "https://dev.azure.com/ForesightAnalytics/ForesightManifold/_git/manifold/pullrequest/4396"
        )
    }

    func testIDIsProviderAndProjectQualified() throws {
        // The project belongs in the id because PR numbers are per repo and a
        // repo name is only unique within its project — see
        // AzureMultiProjectTests for the collision this prevents.
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs"), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(items.first?.id, "azureDevOps:ForesightManifold/manifold-validation-swa#4475")
    }

    // MARK: - The vote filter

    /// `reviewerId` returns every PR you are a reviewer on, including ones you
    /// have already voted on, whereas GitHub drops a PR from
    /// `review-requested` the moment you review it. Without this filter the two
    /// halves of one list would mean two different things and the REVIEW count
    /// would overstate the work.
    func testReviewingKeepsOnlyUnvotedRows() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs_votes"), role: .reviewing, me: me, target: target)
        )
        XCTAssertEqual(items.map(\.number), [102])
    }

    /// The authored query is not a review queue — a vote of yours on your own
    /// PR must not remove it.
    func testAuthoredIgnoresVotes() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs_votes"), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(items.count, 4)
    }

    /// Only *your* vote counts. A colleague's approval leaves the PR in your
    /// queue.
    func testAnotherReviewersVoteIsIrrelevant() throws {
        let items = try XCTUnwrap(
            AzurePRParser.parse(try fixture("azure_prs_votes"), role: .reviewing, me: "someone-else", target: target)
        )
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Malformed input

    func testNonObjectPayloadReturnsNil() {
        XCTAssertNil(AzurePRParser.parse(Data("[]".utf8), role: .authored, me: me, target: target))
    }

    func testMissingValueKeyReturnsNil() {
        XCTAssertNil(AzurePRParser.parse(Data(#"{"count":0}"#.utf8), role: .authored, me: me, target: target))
    }

    func testEmptyValueIsEmptyNotNil() {
        XCTAssertEqual(
            AzurePRParser.parse(Data(#"{"count":0,"value":[]}"#.utf8), role: .authored, me: me, target: target),
            []
        )
    }

    func testRowMissingRequiredFieldIsSkipped() throws {
        let json = """
        {"count":2,"value":[
          {"pullRequestId":1,"repository":{"name":"r"}},
          {"pullRequestId":2,"title":"good","repository":{"name":"r"},"creationDate":"2026-01-01T00:00:00Z"}
        ]}
        """
        let items = try XCTUnwrap(
            AzurePRParser.parse(Data(json.utf8), role: .authored, me: me, target: target)
        )
        XCTAssertEqual(items.map(\.number), [2])
    }
}

// MARK: - Count capping

final class AzurePRCapTests: XCTestCase {
    private let target = try! AzureTarget.normalise(organization: "org", project: "proj")

    private func payload(rows: Int) -> Data {
        let items = (1...rows).map { n in
            """
            {"pullRequestId":\(n),"title":"PR \(n)","isDraft":false,\
            "creationDate":"2026-01-01T00:00:00Z","repository":{"name":"r"},"reviewers":[]}
            """
        }
        return Data("{\"count\":\(rows),\"value\":[\(items.joined(separator: ","))]}".utf8)
    }

    /// Azure reports no total for a PR query, so a fetch that comes back full
    /// can only promise "at least this many". The header says "100+" rather
    /// than a number the API never gave.
    func testSaturatedFetchIsMarkedCapped() throws {
        let parsed = try XCTUnwrap(
            AzurePRParser.parse(payload(rows: 101), role: .authored, me: "x", target: target)
        )
        XCTAssertTrue(AzurePRCap.isCapped(rowCount: parsed.count, ceiling: 101))
    }

    func testUnsaturatedFetchIsNotCapped() {
        XCTAssertFalse(AzurePRCap.isCapped(rowCount: 6, ceiling: 101))
    }

    func testCountLabelReadsAsAFloorWhenCapped() {
        XCTAssertEqual(PRFormatting.countLabel(100, capped: true), "100+")
    }
}
