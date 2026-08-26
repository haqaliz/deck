import XCTest

/// `RGBA.init(_ color: Color)` bridges a SwiftUI `Color` into `NSColor`, and
/// that bridge is not thread-safe. Every widget's settings struct used it to
/// build its *default* colours, so merely **decoding** `DeckSettings` ran a
/// dozen of them — from the app, from `DeckAgent`, and from every widget
/// timeline, concurrently.
///
/// Captured 2026-08-26 in production: `SIGABRT`, malloc corruption inside
/// `-[NSConcreteMapTable grow]` under `NSColor.init(_:)`, under
/// `DevBoxSettings.init()`, under `DeckSettings.init(from:)`.
final class RGBAPaletteTests: XCTestCase {

    /// The regression test. Before the fix this corrupts the malloc heap and
    /// aborts the whole test process; after it, decoding is pure arithmetic on
    /// `Double`s and there is nothing to race on.
    func testDecodingSettingsConcurrentlyIsSafe() {
        // "{}" on purpose: every section falls back to its defaults, which is
        // exactly the path that used to build colours through AppKit.
        let json = Data("{}".utf8)
        let iterations = 200

        let results = UnsafeMutableBufferPointer<DeckSettings?>.allocate(capacity: iterations)
        results.initialize(repeating: nil)
        defer { results.deallocate() }

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            results[index] = try? JSONDecoder().decode(DeckSettings.self, from: json)
        }

        let decoded = results.compactMap { $0 }
        XCTAssertEqual(decoded.count, iterations, "a concurrent decode failed outright")
        XCTAssertTrue(decoded.allSatisfy { $0 == decoded[0] }, "concurrent decodes disagreed")
    }

    func testConstructingSettingsConcurrentlyIsSafe() {
        let iterations = 200
        let results = UnsafeMutableBufferPointer<DeckSettings>.allocate(capacity: iterations)
        results.initialize(repeating: DeckSettings())
        defer { results.deallocate() }

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            results[index] = DeckSettings()
        }

        XCTAssertTrue(results.allSatisfy { $0 == results[0] })
    }

    // MARK: - The palette is fixed, not resolved

    /// Apple's system colours are **appearance-dependent**: measured on
    /// macOS 15, `Color.green` bridges to `0.204, 0.780, 0.349` under aqua and
    /// `0.188, 0.820, 0.345` under darkAqua. So the old defaults did not just
    /// race — whichever appearance happened to be current the first time a
    /// settings file was written got frozen into it. A fixed palette is the
    /// more correct answer as well as the safe one.
    func testPaletteMatchesTheMeasuredAquaSystemColours() {
        assertComponents(RGBA.systemGreen, 0.20392151176929474, 0.78039216995239258, 0.34901958703994751)
        assertComponents(RGBA.systemOrange, 1, 0.55294120311737061, 0.15686275064945221)
        assertComponents(RGBA.systemBlue, 0, 0.53333336114883423, 1)
        assertComponents(RGBA.systemCyan, 0, 0.75294119119644165, 0.90980386734008789)
        assertComponents(RGBA.systemTeal, 0, 0.76470589637756348, 0.81568628549575806)
        assertComponents(RGBA.systemRed, 1, 0.21960783004760742, 0.23529410362243652)
        assertComponents(RGBA.systemGray, 0.55686277151107788, 0.55686277151107788, 0.57647061347961426)
        assertComponents(RGBA.systemYellow, 1, 0.80000001192092896, 0)
        assertComponents(RGBA.systemPurple, 0.79607844352722168, 0.18823529779911041, 0.87843137979507446)
        assertComponents(RGBA.systemPink, 1, 0.17647059261798859, 0.33333331346511841)
        assertComponents(RGBA.systemMint, 0, 0.78431367874145508, 0.70196080207824707)
        assertComponents(RGBA.systemIndigo, 0.38039213418960571, 0.33333331346511841, 0.96078437566757202)
    }

    func testEveryPaletteEntryIsOpaque() {
        for entry in RGBA.palette {
            XCTAssertEqual(entry.alpha, 1, "a default colour must not be see-through")
        }
    }

    func testPaletteEntriesAreDistinct() {
        XCTAssertEqual(Set(RGBA.palette.map(\.self)).count, RGBA.palette.count)
    }

    /// The point of the whole change: a default colour is a literal, never a
    /// resolved system colour. If someone reintroduces `RGBA(.green)` as a
    /// default this fails on any machine in dark mode.
    func testWidgetDefaultsComeFromTheFixedPalette() {
        let settings = DeckSettings()
        XCTAssertEqual(settings.livebox.cpuColor, RGBA.systemGreen)
        XCTAssertEqual(settings.livebox.memColor, RGBA.systemCyan)
        XCTAssertEqual(settings.openbox.inputColor, RGBA.systemCyan)
        XCTAssertEqual(settings.shipbox.failureColor, RGBA.systemRed)
        XCTAssertEqual(settings.taskbox.otherColor, RGBA.systemGray)
        XCTAssertEqual(settings.prbox.mineColor, RGBA.systemBlue)
    }

    /// The round trip a `ColorPicker` performs must still be lossless.
    ///
    /// `@MainActor` because `RGBA.init(_:)` now demands it — which is the
    /// point. Writing this test without the annotation is a compile error, and
    /// so is any future default that reaches for the bridge again.
    @MainActor
    func testAPaletteEntrySurvivesConversionToColorAndBack() {
        for entry in RGBA.palette {
            let round = RGBA(entry.color)
            XCTAssertEqual(round.red, entry.red, accuracy: 0.0001)
            XCTAssertEqual(round.green, entry.green, accuracy: 0.0001)
            XCTAssertEqual(round.blue, entry.blue, accuracy: 0.0001)
        }
    }

    private func assertComponents(
        _ rgba: RGBA, _ red: Double, _ green: Double, _ blue: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(rgba.red, red, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rgba.green, green, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rgba.blue, blue, accuracy: 1e-9, file: file, line: line)
    }
}

extension RGBA: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(red); hasher.combine(green); hasher.combine(blue); hasher.combine(alpha)
    }
}
