import Foundation

// MARK: - Countdown wording

public enum Countdown {
    /// The non-relative wording beneath the event title: `in 2h 05m`,
    /// `in 42m`, `now`, or `12m in` once it has started.
    ///
    /// Minute granularity throughout — second-precision on a desktop widget
    /// buys nothing and invites re-render churn. Anything within a minute
    /// either side reads as `now`, which is what a person would say.
    public static func text(start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)

        if abs(delta) < 60 { return "now" }

        if delta < 0 {
            let minutes = Int(-delta) / 60
            return "\(minutes)m in"
        }

        let totalMinutes = Int(delta) / 60
        if totalMinutes <= 60 { return "in \(totalMinutes)m" }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "in %dh %02dm", hours, minutes)
    }
}
