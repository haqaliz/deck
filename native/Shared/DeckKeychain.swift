import Foundation
import Security

/// The five API credentials Deck stores outside `settings.json`.
///
/// Raw values are the keychain account names and are **stable on disk** — a
/// rename strands whatever the user already pasted, with no error anywhere.
enum DeckSecret: String, CaseIterable {
    case openboxToken = "openbox.token"
    case shipboxToken = "shipbox.token"
    case taskboxToken = "taskbox.token"
    case prboxGitHubToken = "prbox.github.token"
    case prboxAzureToken = "prbox.azure.token"
}

/// The result of one keychain read.
///
/// `absent` and `failed` must never be collapsed into each other. Every
/// configured-check in Deck is `token.isEmpty` / `isUsable`, so a failure that
/// arrives as an empty string is indistinguishable from "the user never pasted
/// one" — and the widget then tells them to paste a token they already pasted.
enum SecretRead: Equatable {
    case found(String)
    case absent
    case failed(OSStatus)
}

/// Deck's credential store: the **legacy (file-based) login keychain**.
///
/// Deliberately not the data protection keychain. That one requires a
/// `keychain-access-groups` entitlement (`SecItemAdd` returns `-34018`
/// without it), and signing Deck.app or DeckAgent *with* that entitlement makes
/// the process die at launch with SIGKILL — there is no provisioning profile to
/// authorise it, and a `type: tool` target has nowhere to embed one. Measured;
/// see `docs/planning/keychain-tokens/probe.md` and the CLAUDE.md trap.
///
/// The legacy keychain needs no entitlement, and a separately-signed DeckAgent
/// reads what Deck.app wrote from inside a launchd job without a prompt.
enum DeckKeychain {
    /// Overridable so tests never touch the real items.
    static let defaultService = "com.deck.app"

    static func read(_ secret: DeckSecret, service: String = defaultService) -> SecretRead {
        var query = baseQuery(secret, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                // Present but unreadable is a failure, not an absence.
                return .failed(errSecDecode)
            }
            return .found(value)
        case errSecItemNotFound:
            return .absent
        default:
            return .failed(status)
        }
    }

    /// Add-or-update. Returns `errSecSuccess` on success.
    @discardableResult
    static func write(_ secret: DeckSecret, value: String, service: String = defaultService) -> OSStatus {
        let query = baseQuery(secret, service: service)
        let payload = Data(value.utf8)

        let status = SecItemAdd(
            query.merging([kSecValueData as String: payload]) { _, new in new } as CFDictionary,
            nil
        )
        guard status == errSecDuplicateItem else { return status }
        return SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: payload] as CFDictionary
        )
    }

    /// Removes one secret. A secret that was never stored is a success.
    @discardableResult
    static func delete(_ secret: DeckSecret, service: String = defaultService) -> OSStatus {
        let status = SecItemDelete(baseQuery(secret, service: service) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }

    /// Reads all five in one pass.
    static func readAll(service: String = defaultService) -> [DeckSecret: SecretRead] {
        var out: [DeckSecret: SecretRead] = [:]
        for secret in DeckSecret.allCases {
            out[secret] = read(secret, service: service)
        }
        return out
    }

    private static func baseQuery(_ secret: DeckSecret, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secret.rawValue,
        ]
    }
}

/// Moves credentials that predate the keychain out of `settings.json`.
///
/// Runs once at app launch and is idempotent — a second run finds nothing to
/// move. `DeckAgent` never runs it: the agent does not write settings, which is
/// what lets it keep working from an unmigrated file until the user opens Deck.
enum DeckSecretsMigration {
    /// Write → **read back to confirm** → only then blank the field.
    ///
    /// The order is the safety property. Blanking first and writing second
    /// loses the token outright if the keychain write fails; this way a failure
    /// leaves `settings.json` exactly as it was and the migration simply
    /// retries at the next launch.
    ///
    /// - Returns: `true` when at least one field was moved and the caller
    ///   should save.
    @discardableResult
    static func migrate(
        _ settings: inout DeckSettings,
        write: (DeckSecret, String) -> OSStatus = { DeckKeychain.write($0, value: $1) },
        readBack: (DeckSecret) -> SecretRead = { DeckKeychain.read($0) }
    ) -> Bool {
        var moved = false
        for secret in DeckSecret.allCases {
            let value = settings.secretValue(secret)
            guard !value.isEmpty else { continue }
            guard write(secret, value) == errSecSuccess else { continue }
            guard readBack(secret) == .found(value) else { continue }
            settings.setSecret("", for: secret)
            moved = true
        }
        return moved
    }
}
