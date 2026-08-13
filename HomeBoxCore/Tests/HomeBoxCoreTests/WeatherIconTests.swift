import XCTest
@testable import HomeBoxCore

final class WeatherIconTests: XCTestCase {
    func testMapsCommonCodes() {
        XCTAssertEqual(WeatherIcon.symbol(for: 113), "sun.max")
        XCTAssertEqual(WeatherIcon.symbol(for: 116), "cloud.sun")
        XCTAssertEqual(WeatherIcon.symbol(for: 119), "cloud")
        XCTAssertEqual(WeatherIcon.symbol(for: 176), "cloud.drizzle")
        XCTAssertEqual(WeatherIcon.symbol(for: 200), "cloud.bolt.rain")
        XCTAssertEqual(WeatherIcon.symbol(for: 395), "cloud.bolt.snow.fill")
        XCTAssertEqual(WeatherIcon.symbol(for: 353), "cloud.sun.rain")
    }

    func testUnknownCodeFallsBackToCloud() {
        XCTAssertEqual(WeatherIcon.symbol(for: 999), "cloud")
        XCTAssertEqual(WeatherIcon.symbol(for: -1), "cloud")
    }

    func testNilCodeFallsBackToCloud() {
        XCTAssertEqual(WeatherIcon.symbol(for: nil), "cloud")
    }
}
