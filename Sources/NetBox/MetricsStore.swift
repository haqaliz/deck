import Foundation
import Combine
import NetBoxCore

struct RateSample {
    let up: Double
    let down: Double
}

@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var header: InterfaceRates?
    @Published private(set) var interfaces: [InterfaceRates] = []
    @Published private(set) var history: [RateSample] = []
    /// Chart Y ceiling (0...peak) so a flat series never collapses the scale.
    @Published private(set) var peak: Double = 0

    let historyCapacity = 90
    private let settings: SettingsStore
    private var previous: [InterfaceSample]?
    private var headerName: String?
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        previous = NetworkMetricsLoader.sample()
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
        let current = NetworkMetricsLoader.sample()
        guard let previous else {
            self.previous = current
            return
        }
        self.previous = current

        let rates = previous.compactMap { p in
            current.first { $0.name == p.name }
                .map { NetworkMath.rates(previous: p, current: $0, interval: 1) }
        }
        .sorted { max($0.up, $0.down) > max($1.up, $1.down) }

        interfaces = rates
        guard let top = rates.first else { return }

        header = top
        if top.name != headerName {
            // Never stitch two interfaces' series into one chart.
            headerName = top.name
            history.removeAll()
        }
        history.append(RateSample(up: top.up, down: top.down))
        if history.count > historyCapacity {
            history.removeFirst(history.count - historyCapacity)
        }
        peak = history.map { max($0.up, $0.down) }.max() ?? 0
    }
}
