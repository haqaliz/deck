import XCTest

/// Write → read back → blank. The order is what stops a keychain failure from
/// destroying the only copy of a token (`prd-critique.md` C4).
final class DeckSecretsMigrationTests: XCTestCase {

    private func withToken(_ value: String) -> DeckSettings {
        var s = DeckSettings()
        s.shipbox.token = value
        return s
    }

    func testMovesAValueOutOfTheFileAndIntoTheKeychain() {
        var store: [DeckSecret: String] = [:]
        var settings = withToken("ghp_abc")

        let moved = DeckSecretsMigration.migrate(
            &settings,
            write: { store[$0] = $1; return errSecSuccess },
            readBack: { store[$0].map { .found($0) } ?? .absent }
        )

        XCTAssertTrue(moved)
        XCTAssertEqual(store[.shipboxToken], "ghp_abc")
        XCTAssertEqual(settings.shipbox.token, "", "the file must not keep the secret")
    }

    func testIsIdempotent() {
        var store: [DeckSecret: String] = [:]
        var settings = withToken("ghp_abc")
        let write: (DeckSecret, String) -> OSStatus = { store[$0] = $1; return errSecSuccess }
        let readBack: (DeckSecret) -> SecretRead = { store[$0].map { .found($0) } ?? .absent }

        DeckSecretsMigration.migrate(&settings, write: write, readBack: readBack)
        let second = DeckSecretsMigration.migrate(&settings, write: write, readBack: readBack)

        XCTAssertFalse(second, "a second run has nothing to move")
        XCTAssertEqual(store[.shipboxToken], "ghp_abc")
    }

    func testEmptyFieldsAreNotWritten() {
        var written: [DeckSecret] = []
        var settings = DeckSettings()

        let moved = DeckSecretsMigration.migrate(
            &settings,
            write: { s, _ in written.append(s); return errSecSuccess },
            readBack: { _ in .absent }
        )

        XCTAssertFalse(moved)
        XCTAssertTrue(written.isEmpty, "an empty token is not a credential")
    }

    // MARK: - The safety property

    func testAFailedWriteLeavesTheFileUntouched() {
        var settings = withToken("ghp_abc")

        let moved = DeckSecretsMigration.migrate(
            &settings,
            write: { _, _ in errSecIO },
            readBack: { _ in .absent }
        )

        XCTAssertFalse(moved)
        XCTAssertEqual(settings.shipbox.token, "ghp_abc", "the token was the only copy")
    }

    /// A write that reports success but stored nothing readable must not be
    /// trusted — that is exactly when blanking would lose the token.
    func testAFailedReadBackLeavesTheFileUntouched() {
        var settings = withToken("ghp_abc")

        let moved = DeckSecretsMigration.migrate(
            &settings,
            write: { _, _ in errSecSuccess },
            readBack: { _ in .failed(errSecInteractionNotAllowed) }
        )

        XCTAssertFalse(moved)
        XCTAssertEqual(settings.shipbox.token, "ghp_abc")
    }

    func testAReadBackThatDisagreesLeavesTheFileUntouched() {
        var settings = withToken("ghp_abc")

        let moved = DeckSecretsMigration.migrate(
            &settings,
            write: { _, _ in errSecSuccess },
            readBack: { _ in .found("something-else") }
        )

        XCTAssertFalse(moved)
        XCTAssertEqual(settings.shipbox.token, "ghp_abc")
    }

    func testOneFailureDoesNotBlockTheOthers() {
        var store: [DeckSecret: String] = [:]
        var settings = DeckSettings()
        settings.shipbox.token = "ship"
        settings.taskbox.token = "task"

        DeckSecretsMigration.migrate(
            &settings,
            write: { secret, value in
                guard secret != .shipboxToken else { return errSecIO }
                store[secret] = value
                return errSecSuccess
            },
            readBack: { store[$0].map { .found($0) } ?? .absent }
        )

        XCTAssertEqual(settings.shipbox.token, "ship", "kept, and retried next launch")
        XCTAssertEqual(settings.taskbox.token, "", "moved")
        XCTAssertEqual(store[.taskboxToken], "task")
    }

    func testMovesAllFive() {
        var store: [DeckSecret: String] = [:]
        var settings = DeckSettings()
        settings.openbox.token = "o"
        settings.shipbox.token = "s"
        settings.taskbox.token = "t"
        settings.prbox.github.token = "g"
        settings.prbox.azure.token = "a"

        DeckSecretsMigration.migrate(
            &settings,
            write: { store[$0] = $1; return errSecSuccess },
            readBack: { store[$0].map { .found($0) } ?? .absent }
        )

        XCTAssertEqual(store.count, 5)
        for secret in DeckSecret.allCases {
            XCTAssertEqual(settings.secretValue(secret), "", "\(secret.rawValue) still in the file")
        }
    }
}
