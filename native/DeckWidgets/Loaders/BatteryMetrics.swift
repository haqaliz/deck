import Foundation
import IOKit.ps
// MARK: - Bluetooth accessory batteries
//
// `IOPSCopyPowerSourcesList` deliberately returns only the internal battery.
// Accessories are a separate power-source type, reachable through a by-type
// variant that IOKit exports but the public SDK headers do not declare — hence
// @_silgen_name. Verified inside this (sandboxed) extension, not merely in a
// CLI: the probe read "MX Master 3S = 75% cat=Mouse warn=20", matching
// `pmset -g accps`.
//
// Two dead ends, recorded so nobody re-walks them: `system_profiler
// SPBluetoothDataType -json` reports NO battery keys for a real connected
// mouse, and IORegistry exposes no `BatteryPercent` for it either.
//
// Being SPI, this can vanish in any macOS update. Every failure path returns
// an empty array, so BatBox then degrades to exactly what it does today.
@_silgen_name("IOPSCopyPowerSourcesByType")
private func IOPSCopyPowerSourcesByType(_ type: Int32) -> Unmanaged<CFTypeRef>?

enum AccessoryMetricsLoader {
    /// IOPSPowerSourceIndex: 0 all, 1 internal, 2 UPS, 3 internal+UPS,
    /// 4 accessories.
    private static let accessoryType: Int32 = 4

    static func snapshot() -> [BatteryAccessory] {
        guard
            let blob = IOPSCopyPowerSourcesByType(accessoryType)?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        var result: [BatteryAccessory] = []
        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                let name = desc["Name"] as? String,
                let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
                let maxCapacity = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
                // Not assuming Max Capacity == 100; reuse the existing maths.
                let percent = BatteryMath.percent(current: current, maxCapacity: maxCapacity)
            else { continue }

            let identifier = (desc["Accessory Identifier"] as? String) ?? name
            result.append(
                BatteryAccessory(
                    id: identifier,
                    name: name,
                    percent: percent,
                    lowWarnLevel: (desc["Low Warn Level"] as? NSNumber)?.intValue ?? 0,
                    category: (desc["Accessory Category"] as? String) ?? ""
                )
            )
        }
        return AccessoryCore.sorted(result)
    }
}

// MARK: - Battery state (IOKit power source, no subprocess)

struct BatterySnapshot: Equatable {
    let levelPercent: Double?
    let timeToEmptyMinutes: Int?
    let timeToFullMinutes: Int?
    let isCharging: Bool
    let isCharged: Bool
    let isPresent: Bool
    let powerSource: PowerSource
}

enum BatteryMetricsLoader {
    /// A full battery snapshot; missing keys degrade to nil, never crash.
    static func snapshot() -> BatterySnapshot {
        var current: Double?
        var maxCapacity: Double?
        var isCharging = false
        var isCharged = false
        var isPresent = true
        var powerSource: PowerSource = .battery
        var timeToEmptyReported: Int?
        var timeToFullReported: Int?

        if let desc = internalBatteryDescription() {
            current = number(desc[kIOPSCurrentCapacityKey])
            maxCapacity = number(desc[kIOPSMaxCapacityKey])
            isCharging = bool(desc[kIOPSIsChargingKey])
            isCharged = bool(desc[kIOPSIsChargedKey])
            isPresent = bool(desc[kIOPSIsPresentKey], fallback: true)
            if (desc[kIOPSPowerSourceStateKey] as? String) == "AC Power" {
                powerSource = .ac
            }
            timeToEmptyReported = int(desc[kIOPSTimeToEmptyKey])
            timeToFullReported = int(desc[kIOPSTimeToFullChargeKey])
        } else {
            isPresent = false
        }

        let level: Double? = (current != nil && maxCapacity != nil)
            ? BatteryMath.percent(current: current!, maxCapacity: maxCapacity!)
            : nil

        return BatterySnapshot(
            levelPercent: level,
            timeToEmptyMinutes: timeToEmptyReported.flatMap(BatteryMath.timeMinutes),
            timeToFullMinutes: timeToFullReported.flatMap(BatteryMath.timeMinutes),
            isCharging: isCharging,
            isCharged: isCharged || (level ?? 0) >= 100,
            isPresent: isPresent,
            powerSource: powerSource
        )
    }

    /// The INTERNAL battery's description, not merely power source zero: a UPS
    /// or an attached accessory would otherwise be read as the Mac's own.
    private static func internalBatteryDescription() -> [String: Any]? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType { return desc }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func bool(_ value: Any?, fallback: Bool = false) -> Bool {
        (value as? Bool) ?? fallback
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
