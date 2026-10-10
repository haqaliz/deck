import XCTest

// Pull requests: GitHub and Azure DevOps, reached with the `pr ` prefix. Built
// and tested on FIXTURES ONLY: no live GitHub or Azure request has been made.
// The payload shapes below follow each API's documentation and what PRBox's own
// parsers already read; where that is an assumption it says so.

final class GitHubPRSearchQueryTests: XCTestCase {
    func testWithoutAScopeItSearchesPullRequestsYouAreInvolvedIn() {
        let q = GitHubPRSearch.query(tokens: ["login"], scope: "")
        XCTAssertEqual(q, "is:pr involves:@me \"login\" in:title,body")
    }

    /// PRBox's own scope ("org:acme") is the user's setting, trusted as written,
    /// and replaces `involves:@me` — it already bounds the search.
    func testAScopeReplacesInvolves() {
        let q = GitHubPRSearch.query(tokens: ["login"], scope: "  org:acme  ")
        XCTAssertEqual(q, "is:pr org:acme \"login\" in:title,body")
        XCTAssertFalse(q.contains("involves"))
    }

    func testEveryWordIsItsOwnQuotedTerm() {
        XCTAssertEqual(GitHubPRSearch.query(tokens: ["fix", "flaky", "test"], scope: ""),
                       "is:pr involves:@me \"fix\" \"flaky\" \"test\" in:title,body")
    }

    /// The point of the file for GitHub: typed words cannot act as search
    /// qualifiers. Everything after the fixed prefix must sit inside quotes.
    func testTypedQualifiersStayInsideQuotes() {
        let hostile = ["org:evil", "-involves:@me", "repo:x/y", "author:someone", "is:public", "OR",
                       "NOT", "user:\"x\"", "\" org:evil \"", "\\\"", "label:bug", "in:comments", "sort:updated"]
        for word in hostile {
            let q = GitHubPRSearch.query(tokens: GitHubPRSearch.tokens(for: "ab \(word)"), scope: "")
            let outside = Self.outsideQuotes(q)
            XCTAssertEqual(outside.split(separator: " ").map(String.init),
                           ["is:pr", "involves:@me", "in:title,body"] + Array(repeating: "", count: 0),
                           "\(word) leaked outside quotes: \(q)")
        }
    }

    /// Terms with the quoted content removed.
    private static func outsideQuotes(_ q: String) -> String {
        var out = ""; var inside = false
        for c in q { if c == "\"" { inside.toggle(); continue }; if !inside { out.append(c) } }
        return out.split(separator: " ").joined(separator: " ")
    }

    func testTokensDropQuotesBackslashesAndControlCharacters() {
        let t = GitHubPRSearch.tokens(for: "a\"b\\c d\u{0}e")
        XCTAssertEqual(t, ["abc", "d", "e"])
        XCTAssertTrue(GitHubPRSearch.tokens(for: "\"\"").isEmpty)
        XCTAssertTrue(GitHubPRSearch.tokens(for: " a ").isEmpty, "under two characters sends nothing")
    }

    func testTokensAreCapped() {
        XCTAssertEqual(GitHubPRSearch.tokens(for: "a1 b2 c3 d4 e5 f6 g7 h8").count, GitHubPRSearch.maxTokens)
        XCTAssertEqual(GitHubPRSearch.tokens(for: String(repeating: "x", count: 500)).first?.count,
                       GitHubPRSearch.maxTokenLength)
    }

    func testTheURLCarriesTheQueryInOneEncodedParameter() throws {
        let url = try XCTUnwrap(GitHubPRSearch.url(query: "is:pr involves:@me \"a&b=c\" in:title,body", perPage: 25))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "is:pr involves:@me \"a&b=c\" in:title,body")
        XCTAssertEqual(items.map(\.name).sorted(), ["order", "per_page", "q", "sort"], "the query injected a parameter")
        XCTAssertEqual(url.host, "api.github.com")
        XCTAssertEqual(url.path, "/search/issues")
    }

    func testRecentPullRequestsForNumberLookup() throws {
        let q = GitHubPRSearch.recentQuery(scope: "")
        XCTAssertEqual(q, "is:pr involves:@me")
        XCTAssertEqual(GitHubPRSearch.recentQuery(scope: "org:acme"), "is:pr org:acme")
        XCTAssertEqual(GitHubPRSearch.recentLimit, 100)
    }

    func testOnlyAWholeNumberTriggersTheNumberLookup() {
        XCTAssertEqual(GitHubPRSearch.number(from: "1234"), 1234)
        XCTAssertEqual(GitHubPRSearch.number(from: " #1234 "), 1234)
        for no in ["12a", "-5", "1.5", "", "99999999999999999999", "0"] {
            XCTAssertNil(GitHubPRSearch.number(from: no), no)
        }
    }
}

final class GitHubPRSearchParserTests: XCTestCase {
    private let json = """
    {"total_count":3,"items":[
      {"number":41,"title":"Fix login redirect","html_url":"https://github.com/acme/deck/pull/41",
       "state":"open","draft":false,"repository_url":"https://api.github.com/repos/acme/deck",
       "user":{"login":"ada"},"updated_at":"2026-01-10T10:00:00Z","pull_request":{"merged_at":null}},
      {"number":40,"title":"Refactor loader","html_url":"https://github.com/acme/deck/pull/40",
       "state":"closed","draft":false,"repository_url":"https://api.github.com/repos/acme/deck",
       "user":{"login":"bob"},"updated_at":"2026-01-09T10:00:00Z","pull_request":{"merged_at":"2026-01-09T11:00:00Z"}},
      {"number":39,"title":"WIP spike","html_url":"https://github.com/acme/api/pull/39",
       "state":"open","draft":true,"repository_url":"https://api.github.com/repos/acme/api",
       "user":{"login":"cy"},"updated_at":"2026-01-08T10:00:00Z","pull_request":{}},
      {"number":38,"title":"An issue, not a PR","html_url":"https://github.com/acme/deck/issues/38",
       "state":"open","repository_url":"https://api.github.com/repos/acme/deck","user":{"login":"x"}}
    ]}
    """

    func testParsesPullRequestsAndSkipsIssues() throws {
        let hits = try XCTUnwrap(GitHubPRSearchParser.parse(Data(json.utf8)))
        XCTAssertEqual(hits.map(\.number), [41, 40, 39])
        XCTAssertEqual(hits[0].repo, "acme/deck")
        XCTAssertEqual(hits[0].author, "ada")
        XCTAssertEqual(hits[0].provider, .github)
        XCTAssertEqual(hits[0].url, "https://github.com/acme/deck/pull/41")
    }

    func testStateIsOpenMergedClosedOrDraft() throws {
        let hits = try XCTUnwrap(GitHubPRSearchParser.parse(Data(json.utf8)))
        XCTAssertEqual(hits[0].state, .open)
        XCTAssertEqual(hits[1].state, .merged)
        XCTAssertTrue(hits[2].isDraft)
        let closed = #"{"items":[{"number":1,"title":"t","html_url":"https://github.com/a/b/pull/1","state":"closed","repository_url":"https://api.github.com/repos/a/b","pull_request":{"merged_at":null}}]}"#
        XCTAssertEqual(try XCTUnwrap(GitHubPRSearchParser.parse(Data(closed.utf8))).first?.state, .closed)
    }

    func testGarbageIsNilAndABadRowIsSkipped() {
        XCTAssertNil(GitHubPRSearchParser.parse(Data("not json".utf8)))
        XCTAssertNil(GitHubPRSearchParser.parse(Data("{}".utf8)))
        let mixed = #"{"items":[{"title":"no number"},{"number":2,"title":"ok","html_url":"https://github.com/a/b/pull/2","state":"open","repository_url":"https://api.github.com/repos/a/b","pull_request":{}}]}"#
        XCTAssertEqual(GitHubPRSearchParser.parse(Data(mixed.utf8))?.map(\.number), [2])
    }
}

final class AzurePRSearchTests: XCTestCase {
    private var target: AzureTarget { try! AzureTarget.normalise(organization: "Contoso", project: "Web") }

    func testTheByIDRouteIsOrganisationScoped() throws {
        let url = try XCTUnwrap(AzurePRSearch.byIDURL(target: target, id: 1234))
        XCTAssertEqual(url.absoluteString, "https://dev.azure.com/Contoso/_apis/git/pullrequests/1234?api-version=7.1")
    }

    func testTheListRouteAsksForRecentPullRequestsOfAnyStatus() throws {
        let url = try XCTUnwrap(AzurePRSearch.listURL(target: target))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "searchCriteria.status" }?.value, "all")
        XCTAssertEqual(items.first { $0.name == "$top" }?.value, String(AzurePRSearch.listLimit))
        XCTAssertEqual(url.path, "/Contoso/Web/_apis/git/pullrequests")
        // Typed text never reaches this URL: the list API has no text criteria,
        // so matching is local.
        XCTAssertFalse(url.absoluteString.contains("creatorId"))
    }

    private let listJSON = """
    {"value":[
      {"pullRequestId":12,"title":"Fix flaky checkout test","description":"Retries the payment stub",
       "status":"active","isDraft":false,"creationDate":"2026-01-10T10:00:00.1234567Z",
       "createdBy":{"displayName":"Ada"},"repository":{"name":"api","project":{"name":"Web"}}},
      {"pullRequestId":11,"title":"Bump deps","description":"",
       "status":"completed","isDraft":false,"creationDate":"2026-01-09T10:00:00Z",
       "createdBy":{"displayName":"Bob"},"repository":{"name":"api","project":{"name":"Web"}}},
      {"pullRequestId":10,"title":"Old idea","description":"abandoned approach",
       "status":"abandoned","isDraft":true,"creationDate":"2026-01-08T10:00:00Z",
       "createdBy":{"displayName":"Cy"},"repository":{"name":"web","project":{"name":"Web"}}}
    ]}
    """

    func testParsesTheListAndMapsStatus() throws {
        let hits = try XCTUnwrap(AzurePRSearchParser.parseList(Data(listJSON.utf8), organization: "Contoso"))
        XCTAssertEqual(hits.map(\.number), [12, 11, 10])
        XCTAssertEqual(hits.map(\.state), [.open, .merged, .closed])
        XCTAssertTrue(hits[2].isDraft)
        XCTAssertEqual(hits[0].repo, "api")
        XCTAssertEqual(hits[0].project, "Web")
        XCTAssertEqual(hits[0].author, "Ada")
        XCTAssertEqual(hits[0].provider, .azureDevOps)
        XCTAssertEqual(hits[0].url, "https://dev.azure.com/Contoso/Web/_git/api/pullrequest/12")
    }

    func testTheSingleResponseHasTheSameShape() throws {
        let single = """
        {"pullRequestId":12,"title":"Fix flaky checkout test","description":"d","status":"active","isDraft":false,
         "creationDate":"2026-01-10T10:00:00Z","createdBy":{"displayName":"Ada"},
         "repository":{"name":"api","project":{"name":"Web"}}}
        """
        let hit = try XCTUnwrap(AzurePRSearchParser.parseOne(Data(single.utf8), organization: "Contoso"))
        XCTAssertEqual(hit.number, 12)
        XCTAssertEqual(hit.url, "https://dev.azure.com/Contoso/Web/_git/api/pullrequest/12")
    }

    func testSegmentsAreEncodedInTheLink() throws {
        let json = #"{"pullRequestId":3,"title":"t","status":"active","repository":{"name":"my repo/x","project":{"name":"My Project"}}}"#
        let hit = try XCTUnwrap(AzurePRSearchParser.parseOne(Data(json.utf8), organization: "Contoso"))
        XCTAssertTrue(hit.url.hasPrefix("https://dev.azure.com/Contoso/My%20Project/_git/"), hit.url)
        XCTAssertEqual(URL(string: hit.url)?.host, "dev.azure.com")
    }

    func testListMatchingIsLocalOnTitleAndDescription() throws {
        let hits = try XCTUnwrap(AzurePRSearchParser.parseList(Data(listJSON.utf8), organization: "Contoso"))
        XCTAssertEqual(AzurePRSearch.filter(hits, tokens: ["flaky"]).map(\.number), [12])
        XCTAssertEqual(AzurePRSearch.filter(hits, tokens: ["payment"]).map(\.number), [12], "description matches")
        XCTAssertEqual(AzurePRSearch.filter(hits, tokens: ["approach", "old"]).map(\.number), [10], "every word, any order")
        XCTAssertTrue(AzurePRSearch.filter(hits, tokens: ["zzzz"]).isEmpty)
    }

    /// The by-id route is organisation-wide; only configured projects are PRBox's.
    func testByIDResultsAreRestrictedToTheConfiguredProjects() {
        func hit(_ project: String) -> PRSearchHit {
            PRSearchHit(provider: .azureDevOps, repo: "api", project: project, number: 1, title: "t",
                        description: "", state: .open, isDraft: false, author: "", url: "https://dev.azure.com/o/p", updated: nil)
        }
        let kept = AzurePRSearch.restrict([hit("Web"), hit("Secret"), hit("mobile")], toProjects: ["web", "Mobile"])
        XCTAssertEqual(kept.map(\.project), ["Web", "mobile"])
        XCTAssertTrue(AzurePRSearch.restrict([hit("Web")], toProjects: []).isEmpty)
    }

    func testAnUnknownPullRequestNumberIsAnEmptyAnswer() {
        // by-id for a missing PR is a 404: not a failure of the search.
        XCTAssertEqual(AzurePRSearch.interpretByID(status: 404, body: Data()), .some([]))
        XCTAssertNil(AzurePRSearch.interpretByID(status: 500, body: Data()), "other statuses are failures")
    }
}

final class PRSearchResultsTests: XCTestCase {
    private func hit(_ provider: PRProvider = .github, repo: String = "acme/deck", n: Int = 41,
                     title: String = "Fix login", state: PRSearchState = .open, draft: Bool = false,
                     project: String? = nil, url: String = "https://github.com/acme/deck/pull/41",
                     author: String = "ada") -> PRSearchHit {
        PRSearchHit(provider: provider, repo: repo, project: project, number: n, title: title,
                    description: "", state: state, isDraft: draft, author: author, url: url, updated: nil)
    }

    func testARowOpensThePullRequest() throws {
        let r = PRSearch.results(from: [hit()], query: "login")[0]
        XCTAssertEqual(r.provider, .pr)
        XCTAssertEqual(r.title, "Fix login")
        XCTAssertEqual(r.subtitle, "acme/deck #41 · Open · ada")
        XCTAssertEqual(r.action, .open(try XCTUnwrap(URL(string: "https://github.com/acme/deck/pull/41"))))
    }

    func testStateWords() {
        XCTAssertEqual(PRSearch.results(from: [hit(state: .merged)], query: "fix")[0].subtitle, "acme/deck #41 · Merged · ada")
        XCTAssertEqual(PRSearch.results(from: [hit(state: .closed)], query: "fix")[0].subtitle, "acme/deck #41 · Closed · ada")
        XCTAssertEqual(PRSearch.results(from: [hit(draft: true)], query: "fix")[0].subtitle, "acme/deck #41 · Draft · ada")
    }

    func testAnAzureRowShowsItsProject() {
        let r = PRSearch.results(from: [hit(.azureDevOps, repo: "api", project: "Web",
                                            url: "https://dev.azure.com/o/Web/_git/api/pullrequest/41")], query: "fix")[0]
        XCTAssertEqual(r.subtitle, "Web / api #41 · Open · ada")
    }

    /// Two providers, repos and projects can each have a #41.
    func testIDsAreDistinctAcrossProvidersReposAndProjects() {
        let rows = PRSearch.results(from: [
            hit(.github, repo: "acme/deck", n: 41), hit(.github, repo: "acme/api", n: 41),
            hit(.azureDevOps, repo: "api", n: 41, project: "Web", url: "https://dev.azure.com/o/Web/_git/api/pullrequest/41"),
            hit(.azureDevOps, repo: "api", n: 41, project: "Mobile", url: "https://dev.azure.com/o/Mobile/_git/api/pullrequest/41"),
        ], query: "fix")
        XCTAssertEqual(Set(rows.map(\.id)).count, 4)
    }

    func testAnExactNumberOutranksAMention() {
        let rows = SpotlightRanking.sorted(PRSearch.results(from: [
            hit(n: 7, title: "Follow-up to 1234"), hit(n: 1234, title: "Something else"),
        ], query: "1234"))
        XCTAssertEqual(rows.first?.title, "Something else")
    }

    /// The service already decided these match (it searched the body too); a
    /// local matcher that only reads titles must not drop them.
    func testNothingTheServiceReturnedIsFilteredOut() {
        XCTAssertEqual(PRSearch.results(from: [hit(title: "Unrelated title")], query: "login").count, 1)
    }

    func testAnUnsafeLinkIsCopyOnly() {
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "", "https://"] {
            XCTAssertEqual(PRSearch.results(from: [hit(url: bad)], query: "fix")[0].action, .copy("#41"), bad)
        }
    }

    func testResultsAreCappedAndDeduplicated() {
        let many = (1...80).map { hit(n: $0) }
        XCTAssertLessThanOrEqual(PRSearch.results(from: many + many, query: "fix").count, PRSearch.totalLimit)
        XCTAssertEqual(PRSearch.results(from: [hit(), hit()], query: "fix").count, 1, "the same PR from two requests is one row")
    }
}

final class SourceMergeTests: XCTestCase {
    func testPartialAnswersAreKept() throws {
        let m = try SourceMerge.combine(Result<[Int], Error>.failure(SearchSourceFailure(.unreachable)),
                                        Result<[String], Error>.success(["a"]), ifNothingAnswered: .notConfigured)
        XCTAssertTrue(m.0.isEmpty)
        XCTAssertEqual(m.1, ["a"])
    }

    func testNothingAnsweredReportsTheGivenReasonOrTheFirstError() {
        XCTAssertThrowsError(try SourceMerge.combine(Result<[Int], Error>?.none, Result<[String], Error>?.none,
                                                     ifNothingAnswered: .notConfigured)) {
            XCTAssertEqual(RemoteSearchFailure(error: $0), .notConfigured)
        }
        XCTAssertThrowsError(try SourceMerge.combine(Result<[Int], Error>.failure(SearchSourceFailure(.authOrTarget)),
                                                     Result<[String], Error>?.none, ifNothingAnswered: .notConfigured)) {
            XCTAssertEqual(RemoteSearchFailure(error: $0), .authOrTarget)
        }
    }
}
