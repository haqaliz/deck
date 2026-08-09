import Foundation

public enum IOregParser {
    /// Parses `"CycleCount" = 107` out of `ioreg -rn AppleSmartBattery` output.
    public static func cycleCount(from output: String) -> Int? {
        let pattern = "\"CycleCount\"\\s*=\\s*(-?\\d+)"
        guard
            let range = output.range(of: pattern, options: .regularExpression),
            let valueRange = output[range].range(of: "= -?\\d+", options: .regularExpression)
        else { return nil }
        let number = output[valueRange].dropFirst()
        return Int(number.trimmingCharacters(in: .whitespaces))
    }
}
