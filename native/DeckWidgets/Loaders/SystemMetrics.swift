import Foundation
import Darwin

// MARK: - CPU
//
// The pure tick math (CpuTicks, perCoreUsagePercents, cpuUsagePercent) lives
// in Shared/SystemMetricsCore.swift so DeckSharedTests can cover it; this file
// keeps only the mach samplers that feed it.

extension CpuTicks {
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

/// Every mounted volume's capacity, as raw records for `LiveBoxDiskCore`.
///
/// The widget sandbox permits reading Volume resource values (the same API
/// `diskUsagePercent()` already uses in-process). We enumerate with
/// `getmntinfo` rather than `mountedVolumeURLs` because the real boot volume
/// (`/System/Volumes/Data`) is marked "nobrowse" on Catalina+ and would be
/// hidden by `skipHiddenVolumes`; `getmntinfo` lists every mount, and
/// `LiveBoxDiskCore` drops the system/pseudo mounts by path + browsable flag.
func diskVolumeSamples() -> [RawVolume] {
    let keys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsBrowsableKey,
        .volumeIdentifierKey,
    ]
    var mnt: UnsafeMutablePointer<statfs>?
    let count = getmntinfo(&mnt, MNT_NOWAIT)
    guard count > 0, let mnt else { return [] }

    var result: [RawVolume] = []
    result.reserveCapacity(Int(count))
    for i in 0..<Int(count) {
        let m = mnt[i]
        guard (m.f_flags & UInt32(MNT_LOCAL)) != 0 else { continue }
        let path = withUnsafeBytes(of: m.f_mntonname) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys) else { continue }
        result.append(RawVolume(
            name: values.volumeLocalizedName ?? "",
            mountPath: path,
            totalBytes: values.volumeTotalCapacity.map(UInt64.init),
            availableBytes: values.volumeAvailableCapacityForImportantUsage.map(UInt64.init),
            isLocal: true,
            isBrowsable: values.volumeIsBrowsable ?? false,
            identifier: (values.volumeIdentifier as? UUID)?.uuidString ?? path
        ))
    }
    return result
}
