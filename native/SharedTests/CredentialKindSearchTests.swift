import XCTest

/// The provider list in the Add Account sheet, and its search field.
///
/// People do not call these what Deck calls them: "ado" and "vsts" are what
/// Azure DevOps has been named over the years, and someone reaching for the
/// opencode account will type "oc" or "sst" as readily as "opencode".
final class CredentialKindSearchTests: XCTestCase {

    func testAnEmptyQueryOffersEveryProvider() {
        XCTAssertEqual(CredentialKind.matching(""), CredentialKind.allCases)
        XCTAssertEqual(CredentialKind.matching("   "), CredentialKind.allCases)
    }

    func testTypingAProviderNameNarrowsToIt() {
        XCTAssertEqual(CredentialKind.matching("github"), [.github])
        XCTAssertEqual(CredentialKind.matching("opencode"), [.opencode])
    }

    func testSearchIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(CredentialKind.matching("  GitHub "), [.github])
        XCTAssertEqual(CredentialKind.matching("AZURE"), [.azure])
    }

    func testAPartialWordIsEnough() {
        XCTAssertEqual(CredentialKind.matching("git"), [.github])
        XCTAssertEqual(CredentialKind.matching("dev"), [.azure], "\"Azure DevOps\" matches on its second word")
    }

    func testTheNamesAzureDevOpsHasHadAllWork() {
        for query in ["azure devops", "ado", "vsts", "devops"] {
            XCTAssertEqual(CredentialKind.matching(query), [.azure], "\"\(query)\" should find Azure DevOps")
        }
    }

    func testOpencodeIsFindableByItsShortNames() {
        for query in ["oc", "sst"] {
            XCTAssertEqual(CredentialKind.matching(query), [.opencode], "\"\(query)\" should find opencode")
        }
    }

    // MARK: - Brand artwork

    func testEveryProviderNamesItsArtworkAndTheNamesAreDistinct() {
        // These are filenames in the app bundle. A typo is a missing icon, and
        // nothing else in the build would say so.
        let names = CredentialKind.allCases.map(\.assetName)
        XCTAssertEqual(Set(names).count, CredentialKind.allCases.count)
        XCTAssertEqual(CredentialKind.github.assetName, "provider-github")
        XCTAssertEqual(CredentialKind.azure.assetName, "provider-azure")
        XCTAssertEqual(CredentialKind.opencode.assetName, "provider-opencode")
    }

    func testArtworkComesInBothAppearances() {
        XCTAssertEqual(CredentialKind.github.assetName(dark: false), "provider-github-light")
        XCTAssertEqual(CredentialKind.github.assetName(dark: true), "provider-github-dark")
    }

    func testAQueryThatMatchesNothingReturnsNothing() {
        // The sheet says so rather than showing an empty box.
        XCTAssertTrue(CredentialKind.matching("gitlab").isEmpty)
    }

    func testResultsKeepTheDeclaredOrderRatherThanTheQuerysOrder() {
        // The provider list must not reshuffle as you type. "e" is in "Azure"
        // and "opencode" but not in "GitHub".
        XCTAssertEqual(CredentialKind.matching("e"), [.azure, .opencode])
    }
}
