struct CpuTicks: Equatable {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var nice: UInt64 = 0

    var total: UInt64 { user + system + idle + nice }
}
