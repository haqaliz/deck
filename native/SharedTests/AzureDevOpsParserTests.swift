import XCTest

// Azure DevOps payload parsing. Every fixture here is SYNTHETIC — hand-written
// to the documented shape, never a captured response. Real payloads carry work
// item titles, iteration paths and the PAT owner's name from a private org and
// must not enter this repo (PRD §9 R1).

// MARK: - Target normalisation

final class AzureTargetTests: XCTestCase {
    private func target(_ org: String, _ project: String) throws -> AzureTarget {
        try AzureTarget.normalise(organization: org, project: project)
    }

    func testBareOrganizationName() throws {
        let t = try target("Manifold", "Manifold")
        XCTAssertEqual(t.orgBase, "https://dev.azure.com/Manifold")
        XCTAssertEqual(t.projectBase, "https://dev.azure.com/Manifold/Manifold")
    }

    func testFullURLResolvesToTheSameBase() throws {
        XCTAssertEqual(
            try target("https://dev.azure.com/Manifold", "Manifold").orgBase,
            "https://dev.azure.com/Manifold"
        )
    }

    func testTrailingSlashResolvesToTheSameBase() throws {
        XCTAssertEqual(
            try target("https://dev.azure.com/Manifold/", "Manifold").orgBase,
            "https://dev.azure.com/Manifold"
        )
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        XCTAssertEqual(try target("  Manifold  ", " Manifold ").orgBase, "https://dev.azure.com/Manifold")
    }

    /// A project name with a space must produce a valid URL, not a malformed
    /// one that would surface as "unexpected response" and blame the server for
    /// a client bug.
    func testProjectNameWithASpaceIsPercentEncoded() throws {
        XCTAssertEqual(
            try target("Contoso", "My Project").projectBase,
            "https://dev.azure.com/Contoso/My%20Project"
        )
    }

    func testOrganizationNameWithASpaceIsPercentEncoded() throws {
        XCTAssertEqual(try target("My Org", "P").orgBase, "https://dev.azure.com/My%20Org")
    }

    // Scope is the header text, and uses the RAW names — the user reads their
    // project name, not a percent-encoded path segment.
    func testScopeIsJustTheProjectWhenNamesMatch() throws {
        XCTAssertEqual(try target("Manifold", "Manifold").scope, "Manifold")
    }

    func testScopeNamesBothWhenTheyDiffer() throws {
        XCTAssertEqual(try target("Contoso", "My Project").scope, "Contoso / My Project")
    }

    func testEmptyOrganizationThrows() {
        XCTAssertThrowsError(try target("", "Manifold"))
    }

    func testEmptyProjectThrows() {
        XCTAssertThrowsError(try target("Manifold", ""))
    }

    func testWhitespaceOnlyThrows() {
        XCTAssertThrowsError(try target("   ", "Manifold"))
    }
}

// MARK: - WIQL id parsing

final class WiqlIdParserTests: XCTestCase {
    func testExtractsIdsInPayloadOrder() {
        let json = """
        {"queryType":"flat","workItems":[{"id":42,"url":"x"},{"id":7,"url":"y"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(WiqlIdParser.parse(json)?.ids, [42, 7])
    }

    /// "Nothing assigned" is a success, not a failure — an empty list must be
    /// [] so the caller writes an empty snapshot rather than treating it as a
    /// parse error.
    func testEmptyWorkItemsIsEmptyNotNil() {
        let json = #"{"queryType":"flat","workItems":[]}"#.data(using: .utf8)!
        XCTAssertEqual(WiqlIdParser.parse(json)?.ids, [])
        XCTAssertEqual(WiqlIdParser.parse(json)?.total, 0)
    }

    func testCapsIdsPreservingOrder() {
        let entries = (1...260).map { #"{"id":\#($0),"url":"x"}"# }.joined(separator: ",")
        let json = "{\"workItems\":[\(entries)]}".data(using: .utf8)!
        let parsed = WiqlIdParser.parse(json)
        XCTAssertEqual(parsed?.ids.count, WiqlIdParser.idLimit)
        XCTAssertEqual(parsed?.ids.first, 1)
        XCTAssertEqual(parsed?.ids.last, WiqlIdParser.idLimit)
    }

    /// The header count must describe everything assigned to you, not just the
    /// rows that survived the batch cap.
    func testTotalCountsEveryMatchNotJustTheCappedIds() {
        let entries = (1...260).map { #"{"id":\#($0),"url":"x"}"# }.joined(separator: ",")
        let json = "{\"workItems\":[\(entries)]}".data(using: .utf8)!
        XCTAssertEqual(WiqlIdParser.parse(json)?.total, 260)
    }

    func testMalformedJSONIsNil() {
        XCTAssertNil(WiqlIdParser.parse(Data("not json".utf8)))
    }

    func testMissingWorkItemsKeyIsNil() {
        XCTAssertNil(WiqlIdParser.parse(Data(#"{"queryType":"flat"}"#.utf8)))
    }
}

// MARK: - Current sprint

final class CurrentSprintParserTests: XCTestCase {
    func testReadsTheCurrentIterationName() {
        let json = """
        {"count":1,"value":[
          {"id":"a","name":"Sprint 57","path":"ForesightManifold\\\\Sprint 57",
           "attributes":{"startDate":"2026-07-27T00:00:00Z","finishDate":"2026-08-24T00:00:00Z","timeFrame":"current"}}
        ]}
        """.data(using: .utf8)!
        XCTAssertEqual(CurrentSprintParser.parse(json), "Sprint 57")
    }

    /// A team between sprints has no current iteration — the header simply
    /// shows nothing rather than a stale or invented sprint.
    func testEmptyValueIsNil() {
        XCTAssertNil(CurrentSprintParser.parse(Data(#"{"count":0,"value":[]}"#.utf8)))
    }

    func testEntryWithoutANameIsNil() {
        XCTAssertNil(CurrentSprintParser.parse(Data(#"{"value":[{"id":"a"}]}"#.utf8)))
    }

    /// Best-effort, like every optional decoration on the face.
    func testMalformedJSONIsNil() {
        XCTAssertNil(CurrentSprintParser.parse(Data("nope".utf8)))
    }

    func testFallsBackToTheLeafOfThePathWhenNameIsAbsent() {
        let json = #"{"value":[{"path":"ForesightManifold\\Sprint 60"}]}"#.data(using: .utf8)!
        XCTAssertEqual(CurrentSprintParser.parse(json), "Sprint 60")
    }
}

// MARK: - Work item batch

final class WorkItemParserTests: XCTestCase {
    private var target: AzureTarget {
        try! AzureTarget.normalise(organization: "Contoso", project: "My Project")
    }

    private func parse(_ json: String) -> [TaskItem]? {
        WorkItemParser.parse(Data(json.utf8), target: target)
    }

    func testParsesAFullItem() throws {
        let items = parse("""
        {"count":1,"value":[{"id":42,"fields":{
          "System.Id":42,
          "System.Title":"Widget alignment spike",
          "System.State":"Active",
          "System.WorkItemType":"Bug",
          "System.IterationPath":"Contoso\\\\Sprint 42",
          "System.ChangedDate":"2026-08-20T09:15:00Z",
          "Microsoft.VSTS.Scheduling.DueDate":"2026-08-24T00:00:00Z"
        }}]}
        """)
        let item = try XCTUnwrap(items?.first)
        XCTAssertEqual(item.id, "42")
        XCTAssertEqual(item.title, "Widget alignment spike")
        XCTAssertEqual(item.state, "Active")
        XCTAssertEqual(item.itemType, "Bug")
        XCTAssertEqual(item.provider, .azureDevOps)
        XCTAssertEqual(item.changedAt, Date(timeIntervalSince1970: 1_787_217_300))
    }

    /// The batch payload's own `url` is the API endpoint. The stored url must be
    /// the browsable one, and the project segment must stay encoded.
    func testBuildsTheHumanURLRatherThanUsingThePayloadURL() throws {
        let items = parse("""
        {"value":[{"id":42,"url":"https://dev.azure.com/Contoso/_apis/wit/workItems/42",
          "fields":{"System.Title":"T","System.State":"Active","System.WorkItemType":"Task"}}]}
        """)
        XCTAssertEqual(
            try XCTUnwrap(items?.first).url,
            "https://dev.azure.com/Contoso/My%20Project/_workitems/edit/42"
        )
    }



    /// An item without a title is not a task — dropping is honest, defaulting
    /// to "Untitled" would put a phantom row on the face.
    func testItemWithoutATitleIsDropped() {
        let items = parse("""
        {"value":[
          {"id":1,"fields":{"System.State":"New","System.WorkItemType":"Task"}},
          {"id":2,"fields":{"System.Title":"Kept","System.State":"New","System.WorkItemType":"Task"}}
        ]}
        """)
        XCTAssertEqual(items?.map(\.title), ["Kept"])
    }

    func testItemWithoutAFieldsObjectIsDropped() {
        let items = parse(#"{"value":[{"id":1},{"id":2,"fields":{"System.Title":"Kept"}}]}"#)
        XCTAssertEqual(items?.map(\.title), ["Kept"])
    }

    func testUnknownExtraFieldsAreIgnored() throws {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New",
          "System.WorkItemType":"Task","Custom.SomeFutureField":{"nested":true}}}]}
        """)
        XCTAssertEqual(items?.count, 1)
    }

    func testEmptyValueIsEmptyNotNil() {
        XCTAssertEqual(parse(#"{"count":0,"value":[]}"#)?.count, 0)
    }

    func testMalformedJSONIsNil() {
        XCTAssertNil(parse("not json"))
    }

    func testMissingValueKeyIsNil() {
        XCTAssertNil(parse(#"{"count":0}"#))
    }

    // Azure DevOps is inconsistent about fractional seconds across fields, and
    // system fields can carry seven digits.




    // Azure DevOps is inconsistent about fractional seconds across fields, and
    // system fields can carry seven digits — more than ISO8601DateFormatter
    // accepts on its own.
    func testParsesChangedDateWithoutFractionalSeconds() {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "System.ChangedDate":"2026-08-20T09:15:00Z"}}]}
        """)
        XCTAssertEqual(items?.first?.changedAt, Date(timeIntervalSince1970: 1_787_217_300))
    }

    func testParsesChangedDateWithMillisecondPrecision() {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "System.ChangedDate":"2026-08-20T09:15:00.000Z"}}]}
        """)
        XCTAssertEqual(items?.first?.changedAt, Date(timeIntervalSince1970: 1_787_217_300))
    }

    func testParsesChangedDateWithSevenDigitFractionalSeconds() {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "System.ChangedDate":"2026-08-20T09:15:00.0000000Z"}}]}
        """)
        XCTAssertEqual(
            items?.first?.changedAt, Date(timeIntervalSince1970: 1_787_217_300),
            "Azure DevOps system fields return seven fractional digits"
        )
    }

    func testAnUnparseableChangedDateLeavesTheRowIntact() {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "System.ChangedDate":"recently"}}]}
        """)
        XCTAssertEqual(items?.count, 1, "a bad date must not cost the whole row")
        XCTAssertNil(items?.first?.changedAt)
    }

    /// State is stored raw and mapped at render time, so a renamed process
    /// state is a settings edit rather than a rebuild.
    func testStateIsStoredRaw() {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"Committed","System.WorkItemType":"Product Backlog Item"}}]}
        """)
        XCTAssertEqual(items?.first?.state, "Committed")
        XCTAssertEqual(items?.first?.itemType, "Product Backlog Item")
    }
}
