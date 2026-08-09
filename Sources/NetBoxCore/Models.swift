import Foundation

public struct InterfaceSample: Equatable {
    public let name: String
    public let rxBytes: UInt64
    public let txBytes: UInt64

    public init(name: String, rxBytes: UInt64, txBytes: UInt64) {
        self.name = name
        self.rxBytes = rxBytes
        self.txBytes = txBytes
    }
}

public struct InterfaceRates: Equatable {
    public let name: String
    public let up: Double
    public let down: Double
    public let didReset: Bool

    public init(name: String, up: Double, down: Double, didReset: Bool) {
        self.name = name
        self.up = up
        self.down = down
        self.didReset = didReset
    }
}
