import XCTest
@testable import Equaliser

final class DriverNameFormatTests: XCTestCase {
    private let values = DriverNameFormat.Values(device: "Audioengine 2+", preset: "Flat", eqEnabled: true)

    func testDefaultMatchesOriginalNaming() {
        XCTAssertEqual(DriverNameFormat.default.render(values), "Audioengine 2+ (Equaliser)")
        XCTAssertEqual(DriverNameFormat.default.string, "{device} (Equaliser)")
    }

    func testStringRoundTrip() {
        let format = DriverNameFormat(string: "Equaliser → {device} · {preset} ({eq-state})")
        XCTAssertEqual(format.segments, [
            .text("Equaliser → "), .token(.device), .text(" · "), .token(.preset),
            .text(" ("), .token(.eqState), .text(")"),
        ])
        XCTAssertEqual(DriverNameFormat(string: format.string), format)
    }

    func testUnknownAndUnclosedBracesStayLiteral() {
        let format = DriverNameFormat(string: "{nope} {device} {")
        XCTAssertEqual(format.segments, [.text("{nope} "), .token(.device), .text(" {")])
        XCTAssertEqual(format.string, "{nope} {device} {")
    }

    func testRenderingSubstitutesTokens() {
        let format = DriverNameFormat(string: "{device} · {preset} · {eq-state}")
        XCTAssertEqual(format.render(values), "Audioengine 2+ · Flat · On")
        let off = DriverNameFormat.Values(device: "Px8", preset: nil, eqEnabled: false)
        XCTAssertEqual(format.render(off), "Px8 · Custom · Off")
    }

    func testWhitespaceCollapsesAndEmptyFallsBack() {
        XCTAssertEqual(DriverNameFormat(string: "  {device}   x ").render(values), "Audioengine 2+ x")
        XCTAssertEqual(DriverNameFormat(string: "   ").render(values), DriverNameFormat.fallbackName)
    }

    func testInsertingAtCursorSplitsTextAndKeepsTokens() {
        let format = DriverNameFormat(string: "EQ: {device} (x)")  // "EQ: " = 4, token = 1, " (x)" = 4
        XCTAssertEqual(format.editorLength, 9)
        XCTAssertEqual(format.replacing(0..<0, with: .token(.preset)).string, "{preset}EQ: {device} (x)")
        XCTAssertEqual(format.replacing(2..<2, with: .text(" → ")).string, "EQ → : {device} (x)")
        XCTAssertEqual(format.replacing(5..<5, with: .token(.eqState)).string, "EQ: {device}{eq-state} (x)")
        XCTAssertEqual(format.replacing(9..<9, with: .token(.preset)).string, "EQ: {device} (x){preset}")
    }

    func testInsertingReplacesSelection() {
        let format = DriverNameFormat(string: "EQ: {device} (x)")
        // Select ": {device} (" and replace it
        XCTAssertEqual(format.replacing(2..<7, with: .token(.preset)).string, "EQ{preset}x)")
    }

    func testInsertingRespectsEmojiUTF16Offsets() {
        let format = DriverNameFormat(string: "😀{device}")  // emoji = 2 UTF-16 units
        XCTAssertEqual(format.replacing(2..<2, with: .text("!")).string, "😀!{device}")
    }

    func testUsesEQTokens() {
        XCTAssertFalse(DriverNameFormat.default.usesEQTokens)
        XCTAssertTrue(DriverNameFormat(string: "{device} {preset}").usesEQTokens)
        XCTAssertTrue(DriverNameFormat(string: "{eq-state}").usesEQTokens)
    }
}
