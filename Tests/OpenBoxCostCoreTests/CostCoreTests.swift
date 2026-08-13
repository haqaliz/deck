import XCTest
@testable import OpenBoxCostCore

final class CostRowsTests: XCTestCase {
    func testEmptyRowsMapToEmpty() {
        XCTAssertEqual(CostRows.mapRows([]), [])
    }

    func testDropsRowsMissingDayOrModel() {
        let rows: [[String: Any]] = [
            ["day": "2026-08-08", "model": "m1", "cost": 1.0],
            ["model": "m2", "cost": 2.0],
            ["day": "2026-08-08", "cost": 3.0],
        ]
        XCTAssertEqual(CostRows.mapRows(rows), [CostDay(day: "2026-08-08", model: "m1", cost: 1.0)])
    }

    func testMissingCostReadsAsZero() {
        let rows: [[String: Any]] = [
            ["day": "2026-08-08", "model": "m1"],
            ["day": "2026-08-08", "model": "m2", "cost": NSNumber(value: 0.5)],
        ]
        XCTAssertEqual(CostRows.mapRows(rows), [
            CostDay(day: "2026-08-08", model: "m2", cost: 0.5),
            CostDay(day: "2026-08-08", model: "m1", cost: 0),
        ])
    }

    func testSortedByDayAscCostDesc() {
        let rows: [[String: Any]] = [
            ["day": "2026-08-09", "model": "a", "cost": 0.5],
            ["day": "2026-08-07", "model": "b", "cost": 2.0],
            ["day": "2026-08-07", "model": "c", "cost": 3.0],
        ]
        XCTAssertEqual(CostRows.mapRows(rows), [
            CostDay(day: "2026-08-07", model: "c", cost: 3.0),
            CostDay(day: "2026-08-07", model: "b", cost: 2.0),
            CostDay(day: "2026-08-09", model: "a", cost: 0.5),
        ])
    }
}

final class CostSeriesDailyTests: XCTestCase {
    func testEmptyDictMapsToEmpty() {
        XCTAssertEqual(CostSeries.daily(fromDayModelCosts: [:]), [])
    }

    func testFlattensAndSorts() {
        let input = [
            "2026-08-08": ["qwen": 0.0288, "deepseek": 1.6465],
            "2026-08-07": ["r1": 0.0136],
        ]
        XCTAssertEqual(CostSeries.daily(fromDayModelCosts: input), [
            CostDay(day: "2026-08-07", model: "r1", cost: 0.0136),
            CostDay(day: "2026-08-08", model: "deepseek", cost: 1.6465),
            CostDay(day: "2026-08-08", model: "qwen", cost: 0.0288),
        ])
    }
}

final class CostSeriesBuilderTests: XCTestCase {
    func testEmptyInput() {
        XCTAssertEqual(CostSeries.buildSeries(from: []), [])
    }

    func testSingleModelOneValuePerDay() {
        let days = [
            CostDay(day: "2026-08-08", model: "deepseek", cost: 1.6465),
            CostDay(day: "2026-08-09", model: "deepseek", cost: 2.4801),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "deepseek", costs: [1.6465, 2.4801]),
        ])
    }

    func testTopThreePlusOtherMergesRemainder() {
        let days = [
            CostDay(day: "2026-08-08", model: "a", cost: 4.0),
            CostDay(day: "2026-08-08", model: "b", cost: 3.0),
            CostDay(day: "2026-08-08", model: "c", cost: 2.0),
            CostDay(day: "2026-08-08", model: "d", cost: 1.5),
            CostDay(day: "2026-08-08", model: "e", cost: 0.5),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "a", costs: [4.0]),
            CostSeries.Series(model: "b", costs: [3.0]),
            CostSeries.Series(model: "c", costs: [2.0]),
            CostSeries.Series(model: "other", costs: [2.0]),
        ])
    }

    func testTopNZeroMergesEverything() {
        let days = [
            CostDay(day: "2026-08-08", model: "a", cost: 1.0),
            CostDay(day: "2026-08-08", model: "b", cost: 2.0),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days, topN: 0), [
            CostSeries.Series(model: "other", costs: [3.0]),
        ])
    }

    func testTieKeepsFirstAppearanceOrder() {
        let days = [
            CostDay(day: "2026-08-07", model: "b", cost: 1.0),
            CostDay(day: "2026-08-08", model: "a", cost: 1.0),
        ]
        let series = CostSeries.buildSeries(from: days, topN: 1)
        XCTAssertEqual(series.map(\.model), ["b", "other"])
        XCTAssertEqual(series[0].costs, [1.0, 0.0])
        XCTAssertEqual(series[1].costs, [0.0, 1.0])
    }

    func testZeroCostDaysRenderAsEmptySlots() {
        let days = [
            CostDay(day: "2026-08-07", model: "a", cost: 0),
            CostDay(day: "2026-08-08", model: "a", cost: 2.0),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "a", costs: [0.0, 2.0]),
        ])
    }

    func testOtherMergesPerDay() {
        let days = [
            CostDay(day: "2026-08-08", model: "a", cost: 4.0),
            CostDay(day: "2026-08-08", model: "b", cost: 3.0),
            CostDay(day: "2026-08-08", model: "c", cost: 2.0),
            CostDay(day: "2026-08-08", model: "d", cost: 1.5),
            CostDay(day: "2026-08-09", model: "a", cost: 1.0),
            CostDay(day: "2026-08-09", model: "e", cost: 0.5),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "a", costs: [4.0, 1.0]),
            CostSeries.Series(model: "b", costs: [3.0, 0.0]),
            CostSeries.Series(model: "c", costs: [2.0, 0.0]),
            CostSeries.Series(model: "other", costs: [1.5, 0.5]),
        ])
    }
}

final class CostSeriesDisplayIDTests: XCTestCase {
    func testJSONObjectResolvesToID() {
        let raw = #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#
        XCTAssertEqual(CostSeries.displayID(of: raw), "deepseek-v4-flash")
    }

    func testSlashSegmentsResolveToLast() {
        XCTAssertEqual(CostSeries.displayID(of: "opencode-go/deepseek-v4-flash"), "deepseek-v4-flash")
    }

    func testPlainStringPassesThrough() {
        XCTAssertEqual(CostSeries.displayID(of: "plain"), "plain")
    }
}

final class CostSeriesLiveParityTests: XCTestCase {
    /// Fixture from the Phase-2 query on the live DB (2026-08-14): the 14-day
    /// cost rows with real model strings, summed per model.
    func testFixtureMatchesExpectedSeries() {
        let rows: [[String: Any]] = [
            ["day": "2026-08-07", "model": #"{"id":"deepseek/deepseek-r1","providerID":"openrouter"}"#, "cost": 0.0136],
            ["day": "2026-08-08", "model": #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, "cost": 1.6465],
            ["day": "2026-08-08", "model": #"{"id":"qwen/qwen3.8-max","providerID":"openrouter","variant":"xhigh"}"#, "cost": 0.0288],
            ["day": "2026-08-09", "model": #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, "cost": 2.4801],
            ["day": "2026-08-10", "model": #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, "cost": 0.0707],
            ["day": "2026-08-11", "model": #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, "cost": 0.403],
            ["day": "2026-08-12", "model": #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, "cost": 1.5077],
            ["day": "2026-08-13", "model": #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, "cost": 0.0685],
        ]
        let costDays = CostRows.mapRows(rows)
        let series = CostSeries.buildSeries(from: costDays)

        XCTAssertEqual(series.map { CostSeries.displayID(of: $0.model) }, ["deepseek-v4-flash", "qwen/qwen3.8-max", "deepseek/deepseek-r1"])
        XCTAssertEqual(series[0].costs, [0.0, 1.6465, 2.4801, 0.0707, 0.403, 1.5077, 0.0685])
        XCTAssertEqual(series[0].costs.reduce(0, +), 6.1765, accuracy: 0.0001)
        XCTAssertEqual(series[1].costs, [0.0, 0.0288, 0.0, 0.0, 0.0, 0.0, 0.0])
        XCTAssertEqual(series[2].costs, [0.0136, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    }
}
