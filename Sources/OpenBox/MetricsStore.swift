import OpenBoxCore
import Foundation
import Combine

@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var metrics: OpenCodeMetrics?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?
    @Published private(set) var isRemote = false

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
        guard let serverURL = settings.settings.serverURL?
            .trimmingCharacters(in: .whitespaces), !serverURL.isEmpty
        else {
            isRemote = false
            loadLocal()
            return
        }

        isRemote = true
        let password = settings.settings.token
        Task {
            do {
                guard let url = URL(string: serverURL) else {
                    throw RemoteLoadError.invalidURL
                }
                let loader = RemoteOpenCodeMetricsLoader(url: url, password: password)
                let loaded = try await loader.load()
                metrics = loaded
                lastUpdated = Date()
                error = nil
            } catch {
                self.error = "Could not reach opencode server at \(serverURL).\nCheck URL and password."
            }
        }
    }

    private func loadLocal() {
        if let loaded = OpenCodeMetricsLoader.load() {
            metrics = loaded
            lastUpdated = Date()
            error = nil
        } else {
            error = "Could not read opencode metrics.\nIs opencode installed and has usage data?"
        }
    }
}
