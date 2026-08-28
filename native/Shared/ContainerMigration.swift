import Foundation

/// Whether to carry `settings.json` from the pre-rename widget container into
/// the current one — decided as pure data so the cases can be exhausted in
/// tests, with the file I/O kept in `ContainerMigration`.
enum ContainerMigrationPolicy {
    enum SkipReason: Equatable {
        /// `DeckBundle.widgetsID == DeckBundle.Legacy.widgetsID`, so both paths
        /// are one directory. True until the rename ships: this is what lets
        /// the migration land a release early and do nothing.
        case sameContainer
        /// No pre-rename container — a fresh install, not a failure.
        case noLegacyContainer
        /// The old container exists but holds no `settings.json`. Deck writes
        /// that file only on change, so an install that was never configured
        /// genuinely has none.
        case noLegacySettings
        /// The current container is already configured. Never overwrite it.
        case alreadyMigrated
    }

    enum Decision: Equatable {
        case copy
        case skip(SkipReason)
    }

    /// Order matters. `alreadyMigrated` is checked before the legacy side is
    /// examined at all: once the new container is configured, how the old one
    /// looks is irrelevant.
    static func decide(
        identifiersDiffer: Bool,
        legacyContainerExists: Bool,
        legacySettingsExists: Bool,
        currentSettingsExists: Bool
    ) -> Decision {
        guard identifiersDiffer else { return .skip(.sameContainer) }
        if currentSettingsExists { return .skip(.alreadyMigrated) }
        guard legacyContainerExists else { return .skip(.noLegacyContainer) }
        guard legacySettingsExists else { return .skip(.noLegacySettings) }
        return .copy
    }
}

/// Carries `settings.json` across the container move that the bundle rename
/// forces.
///
/// **Only `settings.json`.** Everything else under `Application Support/Deck`
/// is a snapshot the agent rebuilds within one 60s tick — the thirteen
/// `*.json` snapshots, the `fetch-*.json` statuses, and `opencode-cursor.json`
/// (whose loss costs one full resync and nothing else). Copying eleven files
/// that expire in a minute is work that can fail for no benefit.
///
/// **The old container is read, never written, and above all never deleted.**
/// `rm -rf` on a container cannot remove its SIP-protected
/// `.com.apple.containermanagerd.metadata.plist`; because that survives,
/// containermanagerd still believes the container is provisioned and never
/// rebuilds the skeleton, after which every widget renders blank forever. See
/// the CLAUDE.md trap and `scripts/container-repair.sh`.
///
/// Safe to call on every launch from both the app and `DeckAgent`: it is
/// idempotent and never overwrites an existing `settings.json`.
enum ContainerMigration {
    enum Outcome: Equatable {
        case migrated
        case skipped(ContainerMigrationPolicy.SkipReason)
        case failed(String)
    }

    private static let settingsFile = "settings.json"

    /// The pre-rename container's settings directory.
    ///
    /// Deliberately built the unsandboxed way: only the host app and the agent
    /// run this, and neither is sandboxed. The widget extension never migrates —
    /// inside its sandbox `homeDirectoryForCurrentUser` *is* the container, and
    /// it has no view of any other.
    static var legacyDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/\(DeckBundle.Legacy.widgetsID)/Data/Library/Application Support/Deck",
                isDirectory: true
            )
    }

    @discardableResult
    static func run(
        legacyDirectory: URL = ContainerMigration.legacyDirectory,
        currentDirectory: URL = DeckSettings.containerDirectory,
        fileManager: FileManager = .default
    ) -> Outcome {
        let legacySettings = legacyDirectory.appendingPathComponent(settingsFile)
        let currentSettings = currentDirectory.appendingPathComponent(settingsFile)

        let decision = ContainerMigrationPolicy.decide(
            identifiersDiffer: legacyDirectory.standardizedFileURL != currentDirectory.standardizedFileURL,
            legacyContainerExists: fileManager.fileExists(atPath: legacyDirectory.path),
            legacySettingsExists: fileManager.fileExists(atPath: legacySettings.path),
            currentSettingsExists: fileManager.fileExists(atPath: currentSettings.path)
        )

        guard case .copy = decision else {
            if case .skip(let reason) = decision { return .skipped(reason) }
            return .skipped(.sameContainer)
        }

        do {
            try fileManager.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacySettings, to: currentSettings)
            // `copyItem` carries the source's mode, but the source may predate
            // Deck tightening it (files written before 0600 keep their mode
            // until rewritten), so set it rather than trusting the copy.
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: currentSettings.path
            )
            return .migrated
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
