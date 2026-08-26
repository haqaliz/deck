import Foundation

/// What a successful Verify learned about an account.
struct CredentialIdentity: Equatable {
    /// Who the credential belongs to: a GitHub login, an Azure display name,
    /// or a word about the opencode server.
    let identity: String
    /// A second line when there is one — granted scopes, a session count.
    let detail: String?
    /// Azure only. **Display only**: `HostAzurePRLoader` keeps resolving
    /// identity live per fetch. Azure answers 200 with every active pull
    /// request in the project for an identity it cannot parse, and nothing in
    /// the response says the filter was ignored, so a GUID cached against a
    /// since-replaced token would render the whole team's work as the user's.
    let azureIdentityID: String?
}

extension CredentialAccount {
    /// Everything a verification depended on, as one comparable value.
    ///
    /// A rename must not invalidate a verification; a new token, a new
    /// organization or a new server must.
    var credentialFingerprint: String {
        [token, organization, project, serverURL].joined(separator: "\u{0}")
    }

    mutating func recordVerification(_ identity: CredentialIdentity, at date: Date) {
        verifiedIdentity = identity.identity
        azureIdentityID = identity.azureIdentityID
        verifiedAt = date
    }

    mutating func clearVerification() {
        verifiedIdentity = nil
        azureIdentityID = nil
        verifiedAt = nil
    }

    /// Drops a verification whose credential has since been edited. Stale is
    /// worse than absent here: a green "signed in as…" against a token that no
    /// longer exists is a lie the user has no way to spot.
    mutating func clearVerificationIfCredentialChanged(from fingerprint: String) {
        guard credentialFingerprint != fingerprint else { return }
        clearVerification()
    }
}

// MARK: - Parsers (pure)

enum GitHubUserParser {
    /// The token owner's login, or nil when the payload cannot be read. An
    /// empty login is nil: "verified as nobody" is not a verification.
    static func parse(_ data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let login = root["login"] as? String,
            !login.isEmpty
        else { return nil }
        return login
    }

    /// The granted scopes, which live only in the `X-OAuth-Scopes` response
    /// header. A fine-grained PAT omits the header entirely, and that is a
    /// perfectly good token — an empty list is not a failure.
    static func scopes(header: String?) -> [String] {
        (header ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

enum AzureConnectionParser {
    /// The PAT owner, or nil when the payload carries no usable identity.
    ///
    /// Shares the id rule with `ConnectionDataParser`, which PRBox's fetch
    /// uses: no id — or an empty one — means unreadable, never "verified".
    static func parse(_ data: Data) -> CredentialIdentity? {
        guard let id = ConnectionDataParser.parse(data) else { return nil }
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let user = root?["authenticatedUser"] as? [String: Any]
        let name = (user?["providerDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0}
        return CredentialIdentity(identity: name ?? id, detail: nil, azureIdentityID: id)
    }
}

// MARK: - Probes (host only — unsandboxed)

/// Verifies one account against its provider, on demand.
///
/// Manual by design: the settings window must not start making network requests
/// just by being opened, the same rule the widgets follow.
enum CredentialVerifier {
    enum VerifyError: Error {
        case notConfigured
        case badResponse
        case serverError(Int)
        case transport(String)
    }

    static func verify(_ account: CredentialAccount) async throws -> CredentialIdentity {
        guard !account.token.isEmpty else { throw VerifyError.notConfigured }
        switch account.kind {
        case .github: return try await github(token: account.token)
        case .azure: return try await azure(account)
        case .opencode: return try await opencode(account)
        }
    }

    private static func github(token: String) async throws -> CredentialIdentity {
        guard let url = URL(string: "https://api.github.com/user") else {
            throw VerifyError.badResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await send(request)
        guard let login = GitHubUserParser.parse(data) else { throw VerifyError.badResponse }
        let scopes = GitHubUserParser.scopes(
            header: response.value(forHTTPHeaderField: "X-OAuth-Scopes")
        )
        return CredentialIdentity(
            identity: login,
            detail: scopes.isEmpty ? nil : scopes.joined(separator: ", "),
            azureIdentityID: nil
        )
    }

    private static func azure(_ account: CredentialAccount) async throws -> CredentialIdentity {
        let target = try AzureTarget.normalise(
            organization: account.organization,
            project: account.project.isEmpty ? "_" : account.project
        )
        guard let url = URL(string: "\(target.orgBase)/_apis/connectionData?api-version=7.1-preview") else {
            throw VerifyError.badResponse
        }
        var request = URLRequest(url: url)
        // HTTP Basic with an empty username, the same shape the two Azure
        // loaders use. Sent only to dev.azure.com over TLS.
        let auth = "Basic " + Data(":\(account.token)".utf8).base64EncodedString()
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, _) = try await send(request)
        guard let identity = AzureConnectionParser.parse(data) else { throw VerifyError.badResponse }
        return identity
    }

    private static func opencode(_ account: CredentialAccount) async throws -> CredentialIdentity {
        guard !account.serverURL.isEmpty else { throw VerifyError.notConfigured }
        // Success *is* the probe: the same call OpenBox makes every tick, so a
        // green Verify means the widget will work, not merely that a host
        // answered a ping.
        let snapshot = try await RemoteOpenCodeLoader.load(
            serverURL: account.serverURL, token: account.token
        )
        return CredentialIdentity(
            identity: "reachable",
            detail: "\(snapshot.sessions) sessions today",
            azureIdentityID: nil
        )
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw VerifyError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw VerifyError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            throw VerifyError.serverError(http.statusCode)
        }
        return (data, http)
    }
}
