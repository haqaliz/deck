import Foundation

/// Everything one fetch needs from a credential, with the account already
/// resolved. Loaders take this instead of reading a token off their own
/// settings struct.
struct ResolvedCredential: Equatable {
    var token: String
    var organization: String = ""
    /// Azure DevOps only, and plural: one account covers up to
    /// `AzureAccountProjects.maxProjects` projects in its organization.
    var projects: [String] = []
    var serverURL: String = ""
}

extension DeckSettings {
    /// The credential a slot should fetch with, or `nil` when it is not
    /// configured.
    ///
    /// Order matters. A resolved account always wins. A slot whose `accountID`
    /// **dangles** — the account was deleted or is of the wrong kind — is not
    /// configured, and deliberately does *not* fall back: a dangling id means
    /// the user deleted something, not that a stale token should be revived.
    /// Only a slot with no selection at all consults the legacy field.
    func credential(for slot: CredentialSlot) -> ResolvedCredential? {
        if let account = account(for: slot) {
            guard !account.token.isEmpty else { return nil }
            return ResolvedCredential(
                token: account.token,
                organization: account.organization,
                projects: account.projects,
                serverURL: account.serverURL
            )
        }
        guard accountID(for: slot) == nil else { return nil }
        let legacy = legacyCredential(for: slot)
        return legacy.token.isEmpty ? nil : legacy
    }

    /// The pre-accounts shape, for a Deck that was upgraded but never opened.
    ///
    /// `DeckAgent` reads settings and never writes them, so it can run for
    /// weeks on a file the migration has not touched. Without this, upgrading
    /// and not opening Deck silently unconfigures four widgets. It goes inert
    /// on its own once the migration runs: the legacy field is blanked and the
    /// legacy keychain item deleted, so there is nothing left to return.
    func legacyCredential(for slot: CredentialSlot) -> ResolvedCredential {
        switch slot {
        case .openbox:
            return ResolvedCredential(token: openbox.token, serverURL: openbox.serverURL ?? "")
        case .shipbox:
            return ResolvedCredential(token: shipbox.token)
        case .taskbox:
            return ResolvedCredential(
                token: taskbox.token,
                organization: taskbox.organization,
                projects: AzureAccountProjects.normalise([taskbox.project])
            )
        case .prboxGitHub:
            return ResolvedCredential(token: prbox.github.token)
        case .prboxAzure:
            return ResolvedCredential(
                token: prbox.azure.token,
                organization: prbox.azure.organization,
                projects: AzureAccountProjects.normalise([prbox.azure.project])
            )
        }
    }
}

/// What a slot should do this tick.
///
/// `off` and `notConfigured` are deliberately different answers. Nothing
/// selected is a switch the user left alone; a selection that no longer
/// resolves is something to report. And `unavailable` is neither — it is the
/// locked-keychain case, which must never read as "you forgot to paste a
/// token".
enum CredentialGate: Equatable {
    case fetch(ResolvedCredential)
    case notConfigured
    case unavailable
    case off

    /// What to record for the slot's `FetchSource`, or `nil` when the fetch
    /// itself will record the outcome.
    var outcome: FetchOutcome? {
        switch self {
        case .fetch: nil
        case .notConfigured: .notConfigured
        case .unavailable: .credentialsUnavailable
        // `ok` rather than nothing: it is what clears a failure left behind
        // from when the provider was on.
        case .off: .ok
        }
    }
}

extension DeckSettings {
    /// The one decision table, so the agent and the host app cannot drift.
    ///
    /// - Parameter unavailable: account ids whose keychain read **failed**,
    ///   from `hydrateAccounts(from:)`. Not the same as absent.
    func gate(_ slot: CredentialSlot, unavailable: Set<String>) -> CredentialGate {
        if let id = accountID(for: slot), unavailable.contains(id) { return .unavailable }

        guard let credential = credential(for: slot) else {
            // Nothing selected and nothing left over: the user simply has not
            // turned this on.
            return accountID(for: slot) == nil && legacyCredential(for: slot).token.isEmpty
                ? .off
                : .notConfigured
        }

        guard slot.kind == .azure else { return .fetch(credential) }

        // Azure needs a target as much as it needs a token, and the loader
        // would only fail later with something less legible.
        let organization = credential.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        // The last gate before a loader: a duplicate here would double every
        // row its project owns, and a sixth would blow the slot budget.
        let projects = AzureAccountProjects.normalise(credential.projects)
        guard !organization.isEmpty, !projects.isEmpty else { return .notConfigured }

        return .fetch(ResolvedCredential(
            token: credential.token,
            organization: organization,
            projects: projects,
            serverURL: credential.serverURL
        ))
    }

    /// `gate(_:unavailable:)` that also understands a locked keychain on the
    /// **pre-accounts** items.
    ///
    /// `DeckAgent` reads settings and never writes them, so it can run for a
    /// long time on a file the migration has not touched. Without this, a
    /// locked login keychain would read there as "not configured" — the exact
    /// collapse the `credentialsUnavailable` outcome exists to prevent.
    func gate(
        _ slot: CredentialSlot,
        unavailableAccounts: Set<String>,
        unavailableLegacySecrets: Set<DeckSecret>
    ) -> CredentialGate {
        if accountID(for: slot) == nil, unavailableLegacySecrets.contains(slot.legacySecret) {
            return .unavailable
        }
        return gate(slot, unavailable: unavailableAccounts)
    }

    /// Whether OpenBox reads a remote opencode server rather than the local
    /// database — **decidable inside the widget extension**, which has no
    /// keychain access, because it turns only on non-secret fields.
    ///
    /// The rule is now the picker: no account means the local database, an
    /// account with a server URL means remote. Clearer than the old convention,
    /// where the emptiness of a text field was load-bearing.
    var openBoxUsesRemoteServer: Bool {
        if let account = account(for: .openbox) { return !account.serverURL.isEmpty }
        // A dangling selection is not configured; only an untouched slot may
        // consult the pre-accounts field.
        guard accountID(for: .openbox) == nil else { return false }
        return !(openbox.serverURL ?? "").isEmpty
    }

    /// Whether PRBox's GitHub provider is on. The picker replaced the Enable
    /// toggle, so a selected account *is* "on".
    var prBoxGitHubIsOn: Bool { providerIsOn(.prboxGitHub, legacyEnabled: prbox.github.enabled) }

    /// Whether PRBox's Azure DevOps provider is on.
    var prBoxAzureIsOn: Bool { providerIsOn(.prboxAzure, legacyEnabled: prbox.azure.enabled) }

    private func providerIsOn(_ slot: CredentialSlot, legacyEnabled: Bool) -> Bool {
        if account(for: slot) != nil { return true }
        guard accountID(for: slot) == nil else { return false }
        // Before migration the toggle is still the truth, and the agent may
        // well be fetching. The migration clears it, so this goes inert.
        return legacyEnabled
    }
}

/// Turns the five welded credentials into accounts, once.
///
/// Host-app only: `DeckAgent` never writes settings, which is what lets it keep
/// working from an unmigrated file until the user opens Deck.
enum CredentialsMigration {

    /// Write → **read back to confirm** → assign the slot → *only then* delete
    /// the legacy item. The order is the safety property: a failure at any
    /// step leaves `settings` untouched, deletes nothing, and simply retries at
    /// the next launch.
    ///
    /// - Returns: `true` when anything was created and the caller should save.
    @discardableResult
    static func migrate(
        _ settings: inout DeckSettings,
        write: (String, String) -> OSStatus = { DeckKeychain.write(accountID: $0, value: $1) },
        readBack: (String) -> SecretRead = { DeckKeychain.read(accountID: $0) },
        deleteLegacy: (DeckSecret) -> OSStatus = { DeckKeychain.delete($0) },
        makeID: () -> String = { UUID().uuidString.lowercased() }
    ) -> Bool {
        guard settings.credentials.accounts.isEmpty,
              CredentialSlot.allCases.allSatisfy({ settings.accountID(for: $0) == nil })
        else { return false }

        var created: [CredentialAccount] = []
        var assignments: [(CredentialSlot, String)] = []
        var migrated: [CredentialSlot] = []

        for slot in CredentialSlot.allCases {
            let fields = settings.legacyCredential(for: slot)
            guard !fields.token.isEmpty else { continue }

            // Collapse only when *every* field matches. A shared GitHub token
            // becomes one account; the same Azure PAT against two projects
            // stays two, because the project is part of the account.
            if let twin = created.first(where: { $0.kind == slot.kind && matches($0, fields) }) {
                if isSelectable(slot, in: settings) { assignments.append((slot, twin.id)) }
                migrated.append(slot)
                continue
            }

            var account = CredentialAccount(id: makeID(), kind: slot.kind)
            account.token = fields.token
            account.organization = fields.organization
            account.projects = fields.projects
            account.serverURL = fields.serverURL

            guard write(account.id, account.token) == errSecSuccess,
                  readBack(account.id) == .found(account.token)
            else { continue }

            account.label = label(for: account, slot: slot, taken: created.map(\.label))
            created.append(account)
            if isSelectable(slot, in: settings) { assignments.append((slot, account.id)) }
            migrated.append(slot)
        }

        guard !created.isEmpty else { return false }

        settings.credentials.accounts = created
        for (slot, id) in assignments {
            settings.setAccountID(id, for: slot)
        }
        for slot in migrated {
            settings.setSecret("", for: slot.legacySecret)
            clearMovedFields(of: slot, in: &settings)
            _ = deleteLegacy(slot.legacySecret)
        }
        return true
    }

    /// The connection fields belong to the account now (D2). A copy left
    /// behind on the widget is a stale duplicate that outlives the account it
    /// was copied from, and it would keep answering the pre-migration
    /// fallbacks after the picker became the real control.
    ///
    /// Only ever called for a slot whose account is already confirmed stored.
    private static func clearMovedFields(of slot: CredentialSlot, in settings: inout DeckSettings) {
        switch slot {
        case .openbox:
            settings.openbox.serverURL = nil
        case .shipbox:
            break
        case .taskbox:
            settings.taskbox.organization = ""
            settings.taskbox.project = ""
        case .prboxGitHub:
            settings.prbox.github.enabled = false
        case .prboxAzure:
            settings.prbox.azure.enabled = false
            settings.prbox.azure.organization = ""
            settings.prbox.azure.project = ""
        }
    }

    /// Critique R2: PRBox's providers each had an Enable toggle, defaulting to
    /// off, and a token can sit behind a provider the user deliberately
    /// switched off. Since a selected account now *means* enabled, migrating
    /// that selection would silently start fetching again. The account is
    /// still created — never lose a token — it just isn't selected.
    private static func isSelectable(_ slot: CredentialSlot, in settings: DeckSettings) -> Bool {
        switch slot {
        case .prboxGitHub: return settings.prbox.github.enabled
        case .prboxAzure: return settings.prbox.azure.enabled
        case .openbox, .shipbox, .taskbox: return true
        }
    }

    private static func matches(_ account: CredentialAccount, _ fields: ResolvedCredential) -> Bool {
        account.token == fields.token
            && account.organization == fields.organization
            && account.projects == fields.projects
            && account.serverURL == fields.serverURL
    }

    /// Name it after whatever identifies it, then disambiguate. All of this is
    /// renamable afterwards — it only has to be recognisable on first sight.
    private static func label(
        for account: CredentialAccount,
        slot: CredentialSlot,
        taken: [String]
    ) -> String {
        var base: String
        switch account.kind {
        case .azure:
            base = account.organization
        case .opencode:
            base = URL(string: account.serverURL)?.host ?? ""
        case .github:
            base = ""
        }
        if base.isEmpty { base = account.kind.displayName }
        guard taken.contains(base) else { return base }

        let withWidget = "\(base) (\(slot.widgetName))"
        guard taken.contains(withWidget) else { return withWidget }

        var counter = 2
        while taken.contains("\(withWidget) \(counter)") { counter += 1 }
        return "\(withWidget) \(counter)"
    }
}
