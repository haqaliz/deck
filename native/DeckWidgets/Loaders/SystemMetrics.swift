import Foundation
import Darwin

// MARK: - CPU

struct CpuTicks {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var nice: UInt64 = 0

    var total: UInt64 { user + system + idle + nice }

    static func sample() -> CpuTicks {
        var ticks = CpuTicks()
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return ticks }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo))
        }

        let info = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCpuInfo)) { $0 }
        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            ticks.user += UInt64(info[offset + Int(CPU_STATE_USER)])
            ticks.system += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            ticks.idle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            ticks.nice += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }
        return ticks
    }

    /// One `CpuTicks` per physical processor, in CPU index order.
    static func sampleAll() -> [CpuTicks] {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo))
        }

        let info = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCpuInfo)) { $0 }
        return (0..<Int(numCPUs)).map { i in
            let offset = Int(CPU_STATE_MAX) * i
            return CpuTicks(
                user: UInt64(info[offset + Int(CPU_STATE_USER)]),
                system: UInt64(info[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[offset + Int(CPU_STATE_NICE)])
            )
        }
    }
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

/// CPU usage percent (0...100) since the previous sample.
/// Pass `nil` for the first call to seed the baseline.
func cpuUsagePercent(previous: CpuTicks?) -> (usage: Double, current: CpuTicks) {
    let current = CpuTicks.sample()
    return (cpuUsagePercent(previous: previous, current: current), current)
}

// MARK: - Memory

func memoryUsagePercent() -> Double {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }

    let pageSize = vm_kernel_page_size
    let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * UInt64(pageSize)
    let total = ProcessInfo.processInfo.physicalMemory
    guard total > 0 else { return 0 }
    return Double(used) / Double(total) * 100.0
}

// MARK: - Disk

func diskUsagePercent() -> Double {
    let url = URL(fileURLWithPath: "/")
    guard
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage,
        total > 0
    else { return 0 }
    return (Double(total) - Double(available)) / Double(total) * 100.0
}
