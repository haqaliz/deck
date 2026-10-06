import XCTest

/// The team picker's discovery. The payload shape is the one this org answered
/// on 2026-10-07 (probe F1/F3): `value[]` rows carrying `name` and
/// `projectName`, ids and urls stripped here.
final class AzureTeamsParserTests: XCTestCase {
    func testReadsTheTeamNamesSortedForAStablePicker() {
        let data = Data(#"{"count":2,"value":[{"name":"Zulu Team"},{"name":"alpha team"}]}"#.utf8)
        XCTAssertEqual(AzureTeamsParser.parse(data), ["alpha team", "Zulu Team"])
    }

    func testAnEmptyListIsARealAnswer() {
        XCTAssertEqual(AzureTeamsParser.parse(Data(#"{"count":0,"value":[]}"#.utf8)), [])
    }

    func testAMalformedPayloadIsNil() {
        XCTAssertNil(AzureTeamsParser.parse(Data("not json".utf8)))
        XCTAssertNil(AzureTeamsParser.parse(Data(#"{"count":1}"#.utf8)))
    }

    func testARowWithoutANameIsSkippedRatherThanFailingTheList() {
        XCTAssertEqual(
            AzureTeamsParser.parse(Data(#"{"value":[{"id":"1"},{"name":" A "}]}"#.utf8)),
            ["A"]
        )
    }
}
