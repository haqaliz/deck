import XCTest

// Searching by work-item type: `bug login`, `pbi checkout`, `epic payments`.
// A backlog item is a Product Backlog Item in Scrum, a User Story in Agile and
// a Requirement in CMMI, so the filter names a *category*, never a type name
// that only one process template has.

final class WorkItemKindPrefixTests: XCTestCase {
    func testEachTypePrefixScopesToWorkItemsWithItsKind() {
        let cases: [(String, WorkItemKind)] = [
            ("bug login", .bug), ("pbi checkout", .backlog), ("backlog checkout", .backlog),
            ("story checkout", .backlog), ("epic payments", .epic), ("feature search", .feature),
            ("task 4521", .task), ("wi login", .any),
        ]
        for (raw, kind) in cases {
            let q = SpotlightQuery.parse(raw)
            XCTAssertEqual(q.scope, .task, raw)
            XCTAssertEqual(q.workItemKind, kind, raw)
            XCTAssertFalse(q.text.isEmpty, raw)
        }
    }

    func testThePrefixIsRemovedFromTheText() {
        XCTAssertEqual(SpotlightQuery.parse("bug login fails").text, "login fails")
        XCTAssertEqual(SpotlightQuery.parse("PBI Checkout").text, "Checkout")
    }

    /// Like every prefix: only as the first word, and only once followed by a space.
    func testTheSameRulesAsEveryOtherPrefix() {
        XCTAssertNil(SpotlightQuery.parse("bug").scope)
        XCTAssertNil(SpotlightQuery.parse("bugs login").scope)
        XCTAssertNil(SpotlightQuery.parse("fix bug login").scope)
        XCTAssertEqual(SpotlightQuery.parse("bug ").scope, .task)
        XCTAssertTrue(SpotlightQuery.parse("bug ").isEmpty)
    }

    func testUnscopedQueriesHaveNoKind() {
        XCTAssertNil(SpotlightQuery.parse("login").workItemKind)
        XCTAssertNil(SpotlightQuery.parse("port 3000").workItemKind)
        XCTAssertNil(SpotlightQuery.parse("clip bug").workItemKind, "a local prefix must not pick up a type")
    }

    func testTheOtherPrefixesAreUnchanged() {
        XCTAssertEqual(SpotlightQuery.parse("clip foo").scope, .clip)
        XCTAssertEqual(SpotlightQuery.parse("port 8080").scope, .port)
        XCTAssertEqual(SpotlightQuery.parse("time tokyo").scope, .time)
        XCTAssertEqual(SpotlightQuery.parse("oc refactor").scope, .oc)
    }

    func testEveryTypeButAnyHasACategory() {
        XCTAssertEqual(WorkItemKind.bug.category, "Microsoft.BugCategory")
        XCTAssertEqual(WorkItemKind.backlog.category, "Microsoft.RequirementCategory")
        XCTAssertEqual(WorkItemKind.epic.category, "Microsoft.EpicCategory")
        XCTAssertEqual(WorkItemKind.feature.category, "Microsoft.FeatureCategory")
        XCTAssertEqual(WorkItemKind.task.category, "Microsoft.TaskCategory")
        XCTAssertNil(WorkItemKind.any.category)
    }

    func testPrefixesDoNotCollide() {
        let all = WorkItemKind.allCases.flatMap(\.prefixes)
        XCTAssertEqual(all.count, Set(all).count)
        // …and none shadows a local source's prefix.
        for p in all { XCTAssertNil(SearchProviderID.localCases.first { $0.rawValue == p }, p) }
    }
}

/// The condition with every `'…'` literal (and its `''` escapes) removed: what
/// is left is the part typed text must not be able to change.
private func outsideLiterals(_ condition: String) -> String {
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

final class TaskSearchKindConditionTests: XCTestCase {
    func testNoKindIsUnchanged() throws {
        XCTAssertEqual(
            try XCTUnwrap(TaskSearch.condition(for: "login", kind: nil)),
            try XCTUnwrap(TaskSearch.condition(for: "login")))
        XCTAssertEqual(
            try XCTUnwrap(TaskSearch.condition(for: "login", kind: .any)),
            try XCTUnwrap(TaskSearch.condition(for: "login")))
    }

    func testAKindAddsOneCategoryClauseAndKeepsTheTextGrouped() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: "login", kind: .bug))
        XCTAssertEqual(c, "([System.Title] CONTAINS 'login' OR [System.Tags] CONTAINS 'login') "
            + "AND [System.WorkItemType] IN GROUP 'Microsoft.BugCategory'")
    }

    /// With an id clause present the grouping matters most: without the
    /// parentheses `OR [System.Id] = 7` would escape the type filter.
    func testTheIDClauseStaysInsideTheTypeFilter() throws {
        let c = try XCTUnwrap(TaskSearch.condition(for: "4521", kind: .task))
        XCTAssertTrue(c.hasPrefix("([System.Title] CONTAINS '4521'"))
        XCTAssertTrue(c.contains("OR [System.Id] = 4521) AND [System.WorkItemType] IN GROUP 'Microsoft.TaskCategory'"))
    }

    func testEveryKindValidatesAndKeepsTheProjectClause() throws {
        for kind in WorkItemKind.allCases {
            let c = try XCTUnwrap(TaskSearch.condition(for: "login", kind: kind))
            XCTAssertNil(WiqlClause.validate(c), "\(kind)")
            let q = WiqlClause.query(for: c)
            XCTAssertEqual(q.components(separatedBy: "[System.TeamProject] = @project").count - 1, 1, "\(kind)")
            XCTAssertFalse(q.contains("@Me"))
        }
    }

    /// The type comes from a fixed table, never from what was typed: hostile
    /// text must not be able to change the category or add a second clause.
    func testHostileTextCannotChangeTheTypeFilterEither() throws {
        let hostile = ["') OR ([System.Id] > 0", "' OR 1=1 --", "]", ")", "''", "bug", "IN GROUP 'x'",
                       "Microsoft.EpicCategory", "a'b'c"]
        for kind in WorkItemKind.allCases where kind.category != nil {
            for text in hostile {
                guard let c = TaskSearch.condition(for: "ab \(text) cd", kind: kind) else {
                    XCTFail("\(text)"); continue
                }
                XCTAssertNil(WiqlClause.validate(c), "\(kind) \(text) -> \(c)")
                // Typed text may *contain* "IN GROUP" — inside its literal, where it
                // is just text. Outside the literals there must be exactly one.
                XCTAssertEqual(outsideLiterals(c).components(separatedBy: "IN GROUP").count - 1, 1,
                               "\(kind) \(text) -> \(c)")
                XCTAssertTrue(c.hasSuffix("AND [System.WorkItemType] IN GROUP '\(kind.category!)'"),
                              "\(kind) \(text) -> \(c)")
            }
        }
    }
}

final class SearchExamplesTests: XCTestCase {
    func testEverySourceHasSeveralExamples() {
        for provider in SearchProviderID.allCases {
            XCTAssertGreaterThanOrEqual(provider.examples.count, 3, "\(provider)")
        }
    }

    /// An example that does not do what the settings page says is worse than none.
    func testEveryExampleScopesToItsOwnSourceWithSomethingToFind() {
        for provider in SearchProviderID.allCases {
            for example in provider.examples {
                let q = SpotlightQuery.parse(example.query)
                XCTAssertFalse(q.isEmpty, "\(provider): \(example.query) has nothing to search for")
                XCTAssertFalse(example.summary.isEmpty, "\(provider): \(example.query)")
                if example.query.split(separator: " ").count > 1, provider != .task || q.scope != nil {
                    XCTAssertEqual(q.scope, provider, "\(provider): \(example.query)")
                }
            }
        }
    }

    func testNoSourceRepeatsAnExample() {
        for provider in SearchProviderID.allCases {
            let queries = provider.examples.map(\.query)
            XCTAssertEqual(queries.count, Set(queries).count, "\(provider)")
        }
    }

    func testTheHeadlineExampleIsTheFirstOne() {
        for provider in SearchProviderID.allCases {
            XCTAssertEqual(provider.exampleQuery, provider.examples.first?.query)
        }
    }

    func testWorkItemExamplesCoverEveryTypeAndAnIDAndATag() {
        let parsed = SearchProviderID.task.examples.map { SpotlightQuery.parse($0.query) }
        for kind in WorkItemKind.allCases {
            XCTAssertTrue(parsed.contains { $0.workItemKind == kind }, "no example for \(kind)")
        }
        XCTAssertTrue(SearchProviderID.task.examples.contains { $0.summary.lowercased().contains("tag") })
        XCTAssertTrue(parsed.contains { $0.text.allSatisfy(\.isNumber) }, "no id example")
    }

    /// The clock example must find something on a fresh install, like the first one.
    func testEveryClockExampleFindsACity() {
        for example in SearchProviderID.time.examples {
            let q = SpotlightQuery.parse(example.query)
            XCTAssertFalse(ClockSearch.results(query: q.text, configuredIDs: [], now: Date(), reference: .current).isEmpty,
                           example.query)
        }
    }

    func testTheWorkItemSourceIsNamedForWhatItSearches() {
        XCTAssertEqual(SearchProviderID.task.settingsTitle, "Work items")
        XCTAssertEqual(SearchProviderID.task.sectionTitle, "Work items")
        XCTAssertTrue(SearchProviderID.task.exampleSummary.contains("dev.azure.com"))
    }
}
