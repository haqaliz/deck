import XCTest

/// The per-account Verify probe. Parsers only — the network calls themselves
/// are exercised by using the app.
final class CredentialVerificationTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "fixture \(name).json is missing from the bundle"))
    }

    // MARK: - GitHub

    func testGitHubUserYieldsTheLogin() throws {
        let identity = try XCTUnwrap(GitHubUserParser.parse(try fixture("github_user")))

        XCTAssertEqual(identity, "haqaliz")
    }

    func testGitHubUserWithoutALoginIsUnreadable() {
        // Not "verified with an empty name" — the probe failed to answer.
        XCTAssertNil(GitHubUserParser.parse(Data(#"{"id":1}"#.utf8)))
        XCTAssertNil(GitHubUserParser.parse(Data(#"{"login":""}"#.utf8)))
        XCTAssertNil(GitHubUserParser.parse(Data("not json".utf8)))
    }

    func testGitHubScopesComeFromTheResponseHeader() {
        // The granted scopes are never in the body, only in X-OAuth-Scopes.
        XCTAssertEqual(
            GitHubUserParser.scopes(header: "repo, read:org, workflow"),
            ["repo", "read:org", "workflow"]
        )
    }

    func testAFineGrainedTokenSendsNoScopesAndThatIsNotAFailure() {
        // Fine-grained PATs omit the header entirely.
        XCTAssertTrue(GitHubUserParser.scopes(header: nil).isEmpty)
        XCTAssertTrue(GitHubUserParser.scopes(header: "").isEmpty)
        XCTAssertTrue(GitHubUserParser.scopes(header: " , ").isEmpty)
    }

    // MARK: - Azure DevOps

    func testAzureConnectionDataYieldsTheDisplayNameAndTheIdentityGuid() throws {
        let identity = try XCTUnwrap(AzureConnectionParser.parse(try fixture("azure_connectiondata")))

        XCTAssertEqual(identity.identity, "Ali Haqiqi")
        XCTAssertEqual(identity.azureIdentityID, "5d48bc9c-1cf3-419c-b2c5-43c4d36875d2")
    }

    func testAzurePayloadWithoutAnIdentityIsUnreadable() {
        // The trap this guards: Azure answers 200 with every active pull
        // request in the project for an identity it cannot parse. A payload
        // with no id must never read as a successful verification.
        XCTAssertNil(AzureConnectionParser.parse(Data("{}".utf8)))
        XCTAssertNil(AzureConnectionParser.parse(Data(#"{"authenticatedUser":{"providerDisplayName":"x"}}"#.utf8)))
        XCTAssertNil(AzureConnectionParser.parse(Data(#"{"authenticatedUser":{"id":""}}"#.utf8)))
    }

    func testAzureIdentityWithoutADisplayNameFallsBackToItsId() {
        let identity = AzureConnectionParser.parse(Data(#"{"authenticatedUser":{"id":"abc"}}"#.utf8))

        XCTAssertEqual(identity?.identity, "abc")
    }

    func testAzureIdentityAgreesWithTheParserPRBoxAlreadyUses() throws {
        // Two parsers over one payload is two chances to disagree. If they
        // ever do, PRBox would filter by a different identity than the one
        // Verify showed the user.
        let data = try fixture("azure_connectiondata")

        XCTAssertEqual(AzureConnectionParser.parse(data)?.azureIdentityID, ConnectionDataParser.parse(data))
    }

    // MARK: - What the account records

    func testASuccessfulVerificationStampsTheAccount() {
        var account = CredentialAccount(id: "a1", kind: .github, label: "work")
        let at = Date(timeIntervalSince1970: 1_700_000_000)

        account.recordVerification(.init(identity: "haqaliz", detail: "3 scopes", azureIdentityID: nil), at: at)

        XCTAssertEqual(account.verifiedIdentity, "haqaliz")
        XCTAssertEqual(account.verifiedAt, at)
        XCTAssertNil(account.azureIdentityID)
    }

    func testAnAzureVerificationAlsoStampsTheIdentityGuid() {
        var account = CredentialAccount(id: "a1", kind: .azure, label: "acme")

        account.recordVerification(
            .init(identity: "Ali Haqiqi", detail: nil, azureIdentityID: "guid"),
            at: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(account.azureIdentityID, "guid")
    }

    func testEditingATokenClearsTheVerification() {
        // A GUID cached against a token that has since been replaced is worse
        // than no GUID at all.
        var account = CredentialAccount(id: "a1", kind: .azure, label: "acme")
        account.recordVerification(.init(identity: "x", detail: nil, azureIdentityID: "guid"),
                                   at: Date(timeIntervalSince1970: 0))

        account.token = "a-different-token"
        account.clearVerificationIfCredentialChanged(from: "old")

        XCTAssertNil(account.verifiedIdentity)
        XCTAssertNil(account.verifiedAt)
        XCTAssertNil(account.azureIdentityID)
    }

    func testEditingSomethingHarmlessKeepsTheVerification() {
        var account = CredentialAccount(id: "a1", kind: .azure, label: "acme")
        account.token = "same"
        account.organization = "acme"
        account.projects = ["Manifold"]
        account.recordVerification(.init(identity: "x", detail: nil, azureIdentityID: "guid"),
                                   at: Date(timeIntervalSince1970: 0))
        let fingerprint = account.credentialFingerprint

        account.label = "renamed"

        XCTAssertEqual(account.credentialFingerprint, fingerprint, "a rename is not a credential change")
        account.clearVerificationIfCredentialChanged(from: fingerprint)
        XCTAssertEqual(account.verifiedIdentity, "x")
    }

    func testChangingTheOrganizationClearsTheVerification() {
        var account = CredentialAccount(id: "a1", kind: .azure, label: "acme")
        account.token = "same"
        account.organization = "acme"
        let fingerprint = account.credentialFingerprint
        account.recordVerification(.init(identity: "x", detail: nil, azureIdentityID: "guid"),
                                   at: Date(timeIntervalSince1970: 0))

        account.organization = "other"
        account.clearVerificationIfCredentialChanged(from: fingerprint)

        XCTAssertNil(account.azureIdentityID, "the GUID belonged to the old organization")
    }

    func testChangingTheServerURLClearsTheVerification() {
        var account = CredentialAccount(id: "a1", kind: .opencode, label: "nuc")
        account.token = "same"
        account.serverURL = "http://nuc:4096"
        let fingerprint = account.credentialFingerprint
        account.recordVerification(.init(identity: "reachable", detail: nil, azureIdentityID: nil),
                                   at: Date(timeIntervalSince1970: 0))

        account.serverURL = "http://other:4096"
        account.clearVerificationIfCredentialChanged(from: fingerprint)

        XCTAssertNil(account.verifiedIdentity)
    }
}
