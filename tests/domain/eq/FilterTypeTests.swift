import XCTest
@testable import Equaliser

final class FilterTypeTests: XCTestCase {
    // MARK: - Raw Value Tests

    func testRawValues() {
        // Raw values must match AVAudioUnitEQFilterType for backward compatibility
        XCTAssertEqual(FilterType.parametric.rawValue, 0)
        XCTAssertEqual(FilterType.lowPass.rawValue, 1)
        XCTAssertEqual(FilterType.highPass.rawValue, 2)
        XCTAssertEqual(FilterType.lowShelf.rawValue, 3)
        XCTAssertEqual(FilterType.highShelf.rawValue, 4)
        XCTAssertEqual(FilterType.bandPass.rawValue, 5)
        XCTAssertEqual(FilterType.notch.rawValue, 6)
        XCTAssertEqual(FilterType.resonantLowPass.rawValue, 7)
        XCTAssertEqual(FilterType.resonantHighPass.rawValue, 8)
        XCTAssertEqual(FilterType.resonantLowShelf.rawValue, 9)
        XCTAssertEqual(FilterType.resonantHighShelf.rawValue, 10)
    }

    func testAllCasesCount() {
        XCTAssertEqual(FilterType.allCases.count, 11)
    }

    func testValidatedRawValue() {
        // Valid values
        XCTAssertNotNil(FilterType(validatedRawValue: 0))
        XCTAssertNotNil(FilterType(validatedRawValue: 5))
        XCTAssertNotNil(FilterType(validatedRawValue: 10))

        // Invalid values
        XCTAssertNil(FilterType(validatedRawValue: -1))
        XCTAssertNil(FilterType(validatedRawValue: 11))
        XCTAssertNil(FilterType(validatedRawValue: 100))
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
        XCTAssertEqual(FilterType.resonantLowPass.displayName, "Resonant Low Pass")
        XCTAssertEqual(FilterType.resonantHighPass.displayName, "Resonant High Pass")
        XCTAssertEqual(FilterType.resonantLowShelf.displayName, "Resonant Low Shelf")
        XCTAssertEqual(FilterType.resonantHighShelf.displayName, "Resonant High Shelf")
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
        XCTAssertEqual(FilterType.resonantLowPass.abbreviation, "RLP")
        XCTAssertEqual(FilterType.resonantHighPass.abbreviation, "RHP")
        XCTAssertEqual(FilterType.resonantLowShelf.abbreviation, "RLS")
        XCTAssertEqual(FilterType.resonantHighShelf.abbreviation, "RHS")
    }

    // MARK: - UI Order Tests

    func testUIOrderCount() {
        XCTAssertEqual(FilterType.allCasesInUIOrder.count, 11)
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
        // Test that decoding from raw value integers works
        for rawValue in 0...10 {
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