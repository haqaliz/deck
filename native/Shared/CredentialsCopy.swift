import Foundation

/// The strings the Credentials tab shows. Kept out of the view so they can be
/// pinned by tests rather than eyeballed.
enum CredentialsCopy {

    /// What tells two accounts apart at a glance.
    ///
    /// Labels are deliberately not unique — renaming under a uniqueness
    /// constraint is miserable — so every row and every picker entry carries
    /// this second line. It draws only on non-secret fields.
    static func subtitle(for account: CredentialAccount) -> String {
        // Last resort, but it always says *something*: in a picker, two
        // unverified accounts with the same label are otherwise
        // indistinguishable.
        identifyingSubtitle(for: account) ?? String(account.id.prefix(6))
    }

    /// The second line of an account's row in the list.
    ///
    /// `subtitle(for:)`'s id fragment is *disambiguation*, not information, so
    /// it appears only when another account would otherwise read identically.
    /// On the common case — one unverified GitHub account — the row says who
    /// uses it and nothing else.
    static func rowSubtitle(
        for account: CredentialAccount,
        among all: [CredentialAccount],
        usedBy slots: [CredentialSlot]
    ) -> String {
        var parts: [String] = []
        if let identifying = identifyingSubtitle(for: account) {
            parts.append(identifying)
        } else if needsIdToDisambiguate(account, among: all) {
            parts.append(String(account.id.prefix(6)))
        }
        parts.append(usedBy(slots))
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The detail page's header subtitle: what the account *connects to*,
    /// never who it belongs to.
    ///
    /// The identity is already the header's title line, and repeating it
    /// underneath reads as a rendering bug.
    static func connectionSubtitle(for account: CredentialAccount) -> String {
        switch account.kind {
        case .azure:
            let organization = account.organization.trimmingCharacters(in: .whitespaces)
            let project = account.project.trimmingCharacters(in: .whitespaces)
            if !organization.isEmpty, !project.isEmpty { return "\(organization) / \(project)" }
            if !organization.isEmpty { return organization }
        case .opencode:
            if let host = URL(string: account.serverURL)?.host, !host.isEmpty { return host }
        case .github:
            break
        }
        return account.kind.displayName
    }

    /// Whatever names the connection, or nil when nothing does yet.
    private static func identifyingSubtitle(for account: CredentialAccount) -> String? {
        switch account.kind {
        case .azure:
            let organization = account.organization.trimmingCharacters(in: .whitespaces)
            let project = account.project.trimmingCharacters(in: .whitespaces)
            if !organization.isEmpty, !project.isEmpty { return "\(organization) / \(project)" }
            if !organization.isEmpty { return organization }
        case .opencode:
            if let host = URL(string: account.serverURL)?.host, !host.isEmpty { return host }
        case .github:
            break
        }
        if let identity = account.verifiedIdentity, !identity.isEmpty { return identity }
        return nil
    }

    private static func needsIdToDisambiguate(
        _ account: CredentialAccount,
        among all: [CredentialAccount]
    ) -> Bool {
        all.contains { other in
            other.id != account.id
                && other.kind == account.kind
                && other.label == account.label
                && identifyingSubtitle(for: other) == nil
        }
    }

    /// Which widgets read this account, for the row caption.
    static func usedBy(_ slots: [CredentialSlot]) -> String {
        slots.isEmpty ? "Unused" : slots.map(\.displayName).joined(separator: ", ")
    }

    /// The delete confirmation. It names what stops working rather than asking
    /// "are you sure?" about something the user cannot see the consequences of.
    static func deleteMessage(label: String, slots: [CredentialSlot]) -> String {
        let removal = "Its token is removed from the keychain."
        guard !slots.isEmpty else { return "\(removal) Nothing is using it." }
        let names = list(slots.map(\.displayName))
        let verb = slots.count == 1 ? "uses" : "use"
        return "\(names) \(verb) it and will stop fetching until you pick another account. \(removal)"
    }

    /// The per-account verification caption.
    static func verification(for account: CredentialAccount) -> String {
        guard let identity = account.verifiedIdentity, !identity.isEmpty else { return "Not verified" }
        guard let at = account.verifiedAt else { return identity }
        return "\(identity) · verified \(timeFormatter.string(from: at))"
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
