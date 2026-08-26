import XCTest

/// The strings the Credentials tab shows. Pure, so they are pinned here rather
/// than eyeballed in a screenshot.
final class CredentialsCopyTests: XCTestCase {

    private func account(_ kind: CredentialKind, id: String = "abc123def456") -> CredentialAccount {
        CredentialAccount(id: id, kind: kind, label: "work")
    }

    // MARK: - Subtitles (critique A3: labels are not unique)

    func testAnAzureAccountIsSubtitledByItsOrganizationAndProject() {
        var a = account(.azure)
        a.organization = "acme"
        a.project = "Manifold"

        XCTAssertEqual(CredentialsCopy.subtitle(for: a), "acme / Manifold")
    }

    func testAnAzureAccountWithNoProjectShowsJustTheOrganization() {
        var a = account(.azure)
        a.organization = "acme"

        XCTAssertEqual(CredentialsCopy.subtitle(for: a), "acme")
    }

    func testAnOpencodeAccountIsSubtitledByItsServerHost() {
        var a = account(.opencode)
        a.serverURL = "http://nuc:4096"

        XCTAssertEqual(CredentialsCopy.subtitle(for: a), "nuc")
    }

    func testAGitHubAccountIsSubtitledByItsVerifiedLogin() {
        var a = account(.github)
        a.verifiedIdentity = "haqaliz"

        XCTAssertEqual(CredentialsCopy.subtitle(for: a), "haqaliz")
    }

    func testAnAccountWithNothingToSayFallsBackToItsId() {
        // Two accounts can legally share a label. Something must tell them
        // apart, even before either is verified.
        XCTAssertEqual(CredentialsCopy.subtitle(for: account(.github)), "abc123")
    }

    func testASubtitleNeverLeaksAToken() {
        var a = account(.github)
        a.token = "ghp_SENTINEL"

        XCTAssertFalse(CredentialsCopy.subtitle(for: a).contains("SENTINEL"))
    }

    // MARK: - Who uses an account

    func testAnAccountNothingPointsAtSaysSo() {
        XCTAssertEqual(CredentialsCopy.usedBy([]), "Unused")
    }

    func testAnAccountNamesEveryWidgetUsingIt() {
        XCTAssertEqual(CredentialsCopy.usedBy([.shipbox, .prboxGitHub]), "ShipBox, PRBox (GitHub)")
    }

    // MARK: - Deleting (D7)

    func testDeletingAnUnusedAccountSaysNothingAlarming() {
        XCTAssertEqual(
            CredentialsCopy.deleteMessage(label: "work", slots: []),
            "Its token is removed from the keychain. Nothing is using it."
        )
    }

    func testDeletingAUsedAccountNamesWhatBreaks() {
        XCTAssertEqual(
            CredentialsCopy.deleteMessage(label: "work", slots: [.shipbox, .prboxGitHub]),
            "ShipBox and PRBox (GitHub) use it and will stop fetching until you pick another account. Its token is removed from the keychain."
        )
    }

    func testDeletingAnAccountUsedByOneWidgetReadsAsOneWidget() {
        XCTAssertEqual(
            CredentialsCopy.deleteMessage(label: "work", slots: [.shipbox]),
            "ShipBox uses it and will stop fetching until you pick another account. Its token is removed from the keychain."
        )
    }

    // MARK: - Verification captions

    func testAnUnverifiedAccountSaysSoWithoutSoundingBroken() {
        XCTAssertEqual(CredentialsCopy.verification(for: account(.github)), "Not verified")
    }

    func testAVerifiedAccountNamesWhoTheCredentialBelongsTo() {
        var a = account(.github)
        a.verifiedIdentity = "haqaliz"
        a.verifiedAt = Date(timeIntervalSince1970: 0)

        XCTAssertTrue(CredentialsCopy.verification(for: a).hasPrefix("haqaliz"))
    }
}
