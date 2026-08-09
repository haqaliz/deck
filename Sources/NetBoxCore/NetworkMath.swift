import Foundation

public enum NetworkMath {
    /// Rate in bytes/second from two byte-counter samples.
    /// A negative delta (counter reset or interface flap) yields rate 0 and `didReset`.
    public static func rate(
        previousBytes: UInt64,
        currentBytes: UInt64,
        interval: TimeInterval
    ) -> (rate: Double, didReset: Bool) {
        guard interval > 0 else { return (0, false) }
        guard currentBytes >= previousBytes else { return (0, true) }
        return (Double(currentBytes - previousBytes) / interval, false)
    }

    public static func rates(
        previous: InterfaceSample,
        current: InterfaceSample,
        interval: TimeInterval
    ) -> InterfaceRates {
        let down = rate(previousBytes: previous.rxBytes, currentBytes: current.rxBytes, interval: interval)
        let up = rate(previousBytes: previous.txBytes, currentBytes: current.txBytes, interval: interval)
        return InterfaceRates(
            name: current.name,
            up: up.rate,
            down: down.rate,
            didReset: down.didReset || up.didReset
        )
    }

    /// The interface with the highest recent traffic (max of up/down); nil when empty.
    public static func mostActive(_ rates: [InterfaceRates]) -> InterfaceRates? {
        rates.max { lhs, rhs in
            max(lhs.up, lhs.down) < max(rhs.up, rhs.down)
        }
    }
}
