import Foundation

public enum PowerSource: Equatable {
    case battery
    case ac
}

public enum LevelTier: Equatable {
    case high
    case medium
    case low
}

/// Raw battery facts from the IOKit power-source dictionary + ioreg cycle count.
/// Every field is optional: missing keys must never crash the widget.
public struct BatterySnapshot: Equatable {
    public let levelPercent: Double?
    public let timeToEmptyMinutes: Int?
    public let timeToFullMinutes: Int?
    public let isCharging: Bool
    public let isCharged: Bool
    public let isPresent: Bool
    public let cycleCount: Int?
    public let powerSource: PowerSource

    public init(
        levelPercent: Double?,
        timeToEmptyMinutes: Int?,
        timeToFullMinutes: Int?,
        isCharging: Bool,
        isCharged: Bool,
        isPresent: Bool,
        cycleCount: Int?,
        powerSource: PowerSource
    ) {
        self.levelPercent = levelPercent
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullMinutes = timeToFullMinutes
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.isPresent = isPresent
        self.cycleCount = cycleCount
        self.powerSource = powerSource
    }
}
