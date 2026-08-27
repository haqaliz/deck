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
    /// The user vetoed the agents in System Settings → Login Items while
    /// Deck's own toggle is on. Say so; do not rewrite either side.
    case reportBlocked
}

/// What launch-time reconciliation should do about the background agents.
///
/// The policy only governs reconciliation: it never unregisters, because
/// unregistering is the toggle handler's direct action. It never fights the
/// user: a veto in System Settings is reported, not overridden, and someone
/// who enabled the agents there has their toggle flipped back on.
/// `.notFound` is the fresh-install state (the plist is in the bundle, so
/// registering is ours to try).
///
/// `.requiresApproval` is what a user veto in System Settings → Login Items
/// actually produces — measured 2026-08-27, `sfltool dumpbtm` shows the record
/// as `[enabled, disallowed]`: Deck's registration stands, the user's
/// permission does not. It is also the state of a fresh registration nobody
/// has approved yet, so the two are indistinguishable here and neither side
/// gets rewritten — the app reports the drift and leaves it to the user.
/// `.notRegistered` is therefore only reachable when Deck itself never
/// registered or called `unregister`, not from anything the user does in
/// System Settings.
enum AgentReconcilePolicy {
    static func resolve(intent: Bool, state: AgentRegistrationState) -> [AgentAction] {
        switch (intent, state) {
        case (true, .enabled):
            return []
        case (true, .requiresApproval):
            return [.reportBlocked]
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