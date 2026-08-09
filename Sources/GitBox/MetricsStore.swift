import Foundation
import Combine
import GitBoxCore

@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var dayCounts: [DayCommitCount] = []
    @Published private(set) var todayCount: Int = 0
    @Published private(set) var streak: Int = 0
    @Published private(set) var repos: [RepoCommits] = []
    @Published private(set) var hasRepos = true
    @Published private(set) var isLoaded = false

    private let settings: SettingsStore
    private var timer: Timer?
    private var cachedRepos: [URL] = []
    private var lastScanSignature: String?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        sample()
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when settings change: swaps the timer interval and re-scans when
    /// paths or scan depth changed.
    func settingsDidChange() {
        restartTimer()
        sample()
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(10, settings.settings.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func sample() {
        let paths = settings.settings.repoPaths
        let depth = settings.settings.scanDepth
        let signature = "\(paths.joined(separator: "\n"))|\(depth)"
        if signature != lastScanSignature {
            lastScanSignature = signature
            cachedRepos = GitMetricsLoader.discoverRepos(paths: paths, depth: depth)
            hasRepos = !cachedRepos.isEmpty
        }
        let repos = cachedRepos
        let calendar = Calendar.current
        let today = GitMath.dayLabel(Date(), calendar: calendar)
        let window = GitMath.daysBack(14, today: Date(), calendar: calendar)
        Task.detached {
            let result = GitMetricsLoader.sample(repos: repos, today: today)
            let buckets = GitMath.bucket(counts: result.dayCounts, window: window)
            let streak = GitMath.streak(counts: result.dayCounts, window: window)
            let sorted = result.repos
                .filter { $0.todayCount > 0 }
                .sorted { $0.todayCount > $1.todayCount }
            await MainActor.run {
                self.dayCounts = window.enumerated().map { DayCommitCount(day: $0.element, count: buckets[$0.offset]) }
                self.todayCount = result.repos.reduce(0) { $0 + $1.todayCount }
                self.streak = streak
                self.repos = sorted
                self.isLoaded = true
                if ProcessInfo.processInfo.environment["GITBOX_DEBUG"] != nil {
                    print("GITBOX_DEBUG today=\(self.todayCount) streak=\(self.streak) repos=\(self.repos.count) reposFound=\(repos.count) hasRepos=\(self.hasRepos) days=\(self.dayCounts.map(\.count))")
                    fflush(stdout)
                }
            }
        }
    }
}
