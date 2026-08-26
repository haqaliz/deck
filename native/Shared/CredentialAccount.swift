import Foundation

/// The kinds of backend Deck holds a credential for.
///
/// Raw values are **stable on disk** — they are written into `settings.json`
/// and a rename silently drops every account of that kind.
enum CredentialKind: String, Codable, CaseIterable {
    case github
    case azure
    case opencode

    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .azure: "Azure DevOps"
        case .opencode: "opencode"
        }
    }

    var systemImage: String {
        switch self {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .azure: "square.stack.3d.up"
        case .opencode: "server.rack"
        }
    }

    /// Base filename of this provider's brand artwork in the app bundle.
    ///
    /// The real marks, converted from the vendors' own SVGs to vector PDFs.
    /// `systemImage` stays as the fallback for when the artwork cannot be
    /// loaded, and for the sandboxed widget extension, which does not ship it.
    var assetName: String {
        switch self {
        case .github: "provider-github"
        case .azure: "provider-azure"
        case .opencode: "provider-opencode"
        }
    }

    /// GitHub's mark is black on light and white on dark; opencode's inverts
    /// the same way. Azure DevOps ships one coloured mark that reads on both,
    /// but carries both names so callers never have to special-case it.
    func assetName(dark: Bool) -> String {
        "\(assetName)-\(dark ? "dark" : "light")"
    }

    /// What this provider says the account gives Deck, under its name in the
    /// list — the same shape as Internet Accounts' "Mail, Contacts, Calendars".
    var summary: String {
        CredentialSlot.allCases
            .filter { $0.kind == self }
            .map(\.widgetName)
            .reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }
            .joined(separator: ", ")
    }

    /// What someone might type looking for this provider, beyond its name.
    ///
    /// Azure DevOps has been VSTS and ADO within living memory, and people
    /// reach for whichever name they learned it under.
    var searchTerms: [String] {
        switch self {
        case .github: ["gh"]
        case .azure: ["ado", "vsts", "devops", "tfs"]
        case .opencode: ["oc", "sst"]
        }
    }

    /// The providers to offer for a search query, in declared order — the list
    /// must not reshuffle as the user types.
    static func matching(_ query: String) -> [CredentialKind] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return allCases }
        return allCases.filter { kind in
            kind.displayName.lowercased().contains(needle)
                || kind.searchTerms.contains { $0.contains(needle) }
        }
    }
}

/// One credential the user manages in the Credentials tab.
///
/// The `token` is **in memory only**. `encode(to:)` omits it outright rather
/// than relying on a scrub at the file boundary the way the five legacy fields
/// do: that list is fixed and a human can audit it, an unbounded list of
/// accounts is not. `DeckSettings.scrubbedOfSecrets()` still blanks them, so
/// there are two independent guarantees rather than one.
struct CredentialAccount: Codable, Equatable, Identifiable {
    /// Opaque, generated once, never rewritten. It is the keychain item name,
    /// so changing it strands whatever the user already pasted.
    var id: String
    var kind: CredentialKind
    /// User-facing and renamable. Not unique — pickers disambiguate with
    /// `subtitle` instead, because renaming under a uniqueness constraint is
    /// miserable.
    var label: String = ""

    /// Azure DevOps only.
    var organization: String = ""
    /// Azure DevOps only.
    var project: String = ""
    /// opencode only. Its emptiness is what makes OpenBox read the local
    /// database instead of a remote server.
    var serverURL: String = ""

    /// Never encoded. Hydrated from the keychain, host-side only.
    var token: String = ""

    // Verification results. Non-secret, cached in `settings.json`.
    var verifiedIdentity: String?
    /// The `connectionData` GUID. **Display only** — `HostAzurePRLoader` keeps
    /// resolving identity live, because Azure answers 200 with every active
    /// pull request in the project for an identity it cannot parse, and a GUID
    /// cached against a since-replaced token would render the whole team's work
    /// as the user's own with nothing in the response saying so.
    var azureIdentityID: String?
    var verifiedAt: Date?

    init(id: String = UUID().uuidString.lowercased(), kind: CredentialKind, label: String = "") {
        self.id = id
        self.kind = kind
        self.label = label
    }

    /// Tolerant in every field that has a sane default. `id` and `kind` have
    /// none — an account without them cannot be stored or resolved — so those
    /// throw, and `CredentialsSettings` drops the entry rather than letting the
    /// throw reach `DeckSettings.load()`'s `?? DeckSettings()` fallback and
    /// reset every setting in the file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "account id must not be empty"
            )
        }
        kind = try c.decode(CredentialKind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        organization = try c.decodeIfPresent(String.self, forKey: .organization) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        verifiedIdentity = try c.decodeIfPresent(String.self, forKey: .verifiedIdentity)
        azureIdentityID = try c.decodeIfPresent(String.self, forKey: .azureIdentityID)
        verifiedAt = try c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        token = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(label, forKey: .label)
        try c.encode(organization, forKey: .organization)
        try c.encode(project, forKey: .project)
        try c.encode(serverURL, forKey: .serverURL)
        try c.encodeIfPresent(verifiedIdentity, forKey: .verifiedIdentity)
        try c.encodeIfPresent(azureIdentityID, forKey: .azureIdentityID)
        try c.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
        // `token` is deliberately absent.
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, organization, project, serverURL
        case verifiedIdentity, azureIdentityID, verifiedAt
    }
}

/// Every account the user has configured, in display order.
struct CredentialsSettings: Codable, Equatable {
    var accounts: [CredentialAccount] = []

    init(accounts: [CredentialAccount] = []) {
        self.accounts = accounts
    }

    /// Lossy on purpose: one unreadable entry — an unknown `kind` from a newer
    /// build, a missing `id` — is dropped, and its siblings survive.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try c.decodeIfPresent([LossyAccount].self, forKey: .accounts) ?? []
        accounts = entries.compactMap(\.account)
    }

    private struct LossyAccount: Decodable {
        let account: CredentialAccount?

        init(from decoder: Decoder) throws {
            account = try? CredentialAccount(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey { case accounts }
}

/// The places a widget consumes a credential. Replaces `DeckSecret` at every
/// consumption site; `DeckSecret` survives only for the one-way migration.
enum CredentialSlot: String, CaseIterable {
    case openbox
    case shipbox
    case taskbox
    case prboxGitHub
    case prboxAzure

    var kind: CredentialKind {
        switch self {
        case .openbox: .opencode
        case .shipbox, .prboxGitHub: .github
        case .taskbox, .prboxAzure: .azure
        }
    }

    /// The chip this slot's failures land on. Keeping this mapping in one place
    /// is what stops `credentialsUnavailable` appearing on the wrong widget.
    var source: FetchSource {
        switch self {
        case .openbox: .opencodeRemote
        case .shipbox: .shipbox
        case .taskbox: .taskbox
        case .prboxGitHub: .prboxGitHub
        case .prboxAzure: .prboxAzure
        }
    }

    /// The widget this slot belongs to. Shorter than `displayName` because it
    /// is used as a label suffix, where "GitHub (PRBox (GitHub))" would be
    /// absurd.
    var widgetName: String {
        switch self {
        case .openbox: "OpenBox"
        case .shipbox: "ShipBox"
        case .taskbox: "TaskBox"
        case .prboxGitHub, .prboxAzure: "PRBox"
        }
    }

    /// The pre-accounts credential this slot used to own. Read exactly once,
    /// by the migration; nothing else should reach for it.
    var legacySecret: DeckSecret {
        switch self {
        case .openbox: .openboxToken
        case .shipbox: .shipboxToken
        case .taskbox: .taskboxToken
        case .prboxGitHub: .prboxGitHubToken
        case .prboxAzure: .prboxAzureToken
        }
    }

    /// As shown in the "Used by" caption and the delete confirmation.
    var displayName: String {
        switch self {
        case .openbox: "OpenBox"
        case .shipbox: "ShipBox"
        case .taskbox: "TaskBox"
        case .prboxGitHub: "PRBox (GitHub)"
        case .prboxAzure: "PRBox (Azure DevOps)"
        }
    }
}
