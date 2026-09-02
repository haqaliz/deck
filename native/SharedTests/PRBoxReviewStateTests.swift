import XCTest

// Review state for PRBox rows: GitHub review payloads and Azure reviewer
// votes fold to one coarse, provider-agnostic state per pull request.
//
// `github_pr_reviews.json` is hand-built on the documented
// /repos/{owner}/{repo}/pulls/{n}/reviews shape — the probe could not capture
// a non-empty live payload because the dev token's two granted repos have no
// reviewed PRs (see docs/planning/prbox-review-state/probe.md §3). The same
// approach `azure_prs_votes.json` already takes.

final class GitHubReviewParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "missing fixture \(name).json"))
    }

    func testParsesHandBuiltPayload() throws {
        let reviews = try XCTUnwrap(GitHubReviewParser.parse(try fixture("github_pr_reviews")))
        XCTAssertEqual(reviews.count, 6)
        XCTAssertEqual(reviews.first?.login, "alice")
        XCTAssertEqual(reviews.first?.state, "APPROVED")
        XCTAssertEqual(reviews.first?.submittedAt, ISO8601DateFormatter().date(from: "2026-08-10T09:00:00Z"))
    }

    /// PENDING reviews carry no `submitted_at`; the parser keeps them (the
    /// fold ignores them) rather than guessing a date for something not
    /// submitted.
    func testPendingReviewKeepsNilDate() throws {
        let reviews = try XCTUnwrap(GitHubReviewParser.parse(try fixture("github_pr_reviews")))
        let dave = try XCTUnwrap(reviews.last)
        XCTAssertEqual(dave.login, "dave")
        XCTAssertEqual(dave.state, "PENDING")
        XCTAssertNil(dave.submittedAt)
    }

    func testNonArrayPayloadReturnsNil() {
        XCTAssertNil(GitHubReviewParser.parse(Data("not json".utf8)))
        XCTAssertNil(GitHubReviewParser.parse(Data(#"{"value":[]}"#.utf8)))
    }

    func testEmptyArrayIsEmptyNotNil() {
        XCTAssertEqual(GitHubReviewParser.parse(Data("[]".utf8)), [])
    }

    /// One malformed review must not discard the rest — same rule as every
    /// Deck row parser.
    func testMalformedEntryIsSkipped() throws {
        let json = """
        [
          {"user": {"login": "alice"}, "state": "APPROVED", "submitted_at": "2026-08-10T09:00:00Z"},
          {"user": {"login": "broken"}}
        ]
        """
        let reviews = try XCTUnwrap(GitHubReviewParser.parse(Data(json.utf8)))
        XCTAssertEqual(reviews.map(\.login), ["alice"])
    }
}

// MARK: - The fold

final class GitHubReviewFoldTests: XCTestCase {
    private func review(_ login: String, _ state: String, _ day: Int) -> GitHubReview {
        GitHubReview(
            login: login, state: state,
            submittedAt: ISO8601DateFormatter().date(from: "2026-08-\(String(format: "%02d", day))T09:00:00Z")
        )
    }

    func testNoReviewsIsNoState() {
        XCTAssertNil(PRReviewState.fold([]))
    }

    func testOnlyCommentsIsNoState() {
        XCTAssertNil(PRReviewState.fold([review("a", "COMMENTED", 1)]))
    }

    func testSingleApproval() {
        XCTAssertEqual(PRReviewState.fold([review("a", "APPROVED", 1)]), .approved)
    }

    func testSingleChangesRequested() {
        XCTAssertEqual(PRReviewState.fold([review("a", "CHANGES_REQUESTED", 1)]), .changesRequested)
    }

    /// GitHub's own precedence: a changes-requested review outranks an
    /// approval when they come from different reviewers.
    func testChangesRequestedOutranksApprovalAcrossReviewers() {
        let reviews = [review("a", "APPROVED", 1), review("b", "CHANGES_REQUESTED", 2)]
        XCTAssertEqual(PRReviewState.fold(reviews), .changesRequested)
    }

    func testLatestReviewPerReviewerWins() {
        XCTAssertEqual(PRReviewState.fold([review("a", "APPROVED", 1), review("a", "CHANGES_REQUESTED", 2)]), .changesRequested)
        XCTAssertEqual(PRReviewState.fold([review("a", "CHANGES_REQUESTED", 1), review("a", "APPROVED", 2)]), .approved)
    }

    /// Commenting after approving does not revoke the approval — GitHub's
    /// decision box keeps showing the approval.
    func testCommentDoesNotSupersedeAnApproval() {
        XCTAssertEqual(PRReviewState.fold([review("a", "APPROVED", 1), review("a", "COMMENTED", 2)]), .approved)
    }

    /// Dismissing a review removes it from the decision: an approval that was
    /// later dismissed is not an approval.
    func testDismissalSupersedesAnApproval() {
        XCTAssertNil(PRReviewState.fold([review("a", "APPROVED", 1), review("a", "DISMISSED", 2)]))
    }

    func testDismissalSupersedesChangesRequested() {
        XCTAssertNil(PRReviewState.fold([review("a", "CHANGES_REQUESTED", 1), review("a", "DISMISSED", 2)]))
    }

    func testPendingIsIgnoredEntirely() {
        XCTAssertNil(PRReviewState.fold([GitHubReview(login: "a", state: "PENDING", submittedAt: nil)]))
        XCTAssertEqual(
            PRReviewState.fold([review("a", "APPROVED", 1), GitHubReview(login: "a", state: "PENDING", submittedAt: nil)]),
            .approved
        )
    }

    /// A dismissed review from one reviewer does not erase another's live
    /// approval.
    func testDismissalOnlyRemovesThatReviewer() {
        let reviews = [review("a", "APPROVED", 1), review("a", "DISMISSED", 2), review("b", "APPROVED", 3)]
        XCTAssertEqual(PRReviewState.fold(reviews), .approved)
    }

    /// Same timestamp, two reviews — array order breaks the tie, latest wins.
    func testEqualTimestampsBreakByArrayOrder() {
        let date = ISO8601DateFormatter().date(from: "2026-08-10T09:00:00Z")!
        let older = GitHubReview(login: "a", state: "CHANGES_REQUESTED", submittedAt: date)
        let newer = GitHubReview(login: "a", state: "APPROVED", submittedAt: date)
        XCTAssertEqual(PRReviewState.fold([older, newer]), .approved)
    }

    func testFixtureFoldsToChangesRequested() throws {
        let url = Bundle(for: Self.self).url(forResource: "github_pr_reviews", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        let reviews = try XCTUnwrap(GitHubReviewParser.parse(data))
        // alice: latest COMMENTED, earlier APPROVED stands → approved.
        // bob: CHANGES_REQUESTED. carol: DISMISSED removes her approval.
        // dave: PENDING, ignored.
        XCTAssertEqual(PRReviewState.fold(reviews), .changesRequested)
    }
}

// MARK: - The cap

final class GitHubReviewStateCapTests: XCTestCase {
    private func item(_ number: Int, daysAgo: Int) -> PullRequestItem {
        PullRequestItem(
            id: "github:deck#\(number)", number: number, title: "t", repo: "deck",
            role: .authored, provider: .github, isDraft: false,
            createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - Double(daysAgo * 86_400)),
            url: ""
        )
    }

    /// More than `cap` rows can never render, so fetching review state for
    /// more of them pays the per-PR fan-out for nothing.
    func testLimitsToNewestCapRows() {
        let items = [item(1, daysAgo: 5), item(2, daysAgo: 1), item(3, daysAgo: 9), item(4, daysAgo: 3)]
        let capped = GitHubReviewStateCap.limit(items, to: 2)
        XCTAssertEqual(capped.map(\.number), [2, 4])
    }

    func testCapAboveCountKeepsEverything() {
        let items = [item(1, daysAgo: 5), item(2, daysAgo: 1)]
        XCTAssertEqual(GitHubReviewStateCap.limit(items, to: 6).count, 2)
    }

    func testEmptyItemsStayEmpty() {
        XCTAssertTrue(GitHubReviewStateCap.limit([], to: 6).isEmpty)
    }
}

// MARK: - Azure vote folding

final class AzureReviewFoldTests: XCTestCase {
    private let me = "5d48bc9c-1cf3-419c-b2c5-43c4d36875d2"

    private func reviewers(_ votes: [(String, Int)]) -> [[String: Any]] {
        votes.map { ["id": $0.0, "vote": $0.1] }
    }

    func testNoVotesIsNoState() {
        XCTAssertNil(PRReviewState.fold(azureReviewers: [], excluding: me))
        XCTAssertNil(PRReviewState.fold(azureReviewers: reviewers([("other", 0)]), excluding: me))
    }

    func testPositiveVotesFoldToApproved() {
        XCTAssertEqual(PRReviewState.fold(azureReviewers: reviewers([("other", 10)]), excluding: me), .approved)
        XCTAssertEqual(PRReviewState.fold(azureReviewers: reviewers([("other", 5)]), excluding: me), .approved)
    }

    func testNegativeVotesFoldToChangesRequested() {
        XCTAssertEqual(PRReviewState.fold(azureReviewers: reviewers([("other", -5)]), excluding: me), .changesRequested)
        XCTAssertEqual(PRReviewState.fold(azureReviewers: reviewers([("other", -10)]), excluding: me), .changesRequested)
    }

    /// Mixed folds negative, mirroring GitHub's CHANGES_REQUESTED precedence.
    func testMixedFoldsToChangesRequested() {
        XCTAssertEqual(
            PRReviewState.fold(azureReviewers: reviewers([("a", 10), ("b", -5)]), excluding: me),
            .changesRequested
        )
    }

    /// The PAT owner's own vote must not make a row read as approved — an
    /// authored PR carries the author's own +10 (measured live, probe §1).
    func testOwnVoteIsExcluded() {
        XCTAssertNil(PRReviewState.fold(azureReviewers: reviewers([(me, 10)]), excluding: me))
        XCTAssertNil(PRReviewState.fold(azureReviewers: reviewers([(me, -10)]), excluding: me))
        XCTAssertEqual(
            PRReviewState.fold(azureReviewers: reviewers([(me, -10), ("other", 10)]), excluding: me),
            .approved
        )
    }

    func testMalformedReviewerIsSkipped() {
        XCTAssertNil(PRReviewState.fold(azureReviewers: [["id": me]], excluding: me))
        XCTAssertNil(PRReviewState.fold(azureReviewers: [["vote": 10]], excluding: me))
    }
}

// MARK: - Stamping onto rows

final class ReviewStateOnRowsTests: XCTestCase {
    private let target = try! AzureTarget.normalise(organization: "ForesightAnalytics", project: "ForesightManifold")
    private let me = "5d48bc9c-1cf3-419c-b2c5-43c4d36875d2"

    /// The live-shaped fixture row 4397 carries MohammadReza (0) and the owner
    /// aliz (+10): excluding the owner leaves no substantive vote.
    func testAzureLiveFixtureRowCarriesNoState() throws {
        let url = Bundle(for: Self.self).url(forResource: "azure_prs", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        let items = try XCTUnwrap(AzurePRParser.parse(data, role: .authored, me: me, target: target))
        let row = try XCTUnwrap(items.first(where: { $0.number == 4397 }))
        XCTAssertNil(row.reviewState)
    }

    /// A row whose *other* reviewers have approved stamps `.approved`.
    func testAzureRowWithOtherApprovalsStampsApproved() throws {
        let json = """
        {"count":1,"value":[
          {"pullRequestId":1,"title":"t","isDraft":false,"creationDate":"2026-01-01T00:00:00Z",
           "repository":{"name":"r"},
           "reviewers":[{"id":"other","vote":10},{"id":"\(me)","vote":0}]}
        ]}
        """
        let items = try XCTUnwrap(AzurePRParser.parse(Data(json.utf8), role: .authored, me: me, target: target))
        XCTAssertEqual(items.first?.reviewState, .approved)
    }

    // MARK: - Snapshot decode

    func testAbsentReviewStateDecodesNil() throws {
        let json = """
        {"id":"github:deck#1","number":1,"title":"t","role":"authored",
         "provider":"github","createdAt":0,"url":""}
        """
        let row = try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8))
        XCTAssertNil(row.reviewState)
    }

    func testReviewStateRoundTrips() throws {
        var row = PullRequestItem(
            id: "github:deck#1", number: 1, title: "t", repo: "deck", role: .authored,
            provider: .github, isDraft: false, createdAt: Date(timeIntervalSince1970: 0), url: ""
        )
        row.reviewState = .changesRequested
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(PullRequestItem.self, from: data)
        XCTAssertEqual(decoded.reviewState, .changesRequested)
    }
}