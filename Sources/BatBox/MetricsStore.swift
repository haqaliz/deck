import Foundation
import Combine
import BatBoxCore

@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    /// Rolling level-% history (capacity 90, one sample per second).
    @Published private(set) var history: [Double] = []

    let historyCapacity = 90
    private let settings: SettingsStore
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
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
        let current = BatteryMetricsLoader.snapshot()
        snapshot = current
        guard let level = current.levelPercent else { return }
        history.append(level)
        if history.count > historyCapacity {
            history.removeFirst(history.count - historyCapacity)
        }
    }
}
