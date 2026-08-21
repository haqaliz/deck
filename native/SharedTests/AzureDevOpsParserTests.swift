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
        XCTAssertEqual(WiqlIdParser.parse(json), [42, 7])
    }

    /// "Nothing assigned" is a success, not a failure — an empty list must be
    /// [] so the caller writes an empty snapshot rather than treating it as a
    /// parse error.
    func testEmptyWorkItemsIsEmptyNotNil() {
        let json = #"{"queryType":"flat","workItems":[]}"#.data(using: .utf8)!
        XCTAssertEqual(WiqlIdParser.parse(json), [])
    }

    func testCapsAtFiftyPreservingOrder() {
        let entries = (1...80).map { #"{"id":\#($0),"url":"x"}"# }.joined(separator: ",")
        let json = "{\"workItems\":[\(entries)]}".data(using: .utf8)!
        let ids = WiqlIdParser.parse(json)
        XCTAssertEqual(ids?.count, 50)
        XCTAssertEqual(ids?.first, 1)
        XCTAssertEqual(ids?.last, 50)
    }

    func testMalformedJSONIsNil() {
        XCTAssertNil(WiqlIdParser.parse(Data("not json".utf8)))
    }

    func testMissingWorkItemsKeyIsNil() {
        XCTAssertNil(WiqlIdParser.parse(Data(#"{"queryType":"flat"}"#.utf8)))
    }
}

// MARK: - Iteration calendar

final class IterationMapParserTests: XCTestCase {
    func testMapsPathToFinishDate() {
        let json = """
        {"count":1,"value":[
          {"id":"a","name":"Sprint 42","path":"Contoso\\\\Sprint 42",
           "attributes":{"startDate":"2026-08-10T00:00:00Z","finishDate":"2026-08-24T00:00:00Z"}}
        ]}
        """.data(using: .utf8)!
        let map = IterationMapParser.parse(json)
        XCTAssertEqual(map["Contoso\\Sprint 42"], Date(timeIntervalSince1970: 1_787_529_600))
    }

    func testEntryWithoutAttributesIsSkippedNotFatal() {
        let json = """
        {"value":[
          {"path":"A\\\\One"},
          {"path":"A\\\\Two","attributes":{"finishDate":"2026-08-24T00:00:00Z"}}
        ]}
        """.data(using: .utf8)!
        let map = IterationMapParser.parse(json)
        XCTAssertNil(map["A\\One"])
        XCTAssertNotNil(map["A\\Two"], "one bad entry must not lose the good ones")
    }

    func testNullFinishDateIsSkipped() {
        let json = #"{"value":[{"path":"A\\One","attributes":{"finishDate":null}}]}"#.data(using: .utf8)!
        XCTAssertTrue(IterationMapParser.parse(json).isEmpty)
    }

    /// This parser's failure mode is "no fallback dates", never "fetch failed" —
    /// the sprint calendar is best-effort and must not blank a working list.
    func testMalformedJSONIsAnEmptyMapNotNil() {
        XCTAssertTrue(IterationMapParser.parse(Data("nope".utf8)).isEmpty)
    }
}

// MARK: - Work item batch

final class WorkItemParserTests: XCTestCase {
    private var target: AzureTarget {
        try! AzureTarget.normalise(organization: "Contoso", project: "My Project")
    }

    private func parse(_ json: String, ends: [String: Date] = [:]) -> [TaskItem]? {
        WorkItemParser.parse(Data(json.utf8), target: target, iterationEnds: ends)
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
        XCTAssertEqual(item.dueSource, .explicit)
        XCTAssertEqual(item.dueDate, Date(timeIntervalSince1970: 1_787_529_600))
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

    func testFallsBackToTargetDateThenIteration() throws {
        let items = parse("""
        {"value":[
          {"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
            "Microsoft.VSTS.Scheduling.TargetDate":"2026-08-24T00:00:00Z"}},
          {"id":2,"fields":{"System.Title":"B","System.State":"New","System.WorkItemType":"Task",
            "System.IterationPath":"Contoso\\\\Sprint 42"}}
        ]}
        """, ends: ["Contoso\\Sprint 42": Date(timeIntervalSince1970: 1_787_529_600)])
        XCTAssertEqual(items?[0].dueSource, .target)
        XCTAssertEqual(items?[1].dueSource, .iteration)
        XCTAssertEqual(items?[1].dueDate, Date(timeIntervalSince1970: 1_787_529_600))
    }

    func testItemWithNoResolvableDateIsUndated() throws {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task"}}]}
        """)
        XCTAssertNil(try XCTUnwrap(items?.first).dueDate)
        XCTAssertEqual(items?.first?.dueSource, .unset)
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
    func testParsesDatesWithoutFractionalSeconds() throws {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "Microsoft.VSTS.Scheduling.DueDate":"2026-08-24T00:00:00Z"}}]}
        """)
        XCTAssertEqual(items?.first?.dueDate, Date(timeIntervalSince1970: 1_787_529_600))
    }

    func testParsesDatesWithMillisecondPrecision() throws {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "Microsoft.VSTS.Scheduling.DueDate":"2026-08-24T00:00:00.000Z"}}]}
        """)
        XCTAssertEqual(items?.first?.dueDate, Date(timeIntervalSince1970: 1_787_529_600))
    }

    func testParsesDatesWithSevenDigitFractionalSeconds() throws {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "Microsoft.VSTS.Scheduling.DueDate":"2026-08-24T00:00:00.0000000Z"}}]}
        """)
        XCTAssertEqual(
            items?.first?.dueDate, Date(timeIntervalSince1970: 1_787_529_600),
            "Azure DevOps system fields return seven fractional digits"
        )
    }

    func testAnUnparseableDateLeavesTheItemUndatedRatherThanDroppingIt() throws {
        let items = parse("""
        {"value":[{"id":1,"fields":{"System.Title":"A","System.State":"New","System.WorkItemType":"Task",
          "Microsoft.VSTS.Scheduling.DueDate":"soon-ish"}}]}
        """)
        XCTAssertEqual(items?.count, 1, "a bad date must not cost the whole row")
        XCTAssertNil(items?.first?.dueDate)
    }
}
