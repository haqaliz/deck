import Foundation

/// Deck's bundle identifiers, in one place.
///
/// **Why these are literals.** There is no way to derive them. A bundle id is a
/// build setting (`PRODUCT_BUNDLE_IDENTIFIER`), Swift has no string-valued
/// compile flag — `-D` defines a condition, not a value — and the only runtime
/// source, `Bundle.main.bundleIdentifier`, is wrong for both callers that
/// matter: the host app needs the *extension's* id (a different bundle), and
/// `DeckAgent` is a `type: tool` whose identity lives in a
/// `__TEXT,__info_plist` section rather than a bundle. So the literal is
/// unavoidable; `DeckBundleTests` pins it to `project.yml`, the generated
/// `DeckAgent/Info.plist`, and the two LaunchAgent plists, so it cannot drift
/// from the build silently.
///
/// **Renaming these is a user-visible migration, not a refactor.** The widget
/// id names a sandbox container holding `settings.json`; the app id names the
/// BTM parent record; the agent labels name two launchd jobs. See
/// `docs/planning/bundle-identifier/` for what a change costs and what was
/// measured.
enum DeckBundle {
    /// The host app. `com.deck.app` today; see `Legacy` for why the old value
    /// must outlive the rename.
    static let appID = "com.deck.app"

    /// The widget extension — and therefore the sandbox container that holds
    /// `settings.json` and every snapshot (`DeckSettings.containerDirectory`).
    static let widgetsID = appID + ".widgets"

    /// The 60s agent: its launchd label, its `SMAppService` plist basename, and
    /// its OSLog subsystem.
    static let agentLabel = "com.deck.agent"

    /// The fast process agent (`DECK_AGENT_ROLE=processes`).
    static let fastAgentLabel = agentLabel + ".processes"

    /// `log show --predicate 'subsystem == "com.deck.agent"'` is the documented
    /// diagnostic path, so this tracks the label rather than standing alone.
    static let logSubsystem = agentLabel

    /// Identifiers that named things now on users' disks and must never change.
    ///
    /// These are **not** "the previous values of the constants above" — they are
    /// permanent. After the rename they keep naming the old container (which is
    /// migrated from and deliberately never deleted, because its metadata plist
    /// is SIP-protected), the keychain service the five tokens still live under,
    /// and the two BTM records the rename orphans. Updating them to match a new
    /// scheme would strand all of it, silently.
    enum Legacy {
        static let appID = "com.deck.app"
        static let widgetsID = "com.deck.app.widgets"
        static let agentLabel = "com.deck.agent"
        static let fastAgentLabel = "com.deck.agent.processes"
    }
}
