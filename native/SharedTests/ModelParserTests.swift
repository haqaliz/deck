import XCTest

// Fresh suite: ModelParser + OpenCodeFormatters never had scratch tests
// (the roadmap names them — ROADMAP.md:53). Written from behavior.

final class ModelParserTests: XCTestCase {
    func testJSONObjectModelString() {
        let parsed = ModelParser.parse(#"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#)
        XCTAssertEqual(parsed.provider, "opencode-go")
        XCTAssertEqual(parsed.id, "deepseek-v4-flash")
        XCTAssertEqual(parsed.variant, "max")
    }

    func testJSONObjectWithSlashInID() {
        let parsed = ModelParser.parse(#"{"id":"deepseek/deepseek-r1","providerID":"openrouter"}"#)
        XCTAssertEqual(parsed.provider, "openrouter · deepseek")
        XCTAssertEqual(parsed.id, "deepseek-r1")
        XCTAssertNil(parsed.variant)
    }

    func testJSONObjectWithoutProviderFallsBackToLocal() {
        let parsed = ModelParser.parse(#"{"id":"plain-model"}"#)
        XCTAssertEqual(parsed.provider, "local")
        XCTAssertEqual(parsed.id, "plain-model")
        XCTAssertNil(parsed.variant)
    }

    func testProviderSlashIDVariantString() {
        // All trailing variant words are stripped: "flash" and "max" are both
        // variant keywords, so "v4-flash-max" → id "deepseek-v4". (Real DB
        // models are JSON objects, which take the JSON branch above.)
        let parsed = ModelParser.parse("opencode-go/deepseek-v4-flash-max")
        XCTAssertEqual(parsed.provider, "opencode-go")
        XCTAssertEqual(parsed.id, "deepseek-v4")
        XCTAssertEqual(parsed.variant, "flash max")
    }

    func testProviderColonModelVariantString() {
        let parsed = ModelParser.parse("provider:model-mini")
        XCTAssertEqual(parsed.provider, "provider")
        XCTAssertEqual(parsed.id, "model")
        XCTAssertEqual(parsed.variant, "mini")
    }

    func testPlainStringDefaultsToLocal() {
        let parsed = ModelParser.parse("plain")
        XCTAssertEqual(parsed.provider, "local")
        XCTAssertEqual(parsed.id, "plain")
        XCTAssertNil(parsed.variant)
    }

    func testEmbeddedVariantIsExtracted() {
        let parsed = ModelParser.parse("deepseek-max-v4")
        XCTAssertEqual(parsed.id, "deepseek-v4")
        XCTAssertEqual(parsed.variant, "max")
    }

    func testMultipleTrailingVariantsJoinWithSpace() {
        let parsed = ModelParser.parse("x-large-mini")
        XCTAssertEqual(parsed.id, "x")
        XCTAssertEqual(parsed.variant, "large mini")
    }

    func testVariantKeywordInsideWordIsNotStripped() {
        let parsed = ModelParser.parse("maximizer")
        XCTAssertEqual(parsed.id, "maximizer")
        XCTAssertNil(parsed.variant)
    }
}

final class OpenCodeFormattersTests: XCTestCase {
    func testFormatTokensGrouping() {
        XCTAssertEqual(OpenCodeFormatters.formatTokens(0), "0")
        XCTAssertEqual(OpenCodeFormatters.formatTokens(500), "500")
        XCTAssertEqual(OpenCodeFormatters.formatTokens(1_500), "1.5K")
        XCTAssertEqual(OpenCodeFormatters.formatTokens(12_345), "12.3K")
        XCTAssertEqual(OpenCodeFormatters.formatTokens(1_200_000), "1.2M")
        XCTAssertEqual(OpenCodeFormatters.formatTokens(2_500_000_000), "2.50B")
    }

    func testFormatCost() {
        XCTAssertEqual(OpenCodeFormatters.formatCost(0), "$0.00")
        XCTAssertEqual(OpenCodeFormatters.formatCost(1.2345), "$1.23")
        XCTAssertEqual(OpenCodeFormatters.formatCost(123.456), "$123.46")
    }
}
