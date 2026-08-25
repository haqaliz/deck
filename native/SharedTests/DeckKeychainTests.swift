import XCTest

/// Exercises the real keychain against a test-only service so the user's own
/// stored credentials are never touched.
final class DeckKeychainTests: XCTestCase {
    private let service = "com.deck.app.tests"

    override func setUp() {
        super.setUp()
        wipe()
    }

    override func tearDown() {
        wipe()
        super.tearDown()
    }

    private func wipe() {
        for secret in DeckSecret.allCases {
            DeckKeychain.delete(secret, service: service)
        }
    }

    // MARK: - The absent/failed distinction the whole feature rests on

    func testUnwrittenSecretReadsAsAbsentNotFailed() {
        XCTAssertEqual(DeckKeychain.read(.shipboxToken, service: service), .absent)
    }

    func testRoundTrip() {
        XCTAssertEqual(DeckKeychain.write(.shipboxToken, value: "ghp_abc", service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(.shipboxToken, service: service), .found("ghp_abc"))
    }

    func testWriteOverwritesAnExistingValue() {
        DeckKeychain.write(.taskboxToken, value: "first", service: service)
        XCTAssertEqual(DeckKeychain.write(.taskboxToken, value: "second", service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(.taskboxToken, service: service), .found("second"))
    }

    func testDeleteMakesTheSecretAbsentAgain() {
        DeckKeychain.write(.openboxToken, value: "tok", service: service)
        XCTAssertEqual(DeckKeychain.delete(.openboxToken, service: service), errSecSuccess)
        XCTAssertEqual(DeckKeychain.read(.openboxToken, service: service), .absent)
    }

    func testDeletingSomethingNeverStoredSucceeds() {
        XCTAssertEqual(DeckKeychain.delete(.prboxAzureToken, service: service), errSecSuccess)
    }

    func testSecretsAreIndependent() {
        DeckKeychain.write(.prboxGitHubToken, value: "gh", service: service)
        DeckKeychain.write(.prboxAzureToken, value: "az", service: service)
        XCTAssertEqual(DeckKeychain.read(.prboxGitHubToken, service: service), .found("gh"))
        XCTAssertEqual(DeckKeychain.read(.prboxAzureToken, service: service), .found("az"))
    }

    func testReadAllCoversEverySecret() {
        DeckKeychain.write(.shipboxToken, value: "s", service: service)
        let all = DeckKeychain.readAll(service: service)
        XCTAssertEqual(all.count, DeckSecret.allCases.count)
        XCTAssertEqual(all[.shipboxToken], .found("s"))
        XCTAssertEqual(all[.taskboxToken], .absent)
    }

    // MARK: - On-disk contract

    func testAccountNamesAreStable() {
        // Renaming any of these strands a token the user already pasted.
        XCTAssertEqual(DeckSecret.allCases.count, 5)
        XCTAssertEqual(
            Set(DeckSecret.allCases.map(\.rawValue)),
            ["openbox.token", "shipbox.token", "taskbox.token",
             "prbox.github.token", "prbox.azure.token"]
        )
    }
}
