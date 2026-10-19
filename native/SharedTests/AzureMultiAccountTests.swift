import XCTest

/// The multi-account half of Azure: a PAT is organization-scoped, so a slot
/// bound to several accounts is multi-org. Three behaviours are pinned because
/// each is a wrong face if it slips: the gate's answer for a mixed selection,
/// the merge that turns N accounts' snapshots into one, and the row identity
/// that keeps two orgs' same-named repos apart.
final class AzureMultiAccountTests: XCTestCase {

    // MARK: - Fixtures

    private func account(_ id: String, org: String, projects: [String], token: String = "t") -> CredentialAccount {
        var a = CredentialAccount(id: id, kind: .azure, label: id)
        a.organization = org
        a.projects = projects
        a.token = token
        return a
    }

    private func settings(_ accounts: [CredentialAccount], bound: [String]) -> DeckSettings {
        var s = DeckSettings()
        s.credentials.accounts = accounts
        s.setAccountIDs(bound, for: .taskbox)
        return s
    }

    private func task(
        _ id: String, changed: TimeInterval, org: String? = nil, project: String? = nil
    ) -> TaskItem {
        TaskItem(
            id: id, title: "t\(id)", state: "New", itemType: "Task",
            url: "https://dev.azure.com/x/y/_workitems/edit/\(id)",
            provider: .azureDevOps, changedAt: Date(timeIntervalSince1970: changed),
            project: project, organization: org
        )
    }

    private func snapshot(
        scope: String, total: Int = 0, sprint: String? = nil,
        tasks: [TaskItem] = [], note: String? = nil, lowerBound: Bool = false
    ) -> TaskBoxSnapshot {
        TaskBoxSnapshot(
            writtenAt: Date(timeIntervalSince1970: 0), scope: scope, totalCount: total,
            sprint: sprint, tasks: tasks, note: note, totalIsLowerBound: lowerBound
        )
    }

    private func pr(
        _ org: String?, repo: String, number: Int, role: PRRole = .authored, project: String? = nil
    ) -> PullRequestItem {
        PullRequestItem(
            id: "azureDevOps:\(org ?? "")/\(project ?? "")/\(repo)#\(number)",
            number: number, title: "pr", repo: repo, role: role, provider: .azureDevOps,
            isDraft: false, createdAt: Date(timeIntervalSince1970: 0),
            url: "https://dev.azure.com/x/y/_git/\(repo)/pullrequest/\(number)",
            project: project, organization: org
        )
    }

    // MARK: - The gate with several accounts

    func testTwoBoundAccountsBothReachTheLoader() {
        let s = settings(
            [account("a1", org: "acme", projects: ["p1"]), account("a2", org: "other", projects: ["p2"])],
            bound: ["a1", "a2"]
        )

        XCTAssertEqual(s.gate(.taskbox, unavailable: []), .fetch([
            ResolvedCredential(id: "a1", token: "t", organization: "acme", projects: ["p1"]),
            ResolvedCredential(id: "a2", token: "t", organization: "other", projects: ["p2"]),
        ]))
    }

    func testOneUnavailableAccountAmongResolvedOnesStillFetches() {
        // Partial is an answer: one bad account must not blank the others.
        let s = settings(
            [account("a1", org: "acme", projects: ["p1"]), account("a2", org: "other", projects: ["p2"])],
            bound: ["a1", "a2"]
        )

        XCTAssertEqual(s.gate(.taskbox, unavailable: ["a2"]), .fetch([
            ResolvedCredential(id: "a1", token: "t", organization: "acme", projects: ["p1"]),
        ]))
    }

    func testAllBoundAccountsUnavailableIsUnavailable() {
        let s = settings(
            [account("a1", org: "acme", projects: ["p1"]), account("a2", org: "other", projects: ["p2"])],
            bound: ["a1", "a2"]
        )

        XCTAssertEqual(s.gate(.taskbox, unavailable: ["a1", "a2"]), .unavailable)
    }

    func testADanglingBoundAccountStillFetchesTheOther() {
        let s = settings([account("a1", org: "acme", projects: ["p1"])], bound: ["a1", "deleted"])

        XCTAssertEqual(s.gate(.taskbox, unavailable: []), .fetch([
            ResolvedCredential(id: "a1", token: "t", organization: "acme", projects: ["p1"]),
        ]))
    }

    func testOnlyDanglingBoundAccountsIsNotConfigured() {
        let s = settings([], bound: ["deleted-a", "deleted-b"])

        XCTAssertEqual(s.gate(.taskbox, unavailable: []), .notConfigured)
    }

    func testNoSelectionIsOff() {
        XCTAssertEqual(DeckSettings().gate(.taskbox, unavailable: []), .off)
    }

    func testTheSingleAccessorReadsAOneElementList() {
        let s = settings([account("a1", org: "acme", projects: ["p1"])], bound: ["a1"])

        XCTAssertEqual(s.gate(.taskbox, unavailable: []).single,
                       ResolvedCredential(id: "a1", token: "t", organization: "acme", projects: ["p1"]))
    }

    func testTheSingleAccessorIsNilForSeveral() {
        let s = settings(
            [account("a1", org: "acme", projects: ["p1"]), account("a2", org: "other", projects: ["p2"])],
            bound: ["a1", "a2"]
        )

        XCTAssertNil(s.gate(.taskbox, unavailable: []).single)
    }

    // MARK: - Naming the accounts that did not contribute

    func testSkippedBoundAccountsNamesAnUnavailableOne() {
        let s = settings(
            [account("a1", org: "acme", projects: ["p1"]), account("a2", org: "other", projects: ["p2"])],
            bound: ["a1", "a2"]
        )

        XCTAssertEqual(
            s.skippedBoundAccounts(for: .taskbox, unavailable: ["a2"]),
            [AzureAccountFailure(name: "a2", outcome: .credentialsUnavailable)]
        )
    }

    func testSkippedBoundAccountsNamesAnAccountMissingAProject() {
        let s = settings(
            [account("a1", org: "acme", projects: ["p1"]), account("a2", org: "other", projects: [])],
            bound: ["a1", "a2"]
        )

        XCTAssertEqual(
            s.skippedBoundAccounts(for: .taskbox, unavailable: []),
            [AzureAccountFailure(name: "a2", outcome: .notConfigured)]
        )
    }

    func testSkippedBoundAccountsIsEmptyWhenAllContribute() {
        let s = settings([account("a1", org: "acme", projects: ["p1"])], bound: ["a1"])

        XCTAssertEqual(s.skippedBoundAccounts(for: .taskbox, unavailable: []), [])
    }

    // MARK: - Merging TaskBox snapshots

    func testMergedSumsTotalsAndOrsTheLowerBound() {
        let merged = TaskBoxMerge.merged(
            [snapshot(scope: "acme / p1", total: 3), snapshot(scope: "other / p2", total: 4, lowerBound: true)],
            organizations: ["acme", "other"], targetCount: 2, failures: []
        )

        XCTAssertEqual(merged.totalCount, 7)
        XCTAssertTrue(merged.totalIsLowerBound)
    }

    func testOneTargetKeepsItsOwnScopeAndSprint() {
        // The single-account, single-project regression bar.
        let merged = TaskBoxMerge.merged(
            [snapshot(scope: "acme / Manifold", sprint: "Sprint 63")],
            organizations: ["acme"], targetCount: 1, failures: []
        )

        XCTAssertEqual(merged.scope, "acme / Manifold")
        XCTAssertEqual(merged.sprint, "Sprint 63")
    }

    func testSeveralProjectsInOneOrgShowTheOrg() {
        let merged = TaskBoxMerge.merged(
            [snapshot(scope: "acme / p1"), snapshot(scope: "acme / p2")],
            organizations: ["acme", "acme"], targetCount: 2, failures: []
        )

        XCTAssertEqual(merged.scope, "acme")
        XCTAssertNil(merged.sprint, "a sprint belongs to one project")
    }

    func testSeveralOrgsShowTheCount() {
        let merged = TaskBoxMerge.merged(
            [snapshot(scope: "acme / p1"), snapshot(scope: "other / p2")],
            organizations: ["acme", "other"], targetCount: 2, failures: []
        )

        XCTAssertEqual(merged.scope, "2 orgs")
        XCTAssertNil(merged.sprint)
    }

    func testMergedSortsNewestFirstAcrossAccounts() {
        let merged = TaskBoxMerge.merged(
            [
                snapshot(scope: "acme", tasks: [task("1", changed: 10, org: "acme")]),
                snapshot(scope: "other", tasks: [task("2", changed: 20, org: "other")]),
            ],
            organizations: ["acme", "other"], targetCount: 2, failures: []
        )

        XCTAssertEqual(merged.tasks.map(\.id), ["2", "1"])
    }

    func testMergedJoinsNotesAndNamesAFailedAccount() {
        let merged = TaskBoxMerge.merged(
            [snapshot(scope: "acme", note: "p2: couldn't reach Azure")],
            organizations: ["acme", "other"], targetCount: 2,
            failures: [AzureAccountFailure(name: "other", outcome: .unreachable)]
        )

        let note = merged.note ?? ""
        XCTAssertTrue(note.contains("p2"), "the per-project note survives")
        XCTAssertTrue(note.contains("other"), "the failed account is named")
        XCTAssertTrue(note.contains(" · "), "the two lines are joined")
    }

    func testMergedNoteIsNilWhenNothingFailed() {
        let merged = TaskBoxMerge.merged(
            [snapshot(scope: "acme")], organizations: ["acme"], targetCount: 1, failures: []
        )

        XCTAssertNil(merged.note)
    }

    // MARK: - Merging PR totals

    func testMergedPRTotalsSumAndOrTheCappedFlag() {
        let merged = PRRoleTotals.merged(
            [
                PRRoleTotals(authoredTotal: 2, reviewingTotal: 1, authoredCapped: true,
                             reviewingCapped: false, items: []),
                PRRoleTotals(authoredTotal: 3, reviewingTotal: 4, authoredCapped: false,
                             reviewingCapped: true, items: []),
            ],
            failures: []
        )

        XCTAssertEqual(merged.authoredTotal, 5)
        XCTAssertEqual(merged.reviewingTotal, 5)
        XCTAssertTrue(merged.authoredCapped)
        XCTAssertTrue(merged.reviewingCapped)
    }

    func testMergedPRTotalsConcatenateItems() {
        let merged = PRRoleTotals.merged(
            [
                PRRoleTotals(authoredTotal: 1, reviewingTotal: 0, authoredCapped: false,
                             reviewingCapped: false, items: [pr("acme", repo: "api", number: 1)]),
                PRRoleTotals(authoredTotal: 1, reviewingTotal: 0, authoredCapped: false,
                             reviewingCapped: false, items: [pr("other", repo: "api", number: 1)]),
            ],
            failures: []
        )

        XCTAssertEqual(merged.items.count, 2)
    }

    // MARK: - Row identity across orgs

    func testTwoOrgsWithTheSameRepoAndNumberKeepDistinctRows() {
        // The multi-project bug, one level up: two orgs each have an `api` repo
        // and a PR #12, and without the org in the dedupe key one row vanishes.
        let rows = PRFormatting.deduped([
            pr("acme", repo: "api", number: 12),
            pr("other", repo: "api", number: 12),
        ])

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
    }

    func testTheRoleFoldStillCollapsesTheSameOrgProjectRepoAndNumber() {
        let rows = PRFormatting.deduped([
            pr("acme", repo: "api", number: 12, role: .reviewing, project: "p"),
            pr("acme", repo: "api", number: 12, role: .authored, project: "p"),
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.role, .authored, "authored wins")
    }

    // MARK: - The org-qualified row label

    func testProjectLabelIsBareWithOneOrg() {
        XCTAssertEqual(
            TaskFormatting.projectLabel(task("1", changed: 0, org: "acme", project: "p1"), multipleOrgs: false),
            "p1"
        )
    }

    func testProjectLabelIsOrgQualifiedWhenRowsSpanOrgs() {
        XCTAssertEqual(
            TaskFormatting.projectLabel(task("1", changed: 0, org: "acme", project: "p1"), multipleOrgs: true),
            "acme/p1"
        )
    }

    func testProjectLabelIsNilWhenTheRowNamesNoProject() {
        XCTAssertNil(TaskFormatting.projectLabel(task("1", changed: 0), multipleOrgs: true))
    }

    func testSpansMultipleOrgsDetectsTwoOrgs() {
        XCTAssertTrue(TaskFormatting.spansMultipleOrgs([
            task("1", changed: 0, org: "acme"), task("2", changed: 0, org: "other"),
        ]))
        XCTAssertFalse(TaskFormatting.spansMultipleOrgs([
            task("1", changed: 0, org: "acme"), task("2", changed: 0, org: "acme"),
        ]))
        XCTAssertFalse(TaskFormatting.spansMultipleOrgs([task("1", changed: 0, org: "acme")]))
    }

    func testPRProjectLabelIsOrgQualifiedWhenRowsSpanOrgs() {
        XCTAssertEqual(
            PRFormatting.projectLabel(pr("acme", repo: "api", number: 1, project: "p1"), multipleOrgs: true),
            "acme/p1"
        )
    }

    // MARK: - The new field is additive and tolerant

    func testATaskWithoutAnOrganizationDecodesToNil() throws {
        let json = #"{"id":"1","title":"t","state":"New","itemType":"Task","url":"https://x","provider":"azureDevOps"}"#
        let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertNil(item.organization)
    }

    func testANilOrganizationIsNotEncoded() throws {
        // A single-org slot must not gain the key on every row.
        let text = String(decoding: try JSONEncoder().encode(task("1", changed: 0)), as: UTF8.self)
        XCTAssertFalse(text.contains("\"organization\""))
    }

    func testAPullRequestWithoutAnOrganizationDecodesToNil() throws {
        let json = #"{"id":"github:a/b#1","number":1,"title":"t","role":"authored","createdAt":0}"#
        let item = try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8))
        XCTAssertNil(item.organization)
    }
}
