import Foundation
import IOKit.ps
import BatBoxCore

// MARK: - Battery state
//
// Level/state/time come from IOKit's power-source dictionary (pure C, no
// subprocess). Cycle count is NOT in that dictionary (only DesignCycleCount) —
// read from `ioreg -rn AppleSmartBattery` instead (~13ms, local).

enum BatteryMetricsLoader {
    /// A full battery snapshot; missing keys degrade to nil, never crash.
    static func snapshot() -> BatterySnapshot {
        var current: Double?
        var maxCapacity: Double?
        var isCharging = false
        var isCharged = false
        var isPresent = true
        var powerSource: PowerSource = .battery
        var timeToEmptySeconds: Int?
        var timeToFullSeconds: Int?

        if
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let first = list.first,
            let desc = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any]
        {
            current = number(desc[kIOPSCurrentCapacityKey])
            maxCapacity = number(desc[kIOPSMaxCapacityKey])
            isCharging = bool(desc[kIOPSIsChargingKey])
            isCharged = bool(desc[kIOPSIsChargedKey])
            isPresent = bool(desc[kIOPSIsPresentKey], fallback: true)
            if (desc[kIOPSPowerSourceStateKey] as? String) == "AC Power" {
                powerSource = .ac
            }
            timeToEmptySeconds = int(desc[kIOPSTimeToEmptyKey])
            timeToFullSeconds = int(desc[kIOPSTimeToFullChargeKey])
        } else {
            isPresent = false
        }

        let level: Double? = (current != nil && maxCapacity != nil)
            ? BatteryMath.percent(current: current!, maxCapacity: maxCapacity!)
            : nil

        return BatterySnapshot(
            levelPercent: level,
            timeToEmptyMinutes: timeToEmptySeconds.flatMap(BatteryMath.timeMinutes),
            timeToFullMinutes: timeToFullSeconds.flatMap(BatteryMath.timeMinutes),
            isCharging: isCharging,
            isCharged: isCharged || (level ?? 0) >= 100,
            isPresent: isPresent,
            cycleCount: readCycleCount(),
            powerSource: powerSource
        )
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

    /// `"CycleCount" = 107` from `ioreg -rn AppleSmartBattery`; nil on failure.
    private static func readCycleCount() -> Int? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ioreg", "-rn", "AppleSmartBattery"]
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let out = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return IOregParser.cycleCount(from: out)
    }
}
