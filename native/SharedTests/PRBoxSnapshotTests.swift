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
