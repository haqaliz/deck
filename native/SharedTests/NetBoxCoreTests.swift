import XCTest

private let en0 = InterfaceRates(name: "en0", up: 1_200_000, down: 3_400_000)
private let en1 = InterfaceRates(name: "en1", up: 80_000, down: 210_000)
private let en2 = InterfaceRates(name: "en2", up: 0, down: 0)

final class NetBoxPinnedInterfaceTests: XCTestCase {
    private let interfaces = [en0, en1, en2]

    func testNilPinLeavesInterfacesUnchanged() {
        XCTAssertEqual(NetBoxPinnedInterface.select(pinned: nil, interfaces: interfaces), interfaces)
    }

    func testEmptyStringPinLeavesInterfacesUnchanged() {
        XCTAssertEqual(NetBoxPinnedInterface.select(pinned: "", interfaces: interfaces), interfaces)
    }

    func testPresentPinFiltersToThatInterface() {
        XCTAssertEqual(NetBoxPinnedInterface.select(pinned: "en1", interfaces: interfaces), [en1])
    }

    func testAbsentPinFallsBackToAllInterfaces() {
        XCTAssertEqual(NetBoxPinnedInterface.select(pinned: "en9", interfaces: interfaces), interfaces)
    }

    func testPinWithEmptyInterfacesReturnsEmpty() {
        XCTAssertEqual(NetBoxPinnedInterface.select(pinned: "en0", interfaces: []), [])
    }
}

final class NetBoxFormatRateTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(0), "0 B/s")
        XCTAssertEqual(NetBoxFormatters.formatRate(512), "512 B/s")
    }

    func testKilobytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_000), "1.0 KB/s")
        XCTAssertEqual(NetBoxFormatters.formatRate(12_345), "12.3 KB/s")
    }

    func testMegabytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_000_000), "1.0 MB/s")
        XCTAssertEqual(NetBoxFormatters.formatRate(3_400_000), "3.4 MB/s")
    }

    func testGigabytes() {
        XCTAssertEqual(NetBoxFormatters.formatRate(1_000_000_000), "1.0 GB/s")
        XCTAssertEqual(NetBoxFormatters.formatRate(2_500_000_000), "2.5 GB/s")
    }

    func testNegativeValueClampsToZero() {
        XCTAssertEqual(NetBoxFormatters.formatRate(-100), "0 B/s")
    }

    func testRoundsDownUnderThreshold() {
        XCTAssertEqual(NetBoxFormatters.formatRate(999), "999 B/s")
        XCTAssertEqual(NetBoxFormatters.formatRate(999_900), "999.9 KB/s")
    }
}
