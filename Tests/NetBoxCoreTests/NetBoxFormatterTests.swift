import XCTest
@testable import NetBoxCore

final class NetBoxFormatterTests: XCTestCase {
    func testFormatZero() {
        XCTAssertEqual(NetBoxFormatters.formatRate(0), "0 B/s")
    }

    func testFormatBytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(512), "512 B/s")
    }

    func testFormatKilobytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_234), "1.2 KB/s")
    }

    func testFormatKilobyteBoundary() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_000), "1.0 KB/s")
    }

    func testFormatMegabytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_234_567), "1.2 MB/s")
    }

    func testFormatGigabytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_234_567_890), "1.2 GB/s")
    }
}
