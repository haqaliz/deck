import XCTest
@testable import NetBoxCore

final class NetworkMathTests: XCTestCase {
    func testRateSimpleDelta() {
        let r = NetworkMath.rate(previousBytes: 1000, currentBytes: 2000, interval: 1)
        XCTAssertEqual(r.rate, 1000, accuracy: 0.001)
        XCTAssertFalse(r.didReset)
    }

    func testRateDividesByInterval() {
        let r = NetworkMath.rate(previousBytes: 1000, currentBytes: 2000, interval: 2)
        XCTAssertEqual(r.rate, 500, accuracy: 0.001)
    }

    func testRateZeroDelta() {
        let r = NetworkMath.rate(previousBytes: 2000, currentBytes: 2000, interval: 1)
        XCTAssertEqual(r.rate, 0)
        XCTAssertFalse(r.didReset)
    }

    func testRateNegativeDeltaIsReset() {
        let r = NetworkMath.rate(previousBytes: 2000, currentBytes: 1000, interval: 1)
        XCTAssertEqual(r.rate, 0)
        XCTAssertTrue(r.didReset)
    }

    func testRateZeroIntervalDoesNotDivide() {
        let r = NetworkMath.rate(previousBytes: 1000, currentBytes: 2000, interval: 0)
        XCTAssertEqual(r.rate, 0)
    }

    func testRatesCombineDirections() {
        let prev = InterfaceSample(name: "en0", rxBytes: 1000, txBytes: 5000)
        let cur = InterfaceSample(name: "en0", rxBytes: 3000, txBytes: 6000)
        let rates = NetworkMath.rates(previous: prev, current: cur, interval: 1)
        XCTAssertEqual(rates.down, 2000, accuracy: 0.001)
        XCTAssertEqual(rates.up, 1000, accuracy: 0.001)
        XCTAssertEqual(rates.name, "en0")
        XCTAssertFalse(rates.didReset)
    }

    func testRatesPerDirectionReset() {
        let prev = InterfaceSample(name: "en0", rxBytes: 9000, txBytes: 1000)
        let cur = InterfaceSample(name: "en0", rxBytes: 1000, txBytes: 2000)
        let rates = NetworkMath.rates(previous: prev, current: cur, interval: 1)
        XCTAssertEqual(rates.down, 0)
        XCTAssertEqual(rates.up, 1000, accuracy: 0.001)
        XCTAssertTrue(rates.didReset)
    }

    func testMostActiveByMaxDirection() {
        let a = InterfaceRates(name: "en0", up: 10, down: 100, didReset: false)
        let b = InterfaceRates(name: "en5", up: 500, down: 20, didReset: false)
        XCTAssertEqual(NetworkMath.mostActive([a, b])?.name, "en5")
    }

    func testMostActiveEmpty() {
        XCTAssertNil(NetworkMath.mostActive([]))
    }

    func testMostActiveTiePicksFirst() {
        let a = InterfaceRates(name: "en0", up: 100, down: 100, didReset: false)
        let b = InterfaceRates(name: "en5", up: 100, down: 100, didReset: false)
        XCTAssertEqual(NetworkMath.mostActive([a, b])?.name, "en0")
    }
}
