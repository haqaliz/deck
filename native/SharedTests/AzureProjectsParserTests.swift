import XCTest

/// Discovery for the settings window's project pickers.
///
/// The fixture is the payload this org actually returned on 2026-08-28 (ids and
/// urls stripped, one synthetic half-created project appended), not a
/// hand-written guess at the documented shape.
final class AzureProjectsParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "missing fixture \(name).json"))
    }

    func testReadsTheProjectNamesSortedForAStablePicker() throws {
        // Sorted by name, not by the API's own order and not by recency: a
        // picker that reshuffles between openings is the MarketBox lesson.
        XCTAssertEqual(
            AzureProjectsParser.parse(try fixture("azure_projects")),
            [
                "ForesightDevops",
                "ForesightManifold",
                "InfraSturcture",
                "MachineLearning",
                "Manifold Ops",
                "Playground",
            ]
        )
    }

    func testSkipsAProjectThatIsNotWellFormed() throws {
        // A project mid-creation or mid-deletion cannot be queried, and
        // offering it would produce a slot that fails every tick.
        let names = try XCTUnwrap(AzureProjectsParser.parse(try fixture("azure_projects")))
        XCTAssertFalse(names.contains("HalfCreated"))
    }

    func testAnEmptyListIsARealAnswer() {
        // Distinct from a failure: an account whose PAT can see no project
        // should say so, not fall back to a text field as though it never asked.
        XCTAssertEqual(AzureProjectsParser.parse(Data(#"{"count":0,"value":[]}"#.utf8)), [])
    }

    func testAMalformedPayloadIsNil() {
        XCTAssertNil(AzureProjectsParser.parse(Data("not json".utf8)))
        XCTAssertNil(AzureProjectsParser.parse(Data(#"{"count":1}"#.utf8)))
    }

    func testARowWithoutANameIsSkippedRatherThanFailingTheList() {
        let data = Data(#"{"value":[{"state":"wellFormed"},{"name":"A","state":"wellFormed"}]}"#.utf8)
        XCTAssertEqual(AzureProjectsParser.parse(data), ["A"])
    }

    func testARowWithoutAStateIsKept() {
        // Absent is not the same as "not well formed"; only an explicit
        // non-wellFormed state excludes a project.
        XCTAssertEqual(AzureProjectsParser.parse(Data(#"{"value":[{"name":"A"}]}"#.utf8)), ["A"])
    }
}
