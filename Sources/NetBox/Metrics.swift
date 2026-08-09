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
}

/// CPU usage percent (0...100) since the previous sample.
/// Pass `nil` for the first call to seed the baseline.
func cpuUsagePercent(previous: CpuTicks?) -> (usage: Double, current: CpuTicks) {
    let current = CpuTicks.sample()
    guard let previous else { return (0, current) }
    let deltaTotal = current.total - previous.total
    guard deltaTotal > 0 else { return (0, current) }
    let deltaIdle = current.idle - previous.idle
    return (Double(deltaTotal - deltaIdle) / Double(deltaTotal) * 100.0, current)
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

// MARK: - Top processes

struct TopProcess {
    let name: String
    let cpuPercent: Double
    let memPercent: Double
}

enum ProcessSort {
    case cpu
    case memory
}

/// Top processes by CPU usage, from `ps`.
func topProcesses(limit: Int = 3, sortBy: ProcessSort = .cpu) -> [TopProcess] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-Aceo", "comm=,%cpu=,%mem="]
    process.standardOutput = pipe
    process.standardError = nil
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return [] }

    let rows = text
        .split(separator: "\n")
        .compactMap { row -> TopProcess? in
            let parts = row.split(whereSeparator: { $0 == " " }).filter { !$0.isEmpty }
            guard parts.count >= 3 else { return nil }
            let path = parts[0]
            let cpu = Double(parts[1]) ?? 0
            let mem = Double(parts[2]) ?? 0
            return TopProcess(
                name: NSString(string: String(path)).lastPathComponent,
                cpuPercent: cpu,
                memPercent: mem
            )
        }
        .sorted {
            switch sortBy {
            case .cpu: return $0.cpuPercent > $1.cpuPercent
            case .memory: return $0.memPercent > $1.memPercent
            }
        }

    return Array(rows.prefix(limit))
}
