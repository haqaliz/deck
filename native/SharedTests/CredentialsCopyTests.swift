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

    // MARK: - The list row's subtitle

    func testAListRowLeadsWithWhatIdentifiesTheAccount() {
        var a = account(.azure)
        a.organization = "acme"
        a.project = "Manifold"

        XCTAssertEqual(
            CredentialsCopy.rowSubtitle(for: a, among: [a], usedBy: [.taskbox]),
            "acme / Manifold \u{00B7} TaskBox"
        )
    }

    func testAnAccountWithNothingIdentifyingShowsOnlyWhoUsesIt() {
        // The id fragment is disambiguation, not information. Printing it on
        // an account nothing could be confused with is noise.
        let a = account(.github)

        XCTAssertEqual(
            CredentialsCopy.rowSubtitle(for: a, among: [a], usedBy: [.shipbox]),
            "ShipBox"
        )
    }

    func testAnUnusedAccountWithNothingIdentifyingStillSaysSomething() {
        let a = account(.github)

        XCTAssertEqual(CredentialsCopy.rowSubtitle(for: a, among: [a], usedBy: []), "Unused")
    }

    func testTheIdFragmentComesBackWhenTwoAccountsWouldOtherwiseMatch() {
        // Two unverified GitHub accounts, both named "work": without the
        // fragment the list shows the same row twice.
        let a = account(.github, id: "aaaaaa11")
        let b = account(.github, id: "bbbbbb22")

        XCTAssertEqual(
            CredentialsCopy.rowSubtitle(for: a, among: [a, b], usedBy: [.shipbox]),
            "aaaaaa \u{00B7} ShipBox"
        )
    }

    func testTwoAccountsThatDifferInTheirOwnRightNeedNoFragment() {
        var a = account(.azure, id: "aaaaaa11")
        a.organization = "acme"
        var b = account(.azure, id: "bbbbbb22")
        b.organization = "other"

        XCTAssertEqual(CredentialsCopy.rowSubtitle(for: a, among: [a, b], usedBy: []), "acme \u{00B7} Unused")
    }

    // MARK: - The detail page's header

    func testTheDetailHeaderNeverRepeatsTheIdentityAsItsOwnSubtitle() {
        // A verified GitHub account has nothing else identifying it, so the
        // header would otherwise read "haqaliz" over "haqaliz".
        var a = account(.github)
        a.verifiedIdentity = "haqaliz"

        XCTAssertEqual(CredentialsCopy.connectionSubtitle(for: a), "GitHub")
    }

    func testTheDetailHeaderShowsTheConnectionWhenThereIsOne() {
        var a = account(.azure)
        a.organization = "acme"
        a.project = "Manifold"
        a.verifiedIdentity = "Ali Haqiqi"

        XCTAssertEqual(CredentialsCopy.connectionSubtitle(for: a), "acme / Manifold")
    }

    func testAnUnconfiguredAccountsHeaderNamesItsProvider() {
        XCTAssertEqual(CredentialsCopy.connectionSubtitle(for: account(.opencode)), "opencode")
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
