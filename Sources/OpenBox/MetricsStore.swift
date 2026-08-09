import OpenBoxCore
import Foundation
import Combine

@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var metrics: OpenCodeMetrics?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?

    private let settings: SettingsStore
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let interval = TimeInterval(max(5, settings.settings.refreshInterval))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if let loaded = OpenCodeMetricsLoader.load() {
            metrics = loaded
            lastUpdated = Date()
            error = nil
        } else {
            error = "Could not read opencode metrics.\nIs opencode installed and has usage data?"
        }
    }
}
