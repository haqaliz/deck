import Testing
@testable import LiveBoxCore

@Suite("PerCore.usagePercents")
struct PerCoreTests {
    private func ticks(user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0) -> CpuTicks {
        CpuTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test("identical samples yield all zeros")
    func identicalSamples() {
        let sample = ticks(user: 100, system: 50, idle: 800, nice: 10)
        let result = PerCore.usagePercents(previous: [sample, sample], current: [sample, sample])
        #expect(result == [0, 0])
    }

    @Test("idle-only increase yields zeros")
    func idleOnlyIncrease() {
        let prev = [ticks(user: 100, idle: 800)]
        let cur = [ticks(user: 100, idle: 850)]
        #expect(PerCore.usagePercents(previous: prev, current: cur) == [0])
    }

    @Test("known half-busy delta yields 50%")
    func halfBusyCore() {
        let prev = [ticks(user: 0, idle: 100)]
        let cur = [ticks(user: 25, idle: 125)]
        #expect(PerCore.usagePercents(previous: prev, current: cur) == [50])
    }

    @Test("fully busy core yields 100%")
    func fullyBusyCore() {
        let prev = [ticks(user: 0, idle: 100)]
        let cur = [ticks(user: 50, idle: 100)]
        #expect(PerCore.usagePercents(previous: prev, current: cur) == [100])
    }

    @Test("mixed cores keep per-core values")
    func mixedCores() {
        let prev = [
            ticks(user: 0, idle: 100),
            ticks(user: 0, idle: 200),
            ticks(user: 0, idle: 300),
        ]
        let cur = [
            ticks(user: 25, idle: 125),
            ticks(user: 100, idle: 200),
            ticks(user: 0, idle: 350),
        ]
        #expect(PerCore.usagePercents(previous: prev, current: cur) == [50, 100, 0])
    }

    @Test("count mismatch uses shared prefix without crashing")
    func countMismatch() {
        let prev = [ticks(idle: 100), ticks(idle: 200)]
        let cur = [ticks(idle: 150), ticks(idle: 250), ticks(idle: 999)]
        let result = PerCore.usagePercents(previous: prev, current: cur)
        #expect(result == [0, 0])
        #expect(result.count == 2)
    }

    @Test("empty previous yields empty result")
    func emptyPrevious() {
        #expect(PerCore.usagePercents(previous: [], current: [ticks(idle: 100)]) == [])
    }
}
