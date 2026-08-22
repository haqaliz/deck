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

// MARK: - Active interface selection

final class NetBoxActiveInterfaceTests: XCTestCase {
    private func rate(_ name: String, up: Double = 0, down: Double = 0) -> InterfaceRates {
        InterfaceRates(name: name, up: up, down: down)
    }

    /// The bug this fixes: with every rate at 0 the old "sort by max(up,down)"
    /// was an all-ties sort, so ACTIVE showed whatever getifaddrs happened to
    /// return first — en4, a dead Thunderbolt bridge — while en0 carried the
    /// traffic.
    func testLiveLinkWinsWhenAllRatesAreZero() {
        let picked = NetBoxActiveInterface.select(
            rates: [rate("en4"), rate("en5"), rate("en0")],
            live: ["en0"]
        )
        XCTAssertEqual(picked?.name, "en0")
    }

    func testBusiestLiveInterfaceWinsAmongSeveral() {
        let picked = NetBoxActiveInterface.select(
            rates: [rate("en0", down: 1_000), rate("en1", down: 50_000)],
            live: ["en0", "en1"]
        )
        XCTAssertEqual(picked?.name, "en1")
    }

    /// A live-but-idle link still beats a dead link that happens to show a
    /// stale non-zero counter delta.
    func testLiveIdleBeatsDeadBusy() {
        let picked = NetBoxActiveInterface.select(
            rates: [rate("en4", down: 99_999), rate("en0")],
            live: ["en0"]
        )
        XCTAssertEqual(picked?.name, "en0")
    }

    /// Nothing live: fall back to traffic rather than showing no ACTIVE row.
    func testFallsBackToBusiestWhenNothingIsLive() {
        let picked = NetBoxActiveInterface.select(
            rates: [rate("en4", down: 10), rate("en5", down: 900)],
            live: []
        )
        XCTAssertEqual(picked?.name, "en5")
    }

    func testEmptyInputYieldsNil() {
        XCTAssertNil(NetBoxActiveInterface.select(rates: [], live: ["en0"]))
    }

    /// Ordering the whole list, not just picking one: the interfaces section
    /// uses the same rule so both faces agree.
    func testSortedPutsLiveFirstThenByTraffic() {
        let sorted = NetBoxActiveInterface.sorted(
            rates: [rate("en5"), rate("en0", down: 100), rate("en4", down: 5_000), rate("en1", down: 20)],
            live: ["en0", "en1"]
        )
        XCTAssertEqual(sorted.map(\.name), ["en0", "en1", "en4", "en5"])
    }
}
