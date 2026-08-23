import XCTest

// PRBox pure logic: the provider-agnostic model, tolerant decode, and the four
// decisions the widget must not make for itself — sort order, dedupe, age
// wording, and the capped-count flag.
//
// The capped flags exist because Azure DevOps reports no total: its PR
// response carries `count` (rows returned) and nothing else, so a `$top` of
// the row cap would make every count saturate silently. GitHub's search
// `total_count` is independent of `per_page`, so only the Azure half needs it.

// MARK: - Model + tolerant decode

final class PullRequestItemDecodeTests: XCTestCase {
    private func sample(
        id: String = "gh:haqaliz/deck#41",
        role: PRRole = .authored,
        provider: PRProvider = .github
    ) -> PullRequestItem {
        PullRequestItem(
            id: id,
            number: 41,
            title: "Review queue widget",
            repo: "deck",
            role: role,
            provider: provider,
            isDraft: false,
            createdAt: Date(timeIntervalSince1970: 1_787_000_000),
            url: "https://github.com/haqaliz/deck/pull/41"
        )
    }

    func testRoundTripsAllFields() throws {
        let item = sample()
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(PullRequestItem.self, from: data), item)
    }

    /// A snapshot written by a future agent that ships GitLab must still decode
    /// here — one unknown string must not throw away the whole queue.
    func testUnknownProviderDecodesAsUnknown() throws {
        let json = #"{"id":"x","number":1,"title":"T","repo":"r","role":"authored","provider":"gitlab","isDraft":false,"createdAt":0,"url":""}"#
        let item = try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.provider, .unknown)
    }

    /// Unlike `provider`, `role` is strict. There is no honest default: calling
    /// an unknown role `.authored` inflates the MINE count and `.reviewing`
    /// inflates the queue, and both read as a wrong number rather than as
    /// missing data. The row is dropped at the snapshot level instead.
    func testUnknownRoleThrows() {
        let json = #"{"id":"x","number":1,"title":"T","repo":"r","role":"mentioned","provider":"github","isDraft":false,"createdAt":0,"url":""}"#
        XCTAssertThrowsError(try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8)))
    }

    /// `title` is required: a row without one is not a pull request, and
    /// rendering a blank line would read as a bug rather than as missing data.
    func testMissingTitleThrows() {
        let json = #"{"id":"x","number":1,"repo":"r","role":"authored","provider":"github","isDraft":false,"createdAt":0,"url":""}"#
        XCTAssertThrowsError(try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8)))
    }

    func testMissingOptionalFieldsDefault() throws {
        let json = #"{"id":"x","number":1,"title":"T","role":"authored","provider":"github","createdAt":0}"#
        let item = try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.repo, "")
        XCTAssertFalse(item.isDraft)
        XCTAssertEqual(item.url, "")
    }
}

// MARK: - Sorting

final class PRFormattingSortTests: XCTestCase {
    private func item(
        _ number: Int,
        _ secondsSinceEpoch: TimeInterval,
        provider: PRProvider = .github,
        repo: String = "deck"
    ) -> PullRequestItem {
        PullRequestItem(
            id: "\(provider.rawValue):\(repo)#\(number)",
            number: number,
            title: "PR \(number)",
            repo: repo,
            role: .authored,
            provider: provider,
            isDraft: false,
            createdAt: Date(timeIntervalSince1970: secondsSinceEpoch),
            url: ""
        )
    }

    /// Both providers are sorted by creation date because Azure DevOps reports
    /// no update timestamp at all. Mixing `updated_at` for GitHub with
    /// `creationDate` for Azure would sink a freshly-pushed Azure PR below a
    /// stale GitHub one, which reads as a bug.
    func testNewestFirstAcrossProviders() {
        let sorted = PRFormatting.sorted([
            item(1, 100, provider: .github),
            item(2, 300, provider: .azureDevOps),
            item(3, 200, provider: .github),
        ])
        XCTAssertEqual(sorted.map(\.number), [2, 3, 1])
    }

    /// Equal timestamps must not shuffle between ticks — an order that changes
    /// on its own looks like data changing when nothing did.
    func testEqualDatesBreakTieStably() {
        let a = item(9, 500, provider: .github, repo: "deck")
        let b = item(4, 500, provider: .azureDevOps, repo: "manifold")
        let c = item(7, 500, provider: .github, repo: "alpha")
        XCTAssertEqual(
            PRFormatting.sorted([a, b, c]).map(\.id),
            PRFormatting.sorted([c, b, a]).map(\.id)
        )
    }

    func testEmptyListSortsToEmpty() {
        XCTAssertTrue(PRFormatting.sorted([]).isEmpty)
    }
}

// MARK: - Dedupe

final class PRFormattingDedupeTests: XCTestCase {
    private func item(role: PRRole, number: Int = 41, provider: PRProvider = .github, repo: String = "deck") -> PullRequestItem {
        PullRequestItem(
            id: "\(provider.rawValue):\(repo)#\(number)",
            number: number,
            title: "PR \(number)",
            repo: repo,
            role: role,
            provider: provider,
            isDraft: false,
            createdAt: Date(timeIntervalSince1970: 100),
            url: ""
        )
    }

    /// Azure DevOps lets you be a reviewer on your own pull request, and the
    /// vote filter keeps it, so the same PR really can arrive from both role
    /// queries. Two identical rows would read as a rendering bug.
    func testSamePRInBothRolesCollapsesToAuthored() {
        let deduped = PRFormatting.deduped([item(role: .reviewing), item(role: .authored)])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.role, .authored)
    }

    func testAuthoredWinsRegardlessOfInputOrder() {
        let deduped = PRFormatting.deduped([item(role: .authored), item(role: .reviewing)])
        XCTAssertEqual(deduped.map(\.role), [.authored])
    }

    /// The key is (provider, repo, number) — the same number in a different
    /// repo, or on a different provider, is a different pull request.
    func testSameNumberDifferentRepoIsNotADuplicate() {
        let deduped = PRFormatting.deduped([
            item(role: .authored, repo: "deck"),
            item(role: .authored, repo: "manifold"),
        ])
        XCTAssertEqual(deduped.count, 2)
    }

    func testSameNumberDifferentProviderIsNotADuplicate() {
        let deduped = PRFormatting.deduped([
            item(role: .authored, provider: .github),
            item(role: .authored, provider: .azureDevOps),
        ])
        XCTAssertEqual(deduped.count, 2)
    }
}

// MARK: - Age wording

final class PRFormattingAgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    private func age(_ secondsAgo: TimeInterval) -> String {
        PRFormatting.age(from: now.addingTimeInterval(-secondsAgo), to: now)
    }

    /// Suffix-less on purpose: `OpenBoxCore.relativeTime` says "2h ago", which
    /// is right in a sentence and noise in a right-aligned column.
    func testMinutesHoursDays() {
        XCTAssertEqual(age(90), "1m")
        XCTAssertEqual(age(3 * 3600), "3h")
        XCTAssertEqual(age(10 * 86400), "10d")
    }

    func testUnderAMinuteReadsAsZeroMinutes() {
        XCTAssertEqual(age(5), "0m")
    }

    /// Clock skew between the API host and this machine must not render "-1m".
    func testFutureDateClampsToZero() {
        XCTAssertEqual(PRFormatting.age(from: now.addingTimeInterval(600), to: now), "0m")
    }

    func testBoundaries() {
        XCTAssertEqual(age(3599), "59m")
        XCTAssertEqual(age(3600), "1h")
        XCTAssertEqual(age(86_399), "23h")
        XCTAssertEqual(age(86_400), "1d")
    }
}

// MARK: - Snapshot

final class PRBoxSnapshotTests: XCTestCase {
    private func snapshot(authoredCapped: Bool = false) -> PRBoxSnapshot {
        PRBoxSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_787_000_000),
            authoredCount: 3,
            reviewingCount: 5,
            authoredCapped: authoredCapped,
            reviewingCapped: false,
            pullRequests: []
        )
    }

    func testRoundTrips() throws {
        let data = try JSONEncoder().encode(snapshot())
        XCTAssertEqual(try JSONDecoder().decode(PRBoxSnapshot.self, from: data), snapshot())
    }

    /// A snapshot written before the capped flags existed must not throw — it
    /// simply reports uncapped counts, which is what it meant.
    func testMissingCappedFlagsDecodeAsFalse() throws {
        let json = #"{"writtenAt":0,"authoredCount":1,"reviewingCount":2,"pullRequests":[]}"#
        let snap = try JSONDecoder().decode(PRBoxSnapshot.self, from: Data(json.utf8))
        XCTAssertFalse(snap.authoredCapped)
        XCTAssertFalse(snap.reviewingCapped)
    }

    /// One malformed row must not blank the whole queue: the rows that decode
    /// are rendered, the rest are skipped. This is what makes `PullRequestItem`
    /// free to be strict about identity fields.
    func testUndecodableRowIsDroppedAndTheRestSurvive() throws {
        let json = """
        {"writtenAt":0,"authoredCount":2,"reviewingCount":0,"pullRequests":[
          {"id":"a","number":1,"title":"good","repo":"r","role":"authored","provider":"github","isDraft":false,"createdAt":0,"url":""},
          {"id":"b","number":2,"repo":"r","role":"authored","provider":"github","isDraft":false,"createdAt":0,"url":""},
          {"id":"c","number":3,"title":"also good","repo":"r","role":"reviewing","provider":"azureDevOps","isDraft":false,"createdAt":0,"url":""}
        ]}
        """
        let snap = try JSONDecoder().decode(PRBoxSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.pullRequests.map(\.id), ["a", "c"])
    }

    /// The header shows "100+" rather than a number the Azure API cannot
    /// actually promise.
    func testCountLabelSaysPlusWhenCapped() {
        XCTAssertEqual(PRFormatting.countLabel(3, capped: false), "3")
        XCTAssertEqual(PRFormatting.countLabel(100, capped: true), "100+")
    }
}

// MARK: - Building one snapshot from two providers

final class PRSnapshotBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    private func item(
        _ number: Int, _ provider: PRProvider, _ role: PRRole,
        secondsAgo: TimeInterval = 0, repo: String = "r"
    ) -> PullRequestItem {
        PullRequestItem(
            id: "\(provider.rawValue):\(repo)#\(number)",
            number: number, title: "PR \(number)", repo: repo, role: role,
            provider: provider, isDraft: false,
            createdAt: now.addingTimeInterval(-secondsAgo), url: ""
        )
    }

    private func totals(
        _ items: [PullRequestItem], authored: Int, reviewing: Int,
        authoredCapped: Bool = false, reviewingCapped: Bool = false
    ) -> PRRoleTotals {
        PRRoleTotals(
            authoredTotal: authored, reviewingTotal: reviewing,
            authoredCapped: authoredCapped, reviewingCapped: reviewingCapped,
            items: items
        )
    }

    func testCountsAreTheUnionOfBothProviders() {
        let snap = PRSnapshotBuilder.build(
            github: totals([item(1, .github, .authored)], authored: 1, reviewing: 4),
            azure: totals([item(2, .azureDevOps, .authored)], authored: 2, reviewing: 3),
            cap: 10, now: now
        )
        XCTAssertEqual(snap.authoredCount, 3)
        XCTAssertEqual(snap.reviewingCount, 7)
    }

    /// A provider that fails contributes nothing rather than blanking the
    /// other's rows — half a queue is still worth reading, and the chip says
    /// which half is missing.
    func testAFailedProviderLeavesTheOtherIntact() {
        let snap = PRSnapshotBuilder.build(
            github: nil,
            azure: totals([item(2, .azureDevOps, .reviewing)], authored: 0, reviewing: 1),
            cap: 10, now: now
        )
        XCTAssertEqual(snap.reviewingCount, 1)
        XCTAssertEqual(snap.pullRequests.map(\.number), [2])
    }

    func testBothProvidersFailingGivesAnEmptySnapshotNotACrash() {
        let snap = PRSnapshotBuilder.build(github: nil, azure: nil, cap: 10, now: now)
        XCTAssertEqual(snap.authoredCount, 0)
        XCTAssertTrue(snap.pullRequests.isEmpty)
    }

    /// Either provider's capped flag makes the union a floor.
    func testCappedFlagsPropagateFromEitherProvider() {
        let snap = PRSnapshotBuilder.build(
            github: totals([], authored: 5, reviewing: 0),
            azure: totals([], authored: 101, reviewing: 0, authoredCapped: true),
            cap: 10, now: now
        )
        XCTAssertTrue(snap.authoredCapped)
        XCTAssertFalse(snap.reviewingCapped)
    }

    func testRowsAreSortedNewestFirstAcrossProviders() {
        let snap = PRSnapshotBuilder.build(
            github: totals([item(1, .github, .authored, secondsAgo: 500)], authored: 1, reviewing: 0),
            azure: totals([item(2, .azureDevOps, .authored, secondsAgo: 100)], authored: 1, reviewing: 0),
            cap: 10, now: now
        )
        XCTAssertEqual(snap.pullRequests.map(\.number), [2, 1])
    }

    func testDuplicatesAreCollapsedBeforeTheCapIsApplied() {
        let both = [
            item(7, .github, .reviewing, secondsAgo: 10),
            item(7, .github, .authored, secondsAgo: 10),
            item(8, .github, .authored, secondsAgo: 20),
        ]
        let snap = PRSnapshotBuilder.build(
            github: totals(both, authored: 2, reviewing: 1), azure: nil, cap: 2, now: now
        )
        XCTAssertEqual(snap.pullRequests.count, 2)
        XCTAssertEqual(snap.pullRequests.first?.role, .authored)
    }

    /// The stored rows are trimmed but the counts are not: the header is
    /// allowed to exceed the list, which is the whole reason it is a separate
    /// number.
    func testRowsAreCappedWhileCountsAreNot() {
        let items = (1...20).map { item($0, .github, .authored, secondsAgo: TimeInterval($0)) }
        let snap = PRSnapshotBuilder.build(
            github: totals(items, authored: 20, reviewing: 0), azure: nil, cap: 6, now: now
        )
        XCTAssertEqual(snap.pullRequests.count, 6)
        XCTAssertEqual(snap.authoredCount, 20)
    }

    func testWrittenAtIsStamped() {
        let snap = PRSnapshotBuilder.build(github: nil, azure: nil, cap: 6, now: now)
        XCTAssertEqual(snap.writtenAt, now)
    }
}

// MARK: - Row destination

final class PRDestinationTests: XCTestCase {
    private func item(url: String) -> PullRequestItem {
        PullRequestItem(
            id: "github:deck#1", number: 1, title: "T", repo: "deck",
            role: .authored, provider: .github, isDraft: false,
            createdAt: Date(timeIntervalSince1970: 0), url: url
        )
    }

    func testHTTPSURLIsClickable() {
        XCTAssertEqual(
            PRFormatting.destination(for: item(url: "https://github.com/haqaliz/deck/pull/33")),
            URL(string: "https://github.com/haqaliz/deck/pull/33")
        )
    }

    func testAzureConstructedURLIsClickable() {
        let url = "https://dev.azure.com/Org/Proj/_git/manifold/pullrequest/4396"
        XCTAssertEqual(PRFormatting.destination(for: item(url: url)), URL(string: url))
    }

    /// A row whose provider gave no URL — or a snapshot written before the
    /// field was populated — must render as plain text rather than as a link
    /// that goes nowhere.
    func testEmptyURLIsNotClickable() {
        XCTAssertNil(PRFormatting.destination(for: item(url: "")))
        XCTAssertNil(PRFormatting.destination(for: item(url: "   ")))
    }

    /// Only http(s) opens a browser. Anything else in a snapshot is either
    /// junk or an attempt to have the widget launch something else, and the
    /// row simply isn't a link.
    func testNonWebSchemesAreRejected() {
        XCTAssertNil(PRFormatting.destination(for: item(url: "file:///etc/passwd")))
        XCTAssertNil(PRFormatting.destination(for: item(url: "javascript:alert(1)")))
        XCTAssertNil(PRFormatting.destination(for: item(url: "not a url at all")))
    }

    func testPlainHTTPIsAllowed() {
        let url = "http://ghe.internal/org/repo/pull/2"
        XCTAssertEqual(PRFormatting.destination(for: item(url: url)), URL(string: url))
    }
}

// MARK: - The parsers must supply what the link needs

final class PRSourceURLTests: XCTestCase {
    /// Characterises existing parser behaviour, because the clickable row now
    /// depends on it: a provider that stopped populating `url` would silently
    /// turn every row back into plain text.
    func testGitHubRowsCarryTheirHTMLURL() throws {
        let url = Bundle(for: Self.self).url(forResource: "github_prs", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        let items = try XCTUnwrap(GitHubPRParser.parse(data, role: .authored))
        XCTAssertTrue(items.allSatisfy { PRFormatting.destination(for: $0) != nil })
    }
}
