import XCTest
@testable import OpenBoxCore

final class ModelParserTests: XCTestCase {
    func testParsesProviderSlashIDDashVariant() {
        let parsed = ModelParser.parse("opencode-go/deepseek-v4-flash-max")
        XCTAssertEqual(parsed.provider, "opencode-go")
        XCTAssertEqual(parsed.id, "deepseek-v4")
        XCTAssertEqual(parsed.variant, "flash max")
    }

    func testParsesPlainModelWithoutVariant() {
        let parsed = ModelParser.parse("anthropic/claude-sonnet")
        XCTAssertEqual(parsed.provider, "anthropic")
        XCTAssertEqual(parsed.id, "claude")
        XCTAssertEqual(parsed.variant, "sonnet")
    }

    func testParsesJSONModelObject() {
        let json = #"{"id":"deepseek-v4-flash-max","providerID":"opencode-go","variant":"flash max"}"#
        let parsed = ModelParser.parse(json)
        XCTAssertEqual(parsed.provider, "opencode-go")
        XCTAssertEqual(parsed.id, "deepseek-v4-flash-max")
        XCTAssertEqual(parsed.variant, "flash max")
    }

    func testParsesColonFallback() {
        let parsed = ModelParser.parse("openai:gpt-4o")
        XCTAssertEqual(parsed.provider, "openai")
        XCTAssertEqual(parsed.id, "gpt-4o")
        XCTAssertNil(parsed.variant)
    }

    func testParsesNoSlashAsLocal() {
        let parsed = ModelParser.parse("deepseek-v4-flash-max")
        XCTAssertEqual(parsed.provider, "local")
        XCTAssertEqual(parsed.id, "deepseek-v4")
        XCTAssertEqual(parsed.variant, "flash max")
    }
}
