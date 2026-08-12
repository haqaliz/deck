import XCTest
@testable import DevBoxCore

final class FormatterTests: XCTestCase {

    func testPortLabelFormatsWildcard() {
        XCTAssertEqual(Formatters.portLabel(host: "*", port: 7000), "*:7000")
    }

    func testPortLabelFormatsIpv4() {
        XCTAssertEqual(Formatters.portLabel(host: "127.0.0.1", port: 6379), "127.0.0.1:6379")
    }

    func testPortLabelFormatsIpv6Brackets() {
        XCTAssertEqual(Formatters.portLabel(host: "[::1]", port: 8080), "[::1]:8080")
    }

    func testPercentStringFormatsNilAsEmDash() {
        XCTAssertEqual(Formatters.percentString(nil), "—")
    }

    func testPercentStringRoundsToOneDecimal() {
        XCTAssertEqual(Formatters.percentString(2.312), "2.3%")
        XCTAssertEqual(Formatters.percentString(0), "0.0%")
        XCTAssertEqual(Formatters.percentString(1.0), "1.0%")
    }
}
