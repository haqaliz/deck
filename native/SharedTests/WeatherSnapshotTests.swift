import XCTest

// Ported from the HomeBoxCore scratch package (989999a) against the merged
// WttrParser/WeatherIcon in Shared. The fixture is the live
// amsterdam_j1.json wttr.in payload captured during the HomeBox build.

final class WttrParserTests: XCTestCase {
    private var fixture: Data {
        let url = Bundle(for: Self.self).url(forResource: "amsterdam_j1", withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    func testParsesLiveFixtureIntoWeather() {
        let parsed = WttrParser.parse(fixture)
        XCTAssertNotNil(parsed)
        let weather = parsed!
        XCTAssertEqual(weather.location, "De Wallen")
        XCTAssertEqual(weather.country, "Netherlands")
        XCTAssertEqual(weather.current.tempC, 23)
        XCTAssertEqual(weather.current.code, 113)
        XCTAssertEqual(weather.current.desc, "Clear")
        XCTAssertEqual(weather.current.feelsLikeC, 21)
        XCTAssertEqual(weather.current.humidity, 40)
        XCTAssertEqual(weather.days.count, 3)
        XCTAssertEqual(weather.days[0].date, "2026-08-13")
        XCTAssertEqual(weather.days[0].maxTempC, 34)
        XCTAssertEqual(weather.days[0].minTempC, 17)
    }

    func testTrimsTrailingWhitespaceFromDescriptions() {
        let weather = WttrParser.parse(fixture)!
        XCTAssertFalse(weather.current.desc.hasSuffix(" "))
        XCTAssertFalse(weather.current.desc.hasPrefix(" "))
        for day in weather.days {
            XCTAssertFalse(day.desc.hasSuffix(" "))
        }
    }

    func testParsesMinimalPayloadWithMissingFieldsAsNil() {
        let json = """
        {"current_condition":[{"temp_C":"21"}],"nearest_area":[{"areaName":[{"value":"X"}],"country":[{"value":"Y"}]}],"weather":[]}
        """
        let weather = WttrParser.parse(json.data(using: .utf8)!)
        XCTAssertNotNil(weather)
        XCTAssertEqual(weather?.location, "X")
        XCTAssertEqual(weather?.current.tempC, 21)
        XCTAssertNil(weather?.current.tempF)
        XCTAssertNil(weather?.current.code)
        XCTAssertEqual(weather?.current.desc, "")
        XCTAssertTrue(weather?.days.isEmpty == true)
    }

    func testReturnsNilForGarbageData() {
        XCTAssertNil(WttrParser.parse(Data("not json".utf8)))
        XCTAssertNil(WttrParser.parse(Data("{\"x\": 1}".utf8)))
    }

    func testParsesImperialFieldsAlongsideMetric() {
        let weather = WttrParser.parse(fixture)!
        XCTAssertEqual(weather.current.tempF, 73)
        XCTAssertEqual(weather.current.feelsLikeF, 70)
        XCTAssertEqual(weather.days[0].maxTempF, 93)
        XCTAssertEqual(weather.days[0].minTempF, 63)
    }

    func testNonNumericTemperatureBecomesNil() {
        let json = """
        {"current_condition":[{"temp_C":"warm","FeelsLikeC":"","weatherCode":"113"}],"nearest_area":[],"weather":[]}
        """
        let weather = WttrParser.parse(json.data(using: .utf8)!)
        XCTAssertNotNil(weather)
        XCTAssertNil(weather?.current.tempC)
        XCTAssertNil(weather?.current.feelsLikeC)
        XCTAssertEqual(weather?.current.code, 113)
    }
}

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
