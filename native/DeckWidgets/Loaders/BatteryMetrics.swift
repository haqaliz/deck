import Foundation
import IOKit.ps

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
