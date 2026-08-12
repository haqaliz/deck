enum PerCore {
    /// Per-core usage percent (0...100) between two tick samples, one entry
    /// per shared-prefix core. 0 when a core shows no delta. Counts that
    /// differ between samples are zip-safe (shared prefix only).
    static func usagePercents(previous: [CpuTicks], current: [CpuTicks]) -> [Double] {
        zip(previous, current).map { prev, cur in
            let deltaTotal = cur.total - prev.total
            guard deltaTotal > 0 else { return 0 }
            let deltaIdle = cur.idle - prev.idle
            return Double(deltaTotal - deltaIdle) / Double(deltaTotal) * 100.0
        }
    }
}
