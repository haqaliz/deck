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

    static let main = Agent(service: .agent(plistName: "com.deck.agent.plist"), label: "com.deck.agent")
    static let processes = Agent(
        service: .agent(plistName: "com.deck.agent.processes.plist"),
        label: "com.deck.agent.processes"
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
}