import XCTest

// Typed text becomes part of a WIQL query, which is the dangerous direction:
// CLAUDE.md records a condition that closed its own parentheses, dropped the
// project clause and returned 7559 items from every project with a 200. The
// search text is therefore only ever a *literal*, and these tests prove the
// shape of the query does not depend on what was typed.

final class TaskSearchConditionTests: XCTestCase {
    /// Removes every `'…'` literal (with `''` as the escaped quote), leaving
    /// the skeleton of the condition. If typed text could escape its literal,
    /// the skeleton would change.
    private func skeleton(_ condition: String) -> String {
        var out = ""
        var inLiteral = false
        let chars = Array(condition)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inLiteral {
                if c == "'" {
                    if i + 1 < chars.count, chars[i + 1] == "'" { i += 1 } else { inLiteral = false }
                }
            } else if c == "'" {
                inLiteral = true
            } else {
                out.append(c)
            }
            i += 1
        }
        return out
    }

    private let textSkeleton = "[System.Title] CONTAINS  OR [System.Tags] CONTAINS "

    func testAPlainTermSearchesTitleAndTags() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: "login bug"))
        XCTAssertEqual(c, "[System.Title] CONTAINS 'login bug' OR [System.Tags] CONTAINS 'login bug'")
    }

    func testANumberAlsoSearchesById() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: "4521"))
        XCTAssertTrue(c.hasSuffix(" OR [System.Id] = 4521"))
        XCTAssertTrue(c.contains("[System.Title] CONTAINS '4521'"))
    }

    func testOnlyAWholeNumberIsAnId() throws {
        XCTAssertFalse(try XCTUnwrap(TaskSearch.condition(for: "45a21")).contains("[System.Id]"))
        XCTAssertFalse(try XCTUnwrap(TaskSearch.condition(for: "-12")).contains("[System.Id]"))
        // Too long to be a work item id: stays a text search, never an Int overflow.
        XCTAssertFalse(try XCTUnwrap(TaskSearch.condition(for: "99999999999999999999")).contains("[System.Id]"))
    }

    func testTooShortSearchesNothing() {
        XCTAssertNil(TaskSearch.condition(for: ""))
        XCTAssertNil(TaskSearch.condition(for: "  a "))
    }

    func testAQuoteIsDoubled() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: "it's"))
        XCTAssertTrue(c.contains("'it''s'"))
    }

    func testWhitespaceAndControlCharactersAreNormalised() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: "  login \n\t bug\u{0}  "))
        XCTAssertTrue(c.contains("'login bug'"))
    }

    func testTextIsCapped() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: String(repeating: "a", count: 4000)))
        XCTAssertLessThan(c.count, 400)
        XCTAssertNil(WiqlClause.validate(c))
    }

    /// The point of the file: whatever is typed, the condition outside the
    /// literals is the same fixed skeleton, validates, and sits inside the
    /// project clause of the real query.
    func testHostileTextCannotChangeTheShapeOfTheQuery() throws {
        let hostile = [
            "') OR ([System.Id] > 0",
            "' OR 1=1 --",
            "'; DROP",
            "]",
            "[System.State]",
            ")",
            "))) OR (((",
            "''",
            "'",
            "\\'",
            "ORDER BY [System.Id]",
            "SELECT [System.Id] FROM WorkItems",
            "ASOF '2020-01-01'",
            "MODE (MustContain)",
            "100% 'real' [x] (y)",
            "ünïcödé 日本語 😀",
            "a'b'c'd''e'''f",
        ]
        // Each string as typed, and wrapped in ordinary text, so the one-character
        // ones (which are correctly too short to send) still exercise escaping.
        let attempts = hostile + hostile.map { "ab \($0) cd" } + hostile.map { "\($0)\($0)" }
        for text in attempts {
            guard let condition = TaskSearch.condition(for: text) else {
                // Nothing sent is the safe answer, and only legitimate when
                // there is genuinely too little to search for.
                XCTAssertFalse(RemoteSearchPolicy.shouldSearch(TaskSearch.sanitise(text)),
                               "\(text) produced no condition although it is long enough")
                continue
            }
            XCTAssertNil(WiqlClause.validate(condition), "\(text) -> \(condition)")
            XCTAssertEqual(skeleton(condition), textSkeleton, "\(text) escaped its literal: \(condition)")

            let query = WiqlClause.query(for: condition)
            XCTAssertEqual(
                query.components(separatedBy: "[System.TeamProject] = @project").count - 1, 1,
                "\(text) disturbed the project clause")
            XCTAssertTrue(query.hasPrefix("SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND ("))
            XCTAssertTrue(query.hasSuffix(") ORDER BY [System.ChangedDate] DESC"))
        }
    }

    func testASingleCharacterIsTooShortToSend() {
        for text in ["'", ")", "]", "[", "%"] {
            XCTAssertNil(TaskSearch.condition(for: text), text)
        }
    }

    func testTheSkeletonCheckItselfCatchesAnEscape() {
        // Control: prove `skeleton` would notice the failure the tests guard
        // against, so a green run means something.
        let broken = "[System.Title] CONTAINS 'x') OR ([System.Id] > 0 OR ('y' OR [System.Tags] CONTAINS 'z'"
        XCTAssertNotEqual(skeleton(broken), textSkeleton)
    }
}

final class TaskItemTagsTests: XCTestCase {
    private var target: AzureTarget {
        try! AzureTarget.normalise(organization: "Contoso", project: "Web")
    }

    func testTagsAreSplitAndTrimmed() throws {
        let json = #"{"value":[{"id":7,"fields":{"System.Title":"T","System.Tags":"alpha; beta ;gamma","System.TeamProject":"Web"}}]}"#
        let items = try XCTUnwrap(WorkItemParser.parse(Data(json.utf8), target: target))
        XCTAssertEqual(items.first?.tags, ["alpha", "beta", "gamma"])
    }

    func testNoTagsFieldMeansNoTags() throws {
        let json = #"{"value":[{"id":7,"fields":{"System.Title":"T"}}]}"#
        let items = try XCTUnwrap(WorkItemParser.parse(Data(json.utf8), target: target))
        XCTAssertEqual(items.first?.tags, [])
    }

    func testEmptyTagSegmentsAreDropped() throws {
        let json = #"{"value":[{"id":7,"fields":{"System.Title":"T","System.Tags":"a;; ;b"}}]}"#
        let items = try XCTUnwrap(WorkItemParser.parse(Data(json.utf8), target: target))
        XCTAssertEqual(items.first?.tags, ["a", "b"])
    }

    /// A `taskbox.json` written before tags existed must still decode, or the
    /// widget would render an empty list until the agent next ran.
    func testAnOldTaskItemWithoutTagsStillDecodes() throws {
        let old = #"{"id":"9","title":"Old","state":"Active","itemType":"Bug","url":"https://dev.azure.com/o/p/_workitems/edit/9","provider":"azureDevOps"}"#
        let item = try JSONDecoder().decode(TaskItem.self, from: Data(old.utf8))
        XCTAssertEqual(item.tags, [])
        XCTAssertEqual(item.title, "Old")
    }

    func testTagsRoundTrip() throws {
        let item = TaskItem(id: "1", title: "T", state: "", itemType: "", url: "",
                            provider: .azureDevOps, changedAt: nil, tags: ["x", "y"])
        let back = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.tags, ["x", "y"])
    }

    /// The batch must actually ask for the field, or tags are always empty.
    func testTheBatchRequestsTheTagsField() {
        XCTAssertTrue(HostAzureDevOpsLoader.batchFields.contains("System.Tags"))
        // …and kept every field the widget already depends on.
        for field in ["System.Id", "System.Title", "System.State", "System.WorkItemType",
                      "System.ChangedDate", "System.TeamProject"] {
            XCTAssertTrue(HostAzureDevOpsLoader.batchFields.contains(field), field)
        }
    }
}

final class TaskSearchRequestTests: XCTestCase {
    private var target: AzureTarget {
        try! AzureTarget.normalise(organization: "Contoso", project: "Web")
    }

    /// A broad search must stay small: an uncapped condition measured 577 KB
    /// and up to 17.8 s against a 10 s timeout (CLAUDE.md). Search asks for far
    /// fewer than the widget does, and always sends `$top`.
    func testSearchSendsASmallTop() throws {
        let url = try XCTUnwrap(WiqlResponse.url(target: target, top: HostAzureDevOpsLoader.searchLimit + 1))
        XCTAssertTrue(url.absoluteString.contains("$top=26"), url.absoluteString)
        XCTAssertLessThan(HostAzureDevOpsLoader.searchLimit, WiqlIdParser.idLimit)
    }

    func testTheWidgetsOwnURLIsUnchanged() throws {
        let url = try XCTUnwrap(WiqlResponse.url(target: target))
        XCTAssertTrue(url.absoluteString.hasSuffix("&$top=\(WiqlIdParser.requestTop)"))
    }

    /// Search is read-only against the WIQL endpoint and must never reuse the
    /// widget's assignee/state filter.
    func testTheSearchQueryHasNoAssigneeOrStateFilter() throws {
        let query = WiqlClause.query(for: try XCTUnwrap(TaskSearch.condition(for: "login")))
        XCTAssertFalse(query.contains("@Me"))
        XCTAssertFalse(query.contains("System.State"))
        XCTAssertFalse(query.contains("AssignedTo"))
    }
}
