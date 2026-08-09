import Foundation
import Combine

struct Sample {
    let cpu: Double
    let mem: Double
    let disk: Double
}

@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var mem: Double = 0
    @Published private(set) var disk: Double = 0
    @Published private(set) var processesByCPU: [TopProcess] = []
    @Published private(set) var processesByMemory: [TopProcess] = []

    @Published private(set) var history: [Sample] = []

    let historyCapacity = 90
    private let settings: SettingsStore
    private var lastTicks: CpuTicks?
    private var timer: Timer?
    private var processTick = 0

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        lastTicks = CpuTicks.sample()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let (usage, ticks) = cpuUsagePercent(previous: lastTicks)
        lastTicks = ticks
        cpu = usage
        mem = memoryUsagePercent()
        disk = diskUsagePercent()

        history.append(Sample(cpu: usage, mem: mem, disk: disk))
        if history.count > historyCapacity {
            history.removeFirst(history.count - historyCapacity)
        }

        processTick += 1
        if processTick % 2 == 0 {
            let count = max(1, min(20, settings.settings.processCount))
            processesByCPU = topProcesses(limit: count, sortBy: .cpu)
            processesByMemory = topProcesses(limit: count, sortBy: .memory)
        }
    }
}
