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
/// Whether the background agents are actually running, as distinct from being
/// registered.
///
/// `.unknown` is not a soft `.down`: it means the question is not ours to
/// answer right now — the user turned the agents off, another notice already
/// owns the state, or nothing has had time to happen yet. Only `.down` is
/// reported to the user, and `.healthy` renders nothing at all.
enum AgentLiveness: Equatable {
    case healthy
    case unknown
    /// `lastRefresh` is `nil` when the agent never ran once — the state the
    /// bundle rename puts every user into.
    case down(lastRefresh: Date?)
}

/// The third way Deck's agents can be down, and the only one nothing else
/// catches: **registered but never loaded by launchd**.
///
/// `SMAppService.status` answers "does a registration record exist", not "did
/// launchd load the job". Measured on the dev machine: both agents
/// `[enabled, allowed]` in `sfltool dumpbtm`, the toggle on, `launchctl print`
/// answering `Could not find service`, and nothing written for six hours.
/// `AgentReconcilePolicy.resolve(intent: true, state: .enabled)` returns `[]`,
/// correctly — the registration is exactly what the user asked for.
///
/// There is no OS call that answers this, and no shell probe either:
/// `launchctl list | grep com.deck.agent` prints nothing on a *healthy*
/// install, because SMAppService jobs are not bootstrapped into `gui/<uid>`
/// under their plist label. So the check is inferential, from what a live
/// agent leaves behind.
///
/// The witness is `processes.json`. Its single writer is the fast agent
/// (`DeckAgent/main.swift`, `sampleProcesses()`); every other snapshot is
/// written by the host app too, which is why a dead agent is invisible while
/// Deck is open. It therefore proves only that
/// `com.deck.agent.processes` ran — the wording of the notice claims no more
/// than that, even though both agents are registered by one call and the
/// measured fault took both down together.
enum AgentLivenessPolicy {
    /// How old the evidence may get before it means something is wrong.
    ///
    /// Deliberately more conservative than the widget's own
    /// `ProcessSnapshot.maxAgeSeconds(for:)` (`max(2 * interval, 30)`): that
    /// one dims a row on a single missed tick, this one tells the user macOS
    /// is not running their agents. A notice that flickers on a transient
    /// hiccup is worse than one that takes two minutes to appear.
    ///
    /// The same number serves as the grace window after registration, since a
    /// registration older than this with nothing ever written is the never-ran
    /// case.
    static func threshold(processRefreshInterval: Int) -> TimeInterval {
        TimeInterval(max(4 * processRefreshInterval, 120))
    }

    static func resolve(
        intent: Bool,
        state: AgentRegistrationState,
        lastRefreshAt: Date?,
        registeredAt: Date?,
        processRefreshInterval: Int,
        now: Date
    ) -> AgentLiveness {
        // 1. Nothing is supposed to be running. Not a fault.
        guard intent else { return .unknown }

        // 2. The other two notices own the other states. Keeping this
        //    structural rather than an `if` in the view is what stops a Login
        //    Items veto from also raising a liveness notice — two notices for
        //    one condition, the second wrong about the cause.
        guard state == .enabled else { return .unknown }

        let limit = threshold(processRefreshInterval: processRefreshInterval)

        // 3. Recent evidence wins, and is checked BEFORE the grace window so a
        //    restart that worked clears the notice at the next agent tick
        //    instead of waiting the grace period out. A stamp in the future is
        //    a bad clock, not a dead agent: never accuse on the strength of a
        //    clock.
        if let lastRefreshAt, now.timeIntervalSince(lastRefreshAt) < limit {
            return .healthy
        }

        // 4. No clock to judge against. Momentary: reconciliation adopts `now`
        //    the first time it sees an enabled registration.
        guard let registeredAt else { return .unknown }

        // 5. Registered too recently to expect anything yet — a fresh install,
        //    and the first launch after the bundle rename.
        if now.timeIntervalSince(registeredAt) < limit { return .unknown }

        // 6. Registered long enough ago that silence means something.
        return .down(lastRefresh: lastRefreshAt)
    }
}
