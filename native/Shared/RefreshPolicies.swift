import Foundation

/// Whether the fast agent should sample the process list on this launchd tick.
///
/// The fast agent's bundle plist pins a fixed `StartInterval` (5s, the minimum
/// of the user-facing range) because the signed bundle cannot be rewritten
/// when `livebox.processRefreshInterval` changes. This policy turns that fixed
/// tick into the configured cadence: sample only when the last sample is old
/// enough. `lastSampleAt` is the snapshot's `writtenAt`, which the fast agent
/// refreshes on every sample (always-write).
enum ProcessRefreshPolicy {
    static func shouldSample(lastSampleAt: Date?, configuredInterval: Int, now: Date) -> Bool {
        guard let lastSampleAt else { return true }
        guard configuredInterval > 0 else { return true }
        return now.timeIntervalSince(lastSampleAt) >= Double(configuredInterval)
    }
}

/// The registration state of an SMAppService agent, as seen by the launch-time
/// reconciliation. Mapped from `SMAppService.Status` in the app target so the
/// policy stays pure and testable without importing ServiceManagement into
/// Shared (which also compiles into the widget extension).
enum AgentRegistrationState {
    case notFound
    case notRegistered
    case enabled
    case requiresApproval
}

enum AgentAction: Equatable {
    case register
    case unregister
    case adoptIntent(Bool)
}

/// What launch-time reconciliation should do about the background agents.
///
/// The policy only governs reconciliation: it never unregisters, because
/// unregistering is the toggle handler's direct action. It mirrors reality in
/// both directions — a user who disabled the agent in System Settings →
/// Login Items is never fought, and one who enabled it there has their toggle
/// flipped back on. `.notFound` is the fresh-install state (the plist is in
/// the bundle, so registering is ours to try); `.notRegistered` is the
/// disabled-by-the-user state.
enum AgentReconcilePolicy {
    static func resolve(intent: Bool, state: AgentRegistrationState) -> [AgentAction] {
        switch (intent, state) {
        case (true, .enabled), (true, .requiresApproval):
            return []
        case (true, .notFound):
            return [.register]
        case (true, .notRegistered):
            return [.adoptIntent(false)]
        case (false, .enabled):
            return [.adoptIntent(true)]
        case (false, .notFound), (false, .notRegistered), (false, .requiresApproval):
            return []
        }
    }
}