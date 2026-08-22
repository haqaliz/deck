import Foundation

// MARK: - Bluetooth accessory batteries (pure logic)
//
// The IOKit read lives in DeckWidgets/Loaders/BatteryMetrics.swift because the
// widget target cannot be compiled into the unit-test bundle; everything that
// makes a decision lives here so it is testable — the BatteryCore precedent.
//
// Field shapes are taken from a verified probe of a real connected device
// rather than from documentation:
//
//   Name = "MX Master 3S"    Current Capacity = 75    Max Capacity = 100
//   Low Warn Level = 20      Accessory Category = "Mouse"

struct BatteryAccessory: Equatable {
    /// `Accessory Identifier` when present, else the name. Never the display
    /// name alone if an identifier exists — names duplicate across devices.
    let id: String
    let name: String
    let percent: Double
    /// The device's own low threshold, as reported by IOKit.
    let lowWarnLevel: Int
    /// Apple's `Accessory Category` string ("Mouse", "Keyboard", …).
    let category: String
}

enum AccessoryCore {
    /// Used when a device reports no warn level of its own.
    static let defaultWarnLevel = 20

    /// Amber at the device's own warn level, red at half of it.
    ///
    /// Each accessory carries its own threshold, so there is no global setting
    /// to disagree with what the manufacturer considers low. Two steps rather
    /// than one keeps "getting low" visually distinct from "about to die".
    static func tier(percent: Double, lowWarnLevel: Int) -> ThresholdTier {
        let warn = lowWarnLevel > 0 ? lowWarnLevel : defaultWarnLevel
        if percent <= Double(warn) / 2 { return .alarm }
        if percent <= Double(warn) { return .warn }
        return .normal
    }

    /// SF Symbol for an `Accessory Category`. Apple's category set will grow,
    /// so anything unrecognised gets a generic glyph rather than a blank slot.
    static func symbol(for category: String) -> String {
        switch category.lowercased() {
        case "mouse": return "magicmouse"
        case "keyboard": return "keyboard"
        case "trackpad": return "trackpad"
        case "headphones", "headset", "headphone": return "headphones"
        case "speaker": return "hifispeaker"
        case "gamecontroller", "game controller": return "gamecontroller"
        case "pencil", "stylus": return "pencil"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// Lowest battery first, so when the row cap bites it is the accessory
    /// about to die that survives rather than an alphabetical accident.
    /// Ties keep input order.
    static func sorted(_ accessories: [BatteryAccessory]) -> [BatteryAccessory] {
        accessories.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.percent != rhs.element.percent {
                    return lhs.element.percent < rhs.element.percent
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The small face's one-liner. Nil when nothing is connected — an empty
    /// list must render nothing at all, not "0 ACCESSORIES".
    static func summary(_ accessories: [BatteryAccessory]) -> String? {
        guard let lowest = sorted(accessories).first else { return nil }
        let percent = Int(lowest.percent.rounded())
        if accessories.count == 1 { return "1 ACCESSORY · \(percent)%" }
        return "\(accessories.count) ACCESSORIES · LOW \(percent)%"
    }
}
