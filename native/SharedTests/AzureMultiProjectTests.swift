import XCTest

/// One Azure account fanning out over several projects.
///
/// Three of these pin bugs that only appear with more than one project, and
/// that no single-project test could have caught: a merged batch attributing
/// every row to one project, one busy project starving the others out of the
/// id budget, and the org's real project names — one of which contains a
/// space — going through URL construction.
final class AzureMultiProjectTests: XCTestCase {

    // MARK: - Targets

    func testOneTargetPerProject() throws {
        let targets = try AzureTargets.normalise(
            organization: "ForesightAnalytics",
            projects: ["ForesightManifold", "Manifold Ops"]
        )

        XCTAssertEqual(targets.map(\.projectName), ["ForesightManifold", "Manifold Ops"])
        // A real project in this org has a space in it; the encoded segment is
        // what reaches the URL.
        XCTAssertEqual(targets[1].projectSegment, "Manifold%20Ops")
        XCTAssertEqual(
            targets[1].projectBase,
            "https://dev.azure.com/ForesightAnalytics/Manifold%20Ops"
        )
    }

    func testNoProjectsIsAnInvalidTarget() {
        XCTAssertThrowsError(
            try AzureTargets.normalise(organization: "acme", projects: [])
        ) { error in
            XCTAssertEqual(error as? AzureDevOpsError, .invalidTarget)
        }
    }

    func testTargetsAreNormalisedLikeEverythingElse() throws {
        let targets = try AzureTargets.normalise(
            organization: "acme", projects: [" One ", "one", "", "Two"]
        )
        XCTAssertEqual(targets.map(\.projectName), ["One", "Two"])
    }

    // MARK: - Merging ids into one org-scoped batch

    func testInterleaveTakesFromEveryProjectInTurn() {
        XCTAssertEqual(
            AzureIDMerge.interleave([[1, 2, 3, 4], [5], [6, 7]], limit: 200),
            [1, 5, 6, 2, 7, 3, 4]
        )
    }

    func testTruncationDoesNotStarveAQuietProject() {
        // Naive concatenation would spend the whole 200-id budget on the first
        // project. This is the per-repo fair share ShipBox left open, done here
        // because with three busy projects it is not a nicety.
        let lists = [
            Array(1...150),
            Array(1001...1150),
            Array(2001...2150),
        ]

        let merged = AzureIDMerge.interleave(lists, limit: 200)

        XCTAssertEqual(merged.count, 200)
        for (index, list) in lists.enumerated() {
            let present = merged.filter { list.contains($0) }.count
            XCTAssertGreaterThan(present, 60, "project \(index) was starved out of the batch")
        }
    }

    func testInterleaveHonoursTheLimit() {
        XCTAssertEqual(AzureIDMerge.interleave([[1, 2, 3]], limit: 2), [1, 2])
        XCTAssertEqual(AzureIDMerge.interleave([], limit: 200), [])
        XCTAssertEqual(AzureIDMerge.interleave([[], []], limit: 200), [])
    }

    // MARK: - Attribution: which project does a row belong to?

    private func target(_ project: String) throws -> AzureTarget {
        try AzureTarget.normalise(organization: "ForesightAnalytics", project: project)
    }

    func testARowIsAttributedToItsOwnProjectNotTheQueriedOne() throws {
        // The batch endpoint is organization-scoped, so one call carries rows
        // from every project. Without System.TeamProject every row would deep
        // link into whichever project happened to be passed in.
        let json = """
        {"value":[
          {"id":1,"fields":{"System.Title":"A","System.TeamProject":"Manifold Ops"}},
          {"id":2,"fields":{"System.Title":"B","System.TeamProject":"ForesightManifold"}}
        ]}
        """

        let items = try XCTUnwrap(
            WorkItemParser.parse(Data(json.utf8), target: try target("ForesightManifold"))
        )

        XCTAssertEqual(items.map(\.project), ["Manifold Ops", "ForesightManifold"])
        XCTAssertEqual(
            items[0].url,
            "https://dev.azure.com/ForesightAnalytics/Manifold%20Ops/_workitems/edit/1"
        )
        XCTAssertEqual(
            items[1].url,
            "https://dev.azure.com/ForesightAnalytics/ForesightManifold/_workitems/edit/2"
        )
    }

    func testARowWithoutTheFieldFallsBackToTheQueriedProject() throws {
        let json = """
        {"value":[{"id":7,"fields":{"System.Title":"A"}}]}
        """

        let items = try XCTUnwrap(
            WorkItemParser.parse(Data(json.utf8), target: try target("ForesightManifold"))
        )

        XCTAssertNil(items[0].project)
        XCTAssertEqual(
            items[0].url,
            "https://dev.azure.com/ForesightAnalytics/ForesightManifold/_workitems/edit/7"
        )
    }

    // MARK: - Header

    func testOneProjectKeepsTodaysHeaderExactly() throws {
        XCTAssertEqual(
            TaskBoxScope.scope(organization: "ForesightAnalytics", targets: [try target("ForesightManifold")]),
            "ForesightAnalytics / ForesightManifold"
        )
    }

    func testSeveralProjectsShowTheOrganization() throws {
        // "current sprint" is per project+team, so the sprint chip goes away
        // with more than one project rather than silently meaning one of them.
        XCTAssertEqual(
            TaskBoxScope.scope(
                organization: "ForesightAnalytics",
                targets: [try target("ForesightManifold"), try target("Manifold Ops")]
            ),
            "ForesightAnalytics"
        )
    }

    // MARK: - Partial failure

    func testOneFailedProjectIsNamedNotSwallowed() {
        XCTAssertEqual(
            AzureProjectNote.compose(
                failures: [.init(project: "Manifold Ops", outcome: .authOrTarget)],
                source: .taskbox
            ),
            "Manifold Ops: check org, project + PAT"
        )
    }

    func testSeveralFailuresSharingAReasonCollapse() {
        let note = AzureProjectNote.compose(
            failures: [
                .init(project: "A", outcome: .unreachable),
                .init(project: "B", outcome: .unreachable),
            ],
            source: .taskbox
        )
        XCTAssertEqual(note, "A + 1 more: can't reach Azure DevOps")
    }

    func testNoFailuresIsNoNote() {
        XCTAssertNil(AzureProjectNote.compose(failures: [], source: .taskbox))
    }

    // MARK: - Snapshot compatibility

    func testTaskItemDecodesWithoutAProject() throws {
        let json = """
        {"id":"1","title":"A","state":"","itemType":"","url":"","provider":"azureDevOps"}
        """
        let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertNil(item.project)
    }

    func testSnapshotDecodesWithoutANote() throws {
        let json = """
        {"writtenAt":0,"scope":"acme","totalCount":0,"tasks":[]}
        """
        let snapshot = try JSONDecoder().decode(TaskBoxSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.note)
    }

    func testSnapshotRoundTripsTheNoteAndProjects() throws {
        let item = TaskItem(
            id: "1", title: "A", state: "New", itemType: "Bug", url: "u",
            provider: .azureDevOps, changedAt: nil, project: "Manifold Ops"
        )
        let snapshot = TaskBoxSnapshot(
            writtenAt: Date(timeIntervalSince1970: 0), scope: "acme", totalCount: 1,
            sprint: nil, tasks: [item], note: "A: can't reach Azure DevOps"
        )

        let decoded = try JSONDecoder().decode(
            TaskBoxSnapshot.self, from: try JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.note, "A: can't reach Azure DevOps")
        XCTAssertEqual(decoded.tasks[0].project, "Manifold Ops")
    }

    // MARK: - PRBox: ids that cannot collide across projects

    private func prJSON(repo: String, number: Int, me: String = "me") -> String {
        """
        {"value":[{
          "pullRequestId": \(number),
          "title": "T",
          "repository": {"name": "\(repo)"},
          "creationDate": "2026-08-20T10:00:00Z",
          "reviewers": [{"id": "\(me)", "vote": 0}]
        }]}
        """
    }

    func testTwoProjectsWithASameNamedRepoProduceDistinctRows() throws {
        // PR numbers are per repo, and a repo name is only unique within its
        // project. Before the project entered the id, `api#12` in two projects
        // was one id — a duplicate ForEach key, and one row silently gone.
        let one = try XCTUnwrap(AzurePRParser.parse(
            Data(prJSON(repo: "api", number: 12).utf8),
            role: .authored, me: "me", target: try target("ForesightManifold")
        ))
        let two = try XCTUnwrap(AzurePRParser.parse(
            Data(prJSON(repo: "api", number: 12).utf8),
            role: .authored, me: "me", target: try target("Manifold Ops")
        ))

        let ids = (one + two).map(\.id)
        XCTAssertEqual(Set(ids).count, 2, "same repo name in two projects collapsed into one row")
        XCTAssertEqual(ids[0], "azureDevOps:ForesightManifold/api#12")
        XCTAssertEqual(ids[1], "azureDevOps:Manifold Ops/api#12")
    }

    func testAPullRequestCarriesItsProjectAndLinksIntoIt() throws {
        let items = try XCTUnwrap(AzurePRParser.parse(
            Data(prJSON(repo: "api", number: 12).utf8),
            role: .authored, me: "me", target: try target("Manifold Ops")
        ))

        XCTAssertEqual(items[0].project, "Manifold Ops")
        XCTAssertEqual(
            items[0].url,
            "https://dev.azure.com/ForesightAnalytics/Manifold%20Ops/_git/api/pullrequest/12"
        )
    }

    func testPullRequestDecodesWithoutAProject() throws {
        let json = """
        {"id":"x","number":1,"title":"T","repo":"api","role":"authored",
         "provider":"azureDevOps","isDraft":false,"createdAt":0,"url":"u"}
        """
        let item = try JSONDecoder().decode(PullRequestItem.self, from: Data(json.utf8))
        XCTAssertNil(item.project)
    }

    func testTheBuilderCarriesAPartialFailureNote() {
        let azure = PRRoleTotals(
            authoredTotal: 1, reviewingTotal: 0, authoredCapped: false,
            reviewingCapped: false, items: [], note: "Manifold Ops: offline"
        )

        let snapshot = PRSnapshotBuilder.build(
            github: nil, azure: azure, cap: 6, now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(snapshot.note, "Manifold Ops: offline")
    }

    func testNoFailuresLeavesTheSnapshotNoteEmpty() {
        let snapshot = PRSnapshotBuilder.build(
            github: .empty, azure: .empty, cap: 6, now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertNil(snapshot.note)
    }

    // MARK: - New settings keys decode tolerantly

    func testTaskBoxKeepsItsSettingsWhenTheNewKeyIsAbsent() throws {
        // Adding a key must never make a pre-existing file decode as defaults:
        // DeckSettings.load() falls back to DeckSettings() on any decode error,
        // which would silently reset every colour, count and account in it.
        let json = """
        {"taskbox":{"taskCount":13,"showLegend":false}}
        """
        let settings = try JSONDecoder().decode(DeckSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.taskbox.taskCount, 13)
        XCTAssertFalse(settings.taskbox.showLegend)
        XCTAssertFalse(settings.taskbox.showProject, "off by default")
    }

    func testPRBoxKeepsItsSettingsWhenTheNewKeyIsAbsent() throws {
        let json = """
        {"prbox":{"prCount":9,"azure":{"organization":"acme"}}}
        """
        let settings = try JSONDecoder().decode(DeckSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.prbox.prCount, 9)
        XCTAssertEqual(settings.prbox.azure.organization, "acme")
        XCTAssertFalse(settings.prbox.azure.showProject, "off by default")
    }

    func testTheTogglesRoundTrip() throws {
        var settings = DeckSettings()
        settings.taskbox.showProject = true
        settings.prbox.azure.showProject = true

        let decoded = try JSONDecoder().decode(
            DeckSettings.self, from: try JSONEncoder().encode(settings)
        )

        XCTAssertTrue(decoded.taskbox.showProject)
        XCTAssertTrue(decoded.prbox.azure.showProject)
    }
}
