import XCTest

// Ported from the OpenBoxCostCore scratch package (e8e1c11) against the
// CostSeries moved into Shared/OpenBoxCore.swift. The scratch-only helpers
// CostRows.mapRows / CostSeries.daily have no merged equivalent (the CostDay
// mapping lives inline in OpenCodeReader.load and is covered by the SQL suite).

final class CostSeriesBuilderTests: XCTestCase {
    func testEmptyInput() {
        XCTAssertEqual(CostSeries.buildSeries(from: []), [])
    }

    func testSingleModelOneValuePerDay() {
        let days = [
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "deepseek", cost: 1.6465),
            OpenCodeSnapshot.CostDay(day: "2026-08-09", model: "deepseek", cost: 2.4801),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "deepseek", costs: [1.6465, 2.4801]),
        ])
    }

    func testTopThreePlusOtherMergesRemainder() {
        let days = [
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "a", cost: 4.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "b", cost: 3.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "c", cost: 2.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "d", cost: 1.5),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "e", cost: 0.5),
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
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "a", cost: 1.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "b", cost: 2.0),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days, topN: 0), [
            CostSeries.Series(model: "other", costs: [3.0]),
        ])
    }

    func testTieKeepsFirstAppearanceOrder() {
        let days = [
            OpenCodeSnapshot.CostDay(day: "2026-08-07", model: "b", cost: 1.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "a", cost: 1.0),
        ]
        let series = CostSeries.buildSeries(from: days, topN: 1)
        XCTAssertEqual(series.map(\.model), ["b", "other"])
        XCTAssertEqual(series[0].costs, [1.0, 0.0])
        XCTAssertEqual(series[1].costs, [0.0, 1.0])
    }

    func testZeroCostDaysRenderAsEmptySlots() {
        let days = [
            OpenCodeSnapshot.CostDay(day: "2026-08-07", model: "a", cost: 0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "a", cost: 2.0),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "a", costs: [0.0, 2.0]),
        ])
    }

    func testOtherMergesPerDay() {
        let days = [
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "a", cost: 4.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "b", cost: 3.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "c", cost: 2.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: "d", cost: 1.5),
            OpenCodeSnapshot.CostDay(day: "2026-08-09", model: "a", cost: 1.0),
            OpenCodeSnapshot.CostDay(day: "2026-08-09", model: "e", cost: 0.5),
        ]
        XCTAssertEqual(CostSeries.buildSeries(from: days), [
            CostSeries.Series(model: "a", costs: [4.0, 1.0]),
            CostSeries.Series(model: "b", costs: [3.0, 0.0]),
            CostSeries.Series(model: "c", costs: [2.0, 0.0]),
            CostSeries.Series(model: "other", costs: [1.5, 0.5]),
        ])
    }
}

final class CostSeriesPointsTests: XCTestCase {
    func testPointsFlattenSeriesDayAligned() {
        let series = [
            CostSeries.Series(model: "a", costs: [1.0, 2.0]),
            CostSeries.Series(model: "b", costs: [3.0, 4.0]),
        ]
        let points = CostSeries.points(from: series)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points.map(\.model), ["a", "a", "b", "b"])
        XCTAssertEqual(points.map(\.day), [0, 1, 0, 1])
        XCTAssertEqual(points.map(\.cost), [1.0, 2.0, 3.0, 4.0])
    }

    func testEmptySeriesMapsToNoPoints() {
        XCTAssertTrue(CostSeries.points(from: []).isEmpty)
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
        let costDays = [
            OpenCodeSnapshot.CostDay(day: "2026-08-07", model: #"{"id":"deepseek/deepseek-r1","providerID":"openrouter"}"#, cost: 0.0136),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, cost: 1.6465),
            OpenCodeSnapshot.CostDay(day: "2026-08-08", model: #"{"id":"qwen/qwen3.8-max","providerID":"openrouter","variant":"xhigh"}"#, cost: 0.0288),
            OpenCodeSnapshot.CostDay(day: "2026-08-09", model: #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, cost: 2.4801),
            OpenCodeSnapshot.CostDay(day: "2026-08-10", model: #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, cost: 0.0707),
            OpenCodeSnapshot.CostDay(day: "2026-08-11", model: #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, cost: 0.403),
            OpenCodeSnapshot.CostDay(day: "2026-08-12", model: #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, cost: 1.5077),
            OpenCodeSnapshot.CostDay(day: "2026-08-13", model: #"{"id":"deepseek-v4-flash","providerID":"opencode-go","variant":"max"}"#, cost: 0.0685),
        ]
        let series = CostSeries.buildSeries(from: costDays)

        XCTAssertEqual(series.map { CostSeries.displayID(of: $0.model) }, ["deepseek-v4-flash", "qwen/qwen3.8-max", "deepseek/deepseek-r1"])
        XCTAssertEqual(series[0].costs, [0.0, 1.6465, 2.4801, 0.0707, 0.403, 1.5077, 0.0685])
        XCTAssertEqual(series[0].costs.reduce(0, +), 6.1765, accuracy: 0.0001)
        XCTAssertEqual(series[1].costs, [0.0, 0.0288, 0.0, 0.0, 0.0, 0.0, 0.0])
        XCTAssertEqual(series[2].costs, [0.0136, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    }
}
