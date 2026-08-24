import XCTest

// GitHub half of PRBox: the search-payload parser and the query builder.
//
// The fixture `github_prs.json` is a trimmed copy of a real
// /search/issues response (two live rows plus one draft), so a change in the
// API's shape shows up here rather than on the desktop.

final class GitHubPRParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "missing fixture \(name).json"))
    }

    func testParsesLivePayload() throws {
        let items = try XCTUnwrap(GitHubPRParser.parse(try fixture("github_prs"), role: .authored))
        XCTAssertEqual(items.count, 3)
    }

    /// The repo column shows the short name, which the search payload only
    /// carries as the tail of an API URL.
    func testRepoComesFromRepositoryURLTail() throws {
        let items = try XCTUnwrap(GitHubPRParser.parse(try fixture("github_prs"), role: .authored))
        XCTAssertEqual(items.map(\.repo), ["dev", "NODE-COURSE", "deck"])
    }

    func testDraftFlagIsHonored() throws {
        let items = try XCTUnwrap(GitHubPRParser.parse(try fixture("github_prs"), role: .authored))
        XCTAssertEqual(items.filter(\.isDraft).map(\.number), [7])
    }

    func testRoleIsStamped() throws {
        let items = try XCTUnwrap(GitHubPRParser.parse(try fixture("github_prs"), role: .reviewing))
        XCTAssertTrue(items.allSatisfy { $0.role == .reviewing })
        XCTAssertTrue(items.allSatisfy { $0.provider == .github })
    }

    func testParsesISO8601CreatedAt() throws {
        let items = try XCTUnwrap(GitHubPRParser.parse(try fixture("github_prs"), role: .authored))
        let expected = ISO8601DateFormatter().date(from: "2022-08-27T21:04:18Z")
        XCTAssertEqual(items.first?.createdAt, expected)
    }

    func testIDIsProviderQualified() throws {
        let items = try XCTUnwrap(GitHubPRParser.parse(try fixture("github_prs"), role: .authored))
        XCTAssertEqual(items.last?.id, "github:deck#7")
    }

    /// GitHub reports the true total independently of `per_page`, so the
    /// header never has to guess — unlike the Azure half.
    func testTotalCountIsReadFromThePayloadNotTheRowCount() throws {
        let parsed = try XCTUnwrap(GitHubPRParser.parseResult(try fixture("github_prs"), role: .authored))
        XCTAssertEqual(parsed.totalCount, 3)
    }

    // MARK: - Malformed input

    /// A payload that isn't a search result at all must read as "bad response"
    /// (nil), not as "no pull requests" (empty) — the two say different things
    /// to the user.
    func testNonObjectPayloadReturnsNil() {
        XCTAssertNil(GitHubPRParser.parse(Data("[]".utf8), role: .authored))
        XCTAssertNil(GitHubPRParser.parse(Data("not json".utf8), role: .authored))
    }

    func testMissingItemsKeyReturnsNil() {
        XCTAssertNil(GitHubPRParser.parse(Data(#"{"total_count":0}"#.utf8), role: .authored))
    }

    func testEmptyItemsIsEmptyNotNil() throws {
        let items = GitHubPRParser.parse(Data(#"{"total_count":0,"items":[]}"#.utf8), role: .authored)
        XCTAssertEqual(items, [])
    }

    /// One unusable row must not discard the rest of the queue.
    func testRowMissingRequiredFieldIsSkipped() throws {
        let json = """
        {"total_count":2,"items":[
          {"number":1,"repository_url":"https://api.github.com/repos/o/r","created_at":"2026-01-01T00:00:00Z"},
          {"number":2,"title":"good","repository_url":"https://api.github.com/repos/o/r","created_at":"2026-01-01T00:00:00Z","html_url":"u"}
        ]}
        """
        let items = try XCTUnwrap(GitHubPRParser.parse(Data(json.utf8), role: .authored))
        XCTAssertEqual(items.map(\.number), [2])
    }

    func testRowWithUnparseableDateIsSkipped() throws {
        let json = """
        {"total_count":1,"items":[
          {"number":1,"title":"t","repository_url":"https://api.github.com/repos/o/r","created_at":"yesterday","html_url":"u"}
        ]}
        """
        let items = try XCTUnwrap(GitHubPRParser.parse(Data(json.utf8), role: .authored))
        XCTAssertTrue(items.isEmpty)
    }
}

// MARK: - Query building

final class GitHubPRQueryTests: XCTestCase {
    func testAuthoredQuery() {
        XCTAssertEqual(
            GitHubPRQuery.searchTerms(role: .authored, scope: ""),
            "is:pr is:open author:@me"
        )
    }

    func testReviewingQuery() {
        XCTAssertEqual(
            GitHubPRQuery.searchTerms(role: .reviewing, scope: ""),
            "is:pr is:open review-requested:@me"
        )
    }

    /// `author:@me` spans every repository the token can see, which on a
    /// long-lived account reaches years back into personal repos. The optional
    /// scope is how a user narrows it.
    func testScopeIsAppended() {
        XCTAssertEqual(
            GitHubPRQuery.searchTerms(role: .authored, scope: "org:acme"),
            "is:pr is:open author:@me org:acme"
        )
    }

    func testWhitespaceOnlyScopeIsIgnored() {
        XCTAssertEqual(
            GitHubPRQuery.searchTerms(role: .authored, scope: "   "),
            "is:pr is:open author:@me"
        )
    }

    func testURLPercentEncodesTheQuery() throws {
        let url = try XCTUnwrap(GitHubPRQuery.url(role: .authored, scope: "org:acme", perPage: 7))
        let string = url.absoluteString
        XCTAssertTrue(string.hasPrefix("https://api.github.com/search/issues?q="))
        XCTAssertFalse(string.contains(" "))
        XCTAssertTrue(string.contains("per_page=7"))
    }

    func testURLSurvivesAScopeWithSpaces() throws {
        let url = try XCTUnwrap(GitHubPRQuery.url(role: .authored, scope: "org:acme repo:a/b", perPage: 5))
        XCTAssertFalse(url.absoluteString.contains(" "))
    }
}
