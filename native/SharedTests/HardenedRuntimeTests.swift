import XCTest

/// Pins `ENABLE_HARDENED_RUNTIME` on every shipping target in `project.yml`.
///
/// Deck notarizes with a Developer ID certificate one day; hardened runtime is
/// required for that, and the runbook names "a target that missed
/// `ENABLE_HARDENED_RUNTIME`" as one of the two usual causes of a first
/// `Invalid` submission. The flag was therefore landed early, under the
/// existing Apple Development identity, so the paid day changes the certificate
/// and nothing else — see `docs/planning/hardened-runtime-preflight/`.
///
/// The guard exists because **absent and `NO` look different in the file and
/// identical in the product**: before this work DeckApp and DeckWidgets said
/// `NO` and DeckAgent said nothing at all, and both shapes ship an unhardened
/// binary. So the audit reports three states, not two, and it *enumerates* the
/// targets it finds rather than checking a hardcoded list — a list cannot catch
/// the next target somebody adds.
///
/// Test-only on purpose. This reads a build input, so nothing at runtime wants
/// it, and putting it in `Shared/` would compile dead code into all three
/// shipping binaries. `DeckBundleTests` reaches `project.yml` the same way, and
/// for the same reason: `#filePath`, because the DeckSharedTests scheme builds
/// only its own target and there is no `Deck.app` in the products directory
/// during a test run.
final class HardenedRuntimeTests: XCTestCase {

    // MARK: - The audit (pure, over the text of project.yml)

    enum Setting: Equatable {
        case enabled        // ENABLE_HARDENED_RUNTIME: YES
        case disabled       // ENABLE_HARDENED_RUNTIME: NO
        case absent         // the key appears nowhere in the target's block

        var isEnabled: Bool { self == .enabled }

        var describedForFailure: String {
            switch self {
            case .enabled: return "YES"
            case .disabled: return "NO"
            case .absent: return "absent"
            }
        }
    }

    struct Audit {
        /// Every target found under `targets:`, in file order, with the state of
        /// its `ENABLE_HARDENED_RUNTIME` key.
        let targets: [(name: String, setting: Setting)]

        /// Targets that would ship unhardened. `exempting` is passed by the
        /// caller rather than baked in, so the one exemption is visible at the
        /// call site instead of hidden in a parser.
        func offenders(exempting exempt: Set<String>) -> [(name: String, setting: Setting)] {
            targets.filter { !exempt.contains($0.name) && !$0.setting.isEnabled }
        }

        func setting(for target: String) -> Setting? {
            targets.first { $0.name == target }?.setting
        }

        /// Parses the `targets:` section. Target names are the keys at two-space
        /// indent under it; a target's block runs to the next such key or to the
        /// next top-level section (`schemes:`).
        init(yml: String) {
            var found: [(name: String, setting: Setting)] = []
            var current: String?
            var currentSetting: Setting = .absent
            var inTargets = false

            func flush() {
                if let name = current { found.append((name, currentSetting)) }
                current = nil
                currentSetting = .absent
            }

            for rawLine in yml.components(separatedBy: .newlines) {
                let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

                let indent = line.prefix { $0 == " " }.count

                // A top-level key ends the targets section.
                if indent == 0 {
                    flush()
                    inTargets = line.hasPrefix("targets:")
                    continue
                }
                guard inTargets else { continue }

                // A two-space key is a target name.
                if indent == 2, line.hasSuffix(":") {
                    flush()
                    current = String(line.dropFirst(2).dropLast())
                    continue
                }

                guard current != nil else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("ENABLE_HARDENED_RUNTIME:") else { continue }
                let value = trimmed
                    .dropFirst("ENABLE_HARDENED_RUNTIME:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
                currentSetting = (value == "YES" || value == "TRUE") ? .enabled : .disabled
            }
            flush()
            self.targets = found
        }
    }

    /// The single exemption: a unit-test bundle is not shipped and not
    /// notarized. Named here rather than in the parser so a reader of the
    /// assertion sees what is being let through.
    private static let notShipped: Set<String> = ["DeckSharedTests"]

    // MARK: - The audit reports three states, not two

    private static let allEnabled = """
    targets:
      DeckApp:
        settings:
          base:
            ENABLE_HARDENED_RUNTIME: YES
      DeckWidgets:
        settings:
          base:
            ENABLE_HARDENED_RUNTIME: YES
      DeckAgent:
        settings:
          base:
            ENABLE_HARDENED_RUNTIME: YES
      DeckSharedTests:
        settings:
          base:
            SWIFT_VERSION: "5.10"
    schemes:
      DeckSharedTests:
        build:
          targets:
            DeckSharedTests: all
    """

    func testCleanTreeHasNoOffenders() {
        let audit = Audit(yml: Self.allEnabled)
        XCTAssertEqual(audit.targets.count, 4, "parser lost or invented a target")
        XCTAssertTrue(audit.offenders(exempting: Self.notShipped).isEmpty)
    }

    /// Shape 1: the key is present and off. This is what DeckApp and
    /// DeckWidgets said before this work.
    func testExplicitNOIsAnOffender() {
        let yml = Self.allEnabled.replacingOccurrences(
            of: """
              DeckWidgets:
                settings:
                  base:
                    ENABLE_HARDENED_RUNTIME: YES
            """,
            with: """
              DeckWidgets:
                settings:
                  base:
                    ENABLE_HARDENED_RUNTIME: NO
            """
        )
        let offenders = Audit(yml: yml).offenders(exempting: Self.notShipped)
        XCTAssertEqual(offenders.map(\.name), ["DeckWidgets"])
        XCTAssertEqual(offenders.first?.setting, .disabled)
    }

    /// Shape 2: the key is nowhere. This is what DeckAgent said before this
    /// work, and it is the shape that reads as "fine" to a grep for `: NO`.
    func testAbsentKeyIsAnOffenderAndIsDistinguishedFromNO() {
        let yml = Self.allEnabled.replacingOccurrences(
            of: """
              DeckAgent:
                settings:
                  base:
                    ENABLE_HARDENED_RUNTIME: YES
            """,
            with: """
              DeckAgent:
                settings:
                  base:
                    PRODUCT_NAME: DeckAgent
            """
        )
        let audit = Audit(yml: yml)
        XCTAssertEqual(audit.setting(for: "DeckAgent"), .absent)
        XCTAssertNotEqual(audit.setting(for: "DeckAgent"), .disabled,
                          "absent and NO must not collapse into one state")
        XCTAssertEqual(audit.offenders(exempting: Self.notShipped).map(\.name), ["DeckAgent"])
    }

    /// Shape 3: a target added later. The guard has to fail for it without
    /// anyone having remembered to add it to a list — this is why the audit
    /// enumerates rather than checks.
    func testATargetAddedLaterIsAnOffenderWithNoListToUpdate() {
        let yml = Self.allEnabled.replacingOccurrences(
            of: "schemes:",
            with: """
              DeckHelper:
                type: tool
                settings:
                  base:
                    PRODUCT_NAME: DeckHelper
            schemes:
            """
        )
        let offenders = Audit(yml: yml).offenders(exempting: Self.notShipped)
        XCTAssertEqual(offenders.map(\.name), ["DeckHelper"])
        XCTAssertEqual(offenders.first?.setting, .absent)
    }

    /// The exemption is one name, not a category. If a second test bundle ever
    /// appears it must be exempted deliberately.
    func testOnlyTheNamedTargetIsExempt() {
        let yml = Self.allEnabled.replacingOccurrences(
            of: """
              DeckApp:
                settings:
                  base:
                    ENABLE_HARDENED_RUNTIME: YES
            """,
            with: """
              DeckApp:
                settings:
                  base:
                    ENABLE_HARDENED_RUNTIME: NO
            """
        )
        XCTAssertTrue(Audit(yml: yml).offenders(exempting: []).contains { $0.name == "DeckSharedTests" },
                      "with no exemption the test bundle is an offender like any other")
        XCTAssertFalse(Audit(yml: yml).offenders(exempting: Self.notShipped).contains { $0.name == "DeckSharedTests" })
    }

    /// A `configs:` block must not be mistaken for a target — its keys sit at
    /// the same shape as a target's own children and one level deeper.
    func testConfigKeysAreNotReadAsTargets() {
        let yml = """
        targets:
          DeckApp:
            settings:
              base:
                ENABLE_HARDENED_RUNTIME: YES
              configs:
                Release:
                  CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO
        """
        XCTAssertEqual(Audit(yml: yml).targets.map(\.name), ["DeckApp"])
    }

    // MARK: - The real build input

    private var projectYML: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)   // native/SharedTests/HardenedRuntimeTests.swift
                .deletingLastPathComponent()             // native/SharedTests
                .deletingLastPathComponent()             // native
                .appendingPathComponent("project.yml")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// The guard itself. Fails naming every target that would ship unhardened,
    /// and which of the two shapes it is in.
    func testEveryShippingTargetEnablesHardenedRuntime() throws {
        let audit = Audit(yml: try projectYML)
        XCTAssertFalse(audit.targets.isEmpty, "no targets parsed out of project.yml")

        let offenders = audit.offenders(exempting: Self.notShipped)
        XCTAssertTrue(
            offenders.isEmpty,
            "these targets would ship without hardened runtime: "
                + offenders.map { "\($0.name) (\($0.setting.describedForFailure))" }
                    .joined(separator: ", ")
                + ". Notarization rejects an unhardened binary, and an absent key looks "
                + "exactly like a hardened one to a grep for ': NO'."
        )
    }

    /// The exemption is only sound while that target really is a test bundle.
    func testTheExemptedTargetIsAUnitTestBundle() throws {
        let yml = try projectYML
        XCTAssertTrue(
            yml.contains("  DeckSharedTests:\n    type: bundle.unit-test\n"),
            "DeckSharedTests is exempted from hardened runtime because it is a test "
                + "bundle; it is no longer declared as one"
        )
    }
}
