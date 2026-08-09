import XCTest
@testable import OpenBoxCore

final class FormatterTests: XCTestCase {
    func testFormatTokensBelowThousand() {
        XCTAssertEqual(OpenCodeFormatters.formatTokens(999), "999")
    }

    func testFormatTokensThousands() {
        XCTAssertEqual(OpenCodeFormatters.formatTokens(1_500), "1.5K")
    }

    func testFormatTokensMillions() {
        XCTAssertEqual(OpenCodeFormatters.formatTokens(2_400_000), "2.4M")
    }

    func testFormatCostTwoDecimals() {
        XCTAssertEqual(OpenCodeFormatters.formatCost(1.234), "$1.23")
    }

    func testShortDayDropsYear() {
        XCTAssertEqual(OpenCodeFormatters.shortDay("2026-08-09"), "08-09")
    }
}
