import Foundation
import ServiceManagement

/// The two background agents, registered through SMAppService so they show up
/// in System Settings → General → Login Items.
///
/// The plists live in the signed bundle at
/// `Contents/Library/LaunchAgents/` and address the embedded DeckAgent via
/// `BundleProgram` (relative to the bundle, so moving the app does not break
/// them). The app is the only caller; the policy behind launch-time decisions
/// is `AgentReconcilePolicy` in Shared (unit-tested).
enum AgentService {
    struct Agent {
        let service: SMAppService
        let label: String

        var state: AgentRegistrationState {
            switch service.status {
            case .notRegistered: .notRegistered
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notFound: .notFound
            @unknown default: .notFound
            }
        }

        func register() throws {
            // register() on an already-enabled service is a no-op at best and
            // an error at worst; the policy already filters, but stay safe.
            guard service.status != .enabled else { return }
            try service.register()
        }
    }

    static let main = Agent(
        service: .agent(plistName: "\(DeckBundle.agentLabel).plist"),
        label: DeckBundle.agentLabel
    )
    static let processes = Agent(
        service: .agent(plistName: "\(DeckBundle.fastAgentLabel).plist"),
        label: DeckBundle.fastAgentLabel
    )

    static var all: [Agent] { [main, processes] }

    /// Register both agents. Stops at the first failure.
    static func registerAll() throws {
        for agent in all {
            try agent.register()
        }
    }

    /// Best-effort unregister of both agents; never throws.
    static func unregisterAll() {
        for agent in all {
            try? agent.service.unregister()
        }
    }

    /// The pre-rename agents, shipped for exactly one release. `unregister()`
    /// flips their orphaned BTM records to [disabled, allowed] — it cannot
    /// delete them, and without the old plists in the bundle there is no handle
    /// at all (flip-runbook Step 2).
    static let legacy = [
        Agent(
            service: .agent(plistName: "\(DeckBundle.Legacy.agentLabel).plist"),
            label: DeckBundle.Legacy.agentLabel
        ),
        Agent(
            service: .agent(plistName: "\(DeckBundle.Legacy.fastAgentLabel).plist"),
            label: DeckBundle.Legacy.fastAgentLabel
        ),
    ]

    /// Run at launch, after the current agents are registered: the renamed app
    /// re-parents the old records, leaving four DeckAgent rows — two of which
    /// can never run. A no-op before the rename.
    static func unregisterLegacy() {
        guard LegacyAgentCleanup.shouldUnregisterLegacy(
            current: DeckBundle.agentLabel,
            legacy: DeckBundle.Legacy.agentLabel
        ) else { return }
        for agent in legacy {
            try? agent.service.unregister()
        }
    }
}