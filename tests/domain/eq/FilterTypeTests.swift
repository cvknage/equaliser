import XCTest
@testable import Equaliser

final class FilterTypeTests: XCTestCase {
    // MARK: - Raw Value Tests

    func testRawValues() {
        // Raw values 0-6 for the 7 filter types
        XCTAssertEqual(FilterType.parametric.rawValue, 0)
        XCTAssertEqual(FilterType.lowPass.rawValue, 1)
        XCTAssertEqual(FilterType.highPass.rawValue, 2)
        XCTAssertEqual(FilterType.lowShelf.rawValue, 3)
        XCTAssertEqual(FilterType.highShelf.rawValue, 4)
        XCTAssertEqual(FilterType.bandPass.rawValue, 5)
        XCTAssertEqual(FilterType.notch.rawValue, 6)
    }

    func testAllCasesCount() {
        XCTAssertEqual(FilterType.allCases.count, 7)
    }

    func testValidatedRawValue() {
        // Valid values
        XCTAssertNotNil(FilterType(validatedRawValue: 0))
        XCTAssertNotNil(FilterType(validatedRawValue: 5))
        XCTAssertNotNil(FilterType(validatedRawValue: 6))

        // Legacy resonant types (7-10) are valid - they migrate to non-resonant equivalents
        XCTAssertNotNil(FilterType(validatedRawValue: 7))
        XCTAssertNotNil(FilterType(validatedRawValue: 10))

        // Invalid values
        XCTAssertNil(FilterType(validatedRawValue: -1))
        XCTAssertNil(FilterType(validatedRawValue: 11))
        XCTAssertNil(FilterType(validatedRawValue: 100))
    }

    func testValidatedRawValue_migratesLegacyResonantTypes() {
        // Legacy resonant types should migrate to non-resonant equivalents
        XCTAssertEqual(FilterType(validatedRawValue: 7), .lowPass)   // resonantLowPass → lowPass
        XCTAssertEqual(FilterType(validatedRawValue: 8), .highPass)  // resonantHighPass → highPass
        XCTAssertEqual(FilterType(validatedRawValue: 9), .lowShelf)   // resonantLowShelf → lowShelf
        XCTAssertEqual(FilterType(validatedRawValue: 10), .highShelf) // resonantHighShelf → highShelf
    }

    // MARK: - Display Name Tests

    func testDisplayNames() {
        XCTAssertEqual(FilterType.parametric.displayName, "Parametric")
        XCTAssertEqual(FilterType.lowPass.displayName, "Low Pass")
        XCTAssertEqual(FilterType.highPass.displayName, "High Pass")
        XCTAssertEqual(FilterType.lowShelf.displayName, "Low Shelf")
        XCTAssertEqual(FilterType.highShelf.displayName, "High Shelf")
        XCTAssertEqual(FilterType.bandPass.displayName, "Band Pass")
        XCTAssertEqual(FilterType.notch.displayName, "Notch")
    }

    // MARK: - Abbreviation Tests

    func testAbbreviations() {
        XCTAssertEqual(FilterType.parametric.abbreviation, "Bell")
        XCTAssertEqual(FilterType.lowPass.abbreviation, "LP")
        XCTAssertEqual(FilterType.highPass.abbreviation, "HP")
        XCTAssertEqual(FilterType.lowShelf.abbreviation, "LS")
        XCTAssertEqual(FilterType.highShelf.abbreviation, "HS")
        XCTAssertEqual(FilterType.bandPass.abbreviation, "BP")
        XCTAssertEqual(FilterType.notch.abbreviation, "Notch")
    }

    // MARK: - Coding Key Migration Tests

    func testFromCodingKey_migratesLegacyAbbreviations() {
        // Legacy resonant abbreviations should migrate to non-resonant
        XCTAssertEqual(FilterType(fromCodingKey: "RLP"), .lowPass)
        XCTAssertEqual(FilterType(fromCodingKey: "RHP"), .highPass)
        XCTAssertEqual(FilterType(fromCodingKey: "RLS"), .lowShelf)
        XCTAssertEqual(FilterType(fromCodingKey: "RHS"), .highShelf)
    }

    func testFromCodingKey_standardAbbreviations() {
        XCTAssertEqual(FilterType(fromCodingKey: "Bell"), .parametric)
        XCTAssertEqual(FilterType(fromCodingKey: "LP"), .lowPass)
        XCTAssertEqual(FilterType(fromCodingKey: "HP"), .highPass)
        XCTAssertEqual(FilterType(fromCodingKey: "LS"), .lowShelf)
        XCTAssertEqual(FilterType(fromCodingKey: "HS"), .highShelf)
        XCTAssertEqual(FilterType(fromCodingKey: "BP"), .bandPass)
        XCTAssertEqual(FilterType(fromCodingKey: "Notch"), .notch)
    }

    func testFromCodingKey_unknownKey_defaultsToParametric() {
        XCTAssertEqual(FilterType(fromCodingKey: "Unknown"), .parametric)
    }

    // MARK: - UI Order Tests

    func testUIOrderCount() {
        XCTAssertEqual(FilterType.allCasesInUIOrder.count, 7)
    }

    func testUIOrderContainsAllTypes() {
        let uiOrder = Set(FilterType.allCasesInUIOrder)
        let allCases = Set(FilterType.allCases)
        XCTAssertEqual(uiOrder, allCases)
    }

    func testUIOrderStartsWithParametric() {
        XCTAssertEqual(FilterType.allCasesInUIOrder.first, .parametric)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() {
        for filterType in FilterType.allCases {
            let encoded = try! JSONEncoder().encode(filterType)
            let decoded = try! JSONDecoder().decode(FilterType.self, from: encoded)
            XCTAssertEqual(decoded, filterType)
        }
    }

    func testDecodeFromRawValue() {
        // Test that decoding from raw value integers works for valid values
        for rawValue in 0...6 {
            // Encode as JSON number and decode
            let data = try! JSONEncoder().encode(rawValue)
            let decoded = try? JSONDecoder().decode(FilterType.self, from: data)
            XCTAssertNotNil(decoded, "Failed to decode raw value \(rawValue)")
            XCTAssertEqual(decoded?.rawValue, rawValue)
        }
    }

    func testDecodeInvalidRawValue() {
        // Invalid raw values should fail to decode
        let invalidData = Data([255])
        XCTAssertThrowsError(try JSONDecoder().decode(FilterType.self, from: invalidData))
    }

    // MARK: - Sendable Tests

    func testSendable() {
        // FilterType should be Sendable (enum with Sendable conformance)
        let filterType: FilterType = .parametric

        // This should compile without warning
        let closure: @Sendable () -> FilterType = { filterType }
        XCTAssertEqual(closure(), .parametric)
    }
}