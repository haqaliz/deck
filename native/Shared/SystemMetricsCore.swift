import Foundation

// MARK: - CPU ticks + pure per-core math
//
// Pure, testable core moved out of DeckWidgets/Loaders/SystemMetrics.swift so
// DeckSharedTests can cover it (the widget target isn't compiled into the test
// bundle). The mach samplers (`CpuTicks.sample`, `sampleAll`) stay in the
// loader file — they only feed these pure functions.

struct CpuTicks: Equatable {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var nice: UInt64 = 0

    var total: UInt64 { user + system + idle + nice }
}

/// Per-core usage percent (0...100) between two tick samples, one entry per
/// shared-prefix core. 0 when a core shows no delta. Counts that differ
/// between samples are zip-safe (shared prefix only).
func perCoreUsagePercents(previous: [CpuTicks], current: [CpuTicks]) -> [Double] {
    zip(previous, current).map { prev, cur in
        let deltaTotal = cur.total - prev.total
        guard deltaTotal > 0 else { return 0 }
        let deltaIdle = cur.idle - prev.idle
        return Double(deltaTotal - deltaIdle) / Double(deltaTotal) * 100.0
    }
}

/// CPU usage percent (0...100) between two tick samples.
/// Pass `nil` for the first call to seed the baseline.
func cpuUsagePercent(previous: CpuTicks?, current: CpuTicks) -> Double {
    guard let previous else { return 0 }
    let deltaTotal = current.total - previous.total
    guard deltaTotal > 0 else { return 0 }
    let deltaIdle = current.idle - previous.idle
    return Double(deltaTotal - deltaIdle) / Double(deltaTotal) * 100.0
}
