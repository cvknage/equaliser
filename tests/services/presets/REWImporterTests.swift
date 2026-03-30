import XCTest
@testable import Equaliser

final class REWImporterTests: XCTestCase {
    // MARK: - Basic Parsing Tests

    func testImport_basicFilterWithQ() throws {
        let text = """
        Filter Settings file
        Room EQ V4.00
        Dated: 07-Jan-2007 17:20:32
        Filter 1: ON  PK   Fc   1000Hz   Gain  6.0dB  Q  1.41
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 1)
        let band = result.bands[0]
        XCTAssertEqual(band.frequency, 1000.0)
        XCTAssertEqual(band.q, 1.41)
        XCTAssertEqual(band.gain, 6.0)
        XCTAssertEqual(band.filterType, .parametric)
        XCTAssertFalse(band.bypass)
    }

    func testImport_filterWithBW60() throws {
        // BW/60 format used by Behringer DSP1124P
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc   1000Hz   Gain  3.0dB  BW/60  4.0
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 1)
        let band = result.bands[0]

        // Q = 60 / (4.0 * sqrt(2)) ≈ 10.61
        let expectedQ: Float = 60.0 / (4.0 * sqrt(2))
        XCTAssertEqual(band.q, expectedQ, accuracy: 0.01)
        XCTAssertEqual(band.frequency, 1000.0)
        XCTAssertEqual(band.gain, 3.0)
    }

    func testImport_multipleFilters() throws {
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc    100Hz   Gain  -3.0dB  Q  1.0
        Filter 2: ON  LS   Fc    500Hz   Gain   2.0dB  Q  0.7
        Filter 3: ON  HS   Fc   2000Hz   Gain   4.0dB  Q  1.41
        Filter 4: ON  LP   Fc   8000Hz   Gain   0.0dB  Q  0.707
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 4)

        XCTAssertEqual(result.bands[0].frequency, 100.0)
        XCTAssertEqual(result.bands[0].gain, -3.0)
        XCTAssertEqual(result.bands[0].filterType, .parametric)

        XCTAssertEqual(result.bands[1].frequency, 500.0)
        XCTAssertEqual(result.bands[1].gain, 2.0)
        XCTAssertEqual(result.bands[1].filterType, .lowShelf)

        XCTAssertEqual(result.bands[2].frequency, 2000.0)
        XCTAssertEqual(result.bands[2].gain, 4.0)
        XCTAssertEqual(result.bands[2].filterType, .highShelf)

        XCTAssertEqual(result.bands[3].frequency, 8000.0)
        XCTAssertEqual(result.bands[3].filterType, .lowPass)
    }

    // MARK: - Filter Type Mapping Tests

    func testImport_filterTypeMapping() throws {
        let filterTypeTests: [(String, FilterType)] = [
            ("PK", .parametric),
            ("PEQ", .parametric),
            ("PA", .parametric),
            ("PARAMETRIC", .parametric),
            ("LS", .lowShelf),
            ("LOWSHELF", .lowShelf),
            ("HS", .highShelf),
            ("HIGHSHELF", .highShelf),
            ("LP", .lowPass),
            ("LOWPASS", .lowPass),
            ("HP", .highPass),
            ("HIGHPASS", .highPass),
            ("BP", .bandPass),
            ("BANDPASS", .bandPass),
            ("NOTCH", .notch)
        ]

        for (rewType, expectedType) in filterTypeTests {
            let text = """
            Filter Settings file
            Filter 1: ON  \(rewType)   Fc   1000Hz   Gain  0.0dB  Q  1.0
            """

            let result = try REWImporter.importBands(from: createTempFile(text))
            XCTAssertEqual(result.bands.count, 1)
            XCTAssertEqual(result.bands[0].filterType, expectedType,
                           "Filter type '\(rewType)' should map to \(expectedType)")
        }
    }

    // MARK: - OFF and None Filter Tests

    func testImport_offFilter_setsBypassTrue() throws {
        let text = """
        Filter Settings file
        Filter 1: OFF  PK   Fc   1000Hz   Gain  6.0dB  Q  1.41
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 1)
        XCTAssertTrue(result.bands[0].bypass)
    }

    func testImport_noneFilter_isSkipped() throws {
        let text = """
        Filter Settings file
        Filter 1: ON  None
        Filter 2: ON  PK   Fc   1000Hz   Gain  6.0dB  Q  1.41
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 1)
        XCTAssertEqual(result.bands[0].frequency, 1000.0)
    }

    // MARK: - Clamping Tests

    func testImport_frequencyClamping() throws {
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc   10Hz   Gain  0.0dB  Q  1.0
        Filter 2: ON  PK   Fc   50000Hz   Gain  0.0dB  Q  1.0
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 2)
        XCTAssertEqual(result.bands[0].frequency, 20.0)  // Clamped to minimum
        XCTAssertEqual(result.bands[1].frequency, 20000.0)  // Clamped to maximum

        // Should have warnings about clamping
        XCTAssertTrue(result.warnings.contains { $0.contains("frequency clamped") })
    }

    func testImport_gainClamping() throws {
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc   1000Hz   Gain  -50.0dB  Q  1.0
        Filter 2: ON  PK   Fc   1000Hz   Gain   50.0dB  Q  1.0
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 2)
        XCTAssertEqual(result.bands[0].gain, -36.0)  // Clamped to minimum
        XCTAssertEqual(result.bands[1].gain, 36.0)  // Clamped to maximum

        XCTAssertTrue(result.warnings.contains { $0.contains("gain clamped") })
    }

    func testImport_qClamping() throws {
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc   1000Hz   Gain  0.0dB  Q  0.05
        Filter 2: ON  PK   Fc   1000Hz   Gain  0.0dB  Q  150.0
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 2)
        XCTAssertEqual(result.bands[0].q, 0.1)  // Clamped to minimum
        XCTAssertEqual(result.bands[1].q, 100.0)  // Clamped to maximum

        XCTAssertTrue(result.warnings.contains { $0.contains("Q clamped") })
    }

    // MARK: - Edge Case Tests

    func testImport_realWorldREWFormat() throws {
        // Example from REW documentation
        let text = """
        Filter Settings file
        Room EQ V4.00
        Dated: 07-Jan-2007 17:20:32
        Notes:Example filter settings
        Equaliser: DSP1124P
        sampledata.txt
        Bass limited 80Hz 12dB/Octave
        Target level: 75.0dB
        Filter 1: ON  PK   Fc   129.1Hz (  125 +2 )   Gain -18.5dB  BW/60  4.0
        Filter 2: ON  PA   Fc    36.8Hz (   40 -7 )   Gain -15.5dB  BW/60 10.0
        Filter 3: ON  LS   Fc    99.1Hz (  100 -1 )   Gain  -3.5dB  Q  1.41
        Filter 4: ON  None
        Filter 5: OFF HP   Fc    20Hz   Q  0.707
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        // Should have 4 bands (None is skipped, OFF HP is included with bypass=true)
        XCTAssertEqual(result.bands.count, 4)

        // First filter: PK with BW/60
        XCTAssertEqual(result.bands[0].filterType, .parametric)
        XCTAssertEqual(result.bands[0].frequency, 129.1)
        XCTAssertEqual(result.bands[0].gain, -18.5)
        XCTAssertFalse(result.bands[0].bypass)

        // Second filter: PA (parametric) with BW/60
        XCTAssertEqual(result.bands[1].filterType, .parametric)
        XCTAssertEqual(result.bands[1].frequency, 36.8)

        // Third filter: LS with Q
        XCTAssertEqual(result.bands[2].filterType, .lowShelf)
        XCTAssertEqual(result.bands[2].q, 1.41)

        // Fourth filter (OFF HP): bypassed
        XCTAssertTrue(result.bands[3].bypass)
        XCTAssertEqual(result.bands[3].filterType, .highPass)
    }

    func testImport_negativeGain() throws {
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc   1000Hz   Gain  -12.5dB  Q  2.0
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 1)
        XCTAssertEqual(result.bands[0].gain, -12.5)
    }

    func testImport_defaultQ() throws {
        // When neither Q nor BW/60 is specified, should use default Q
        let text = """
        Filter Settings file
        Filter 1: ON  PK   Fc   1000Hz   Gain  0.0dB
        """

        let result = try REWImporter.importBands(from: createTempFile(text))

        XCTAssertEqual(result.bands.count, 1)
        XCTAssertEqual(result.bands[0].q, 1.41)  // Default Q
    }

    // MARK: - Error Tests

    func testImport_noFilters_throwsError() {
        let text = """
        Filter Settings file
        Room EQ V4.00
        Dated: 07-Jan-2007 17:20:32
        """

        XCTAssertThrowsError(try REWImporter.importBands(from: createTempFile(text))) { error in
            guard case REWImportError.noFiltersFound = error else {
                XCTFail("Expected noFiltersFound error")
                return
            }
        }
    }

    func testImport_emptyFile_throwsError() {
        XCTAssertThrowsError(try REWImporter.importBands(from: createTempFile(""))) { error in
            guard case REWImportError.noFiltersFound = error else {
                XCTFail("Expected noFiltersFound error")
                return
            }
        }
    }

    // MARK: - Helper Methods

    private func createTempFile(_ content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "rew_test_\(UUID().uuidString).txt"
        let url = tempDir.appendingPathComponent(fileName)
        try? content.write(to: url, atomically: true, encoding: .utf8)

        // Clean up after test
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }

        return url
    }
}