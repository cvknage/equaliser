import XCTest
@testable import EqualiserApp

final class EQConfigurationTests: XCTestCase {
    // MARK: - Frequency Generation Tests

    @MainActor
    func testFrequenciesForBandCount_singleBand() {
        let frequencies = EQConfiguration.frequenciesForBandCount(1)

        XCTAssertEqual(frequencies.count, 1)
        XCTAssertEqual(frequencies[0], 20.0, accuracy: 0.001)
    }

    @MainActor
    func testFrequenciesForBandCount_twoBands() {
        let frequencies = EQConfiguration.frequenciesForBandCount(2)

        XCTAssertEqual(frequencies.count, 2)
        XCTAssertEqual(frequencies[0], 20.0, accuracy: 0.001)
        XCTAssertEqual(frequencies[1], 26000.0, accuracy: 0.001)
    }

    @MainActor
    func testFrequenciesForBandCount_logarithmicSpacing() {
        let bandCount = 10
        let frequencies = EQConfiguration.frequenciesForBandCount(bandCount)

        XCTAssertEqual(frequencies.count, bandCount)

        // Calculate the expected ratio between adjacent frequencies
        // For logarithmic spacing: ratio = (maxFreq/minFreq)^(1/(n-1))
        let expectedRatio = pow(26000.0 / 20.0, 1.0 / Float(bandCount - 1))

        // Verify constant ratio between adjacent frequencies
        for i in 1..<frequencies.count {
            let actualRatio = frequencies[i] / frequencies[i - 1]
            XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.001, "Ratio between bands \(i-1) and \(i) is not constant")
        }
    }

    @MainActor
    func testFrequenciesForBandCount_32bands() {
        let frequencies = EQConfiguration.frequenciesForBandCount(32)

        XCTAssertEqual(frequencies.count, 32)
        XCTAssertEqual(frequencies.first!, 20.0, accuracy: 0.001)
        XCTAssertEqual(frequencies.last!, 26000.0, accuracy: 1.0)

        // Verify frequencies are strictly increasing
        for i in 1..<frequencies.count {
            XCTAssertGreaterThan(frequencies[i], frequencies[i - 1], "Frequencies should be strictly increasing")
        }
    }

    @MainActor
    func testFrequenciesForBandCount_64bands() {
        let frequencies = EQConfiguration.frequenciesForBandCount(64)

        XCTAssertEqual(frequencies.count, 64)
        XCTAssertEqual(frequencies.first!, 20.0, accuracy: 0.001)
        XCTAssertEqual(frequencies.last!, 26000.0, accuracy: 1.0)

        // Calculate expected ratio for 64 bands
        let expectedRatio = pow(26000.0 / 20.0, 1.0 / Float(63))

        // Verify logarithmic spacing
        for i in 1..<frequencies.count {
            let actualRatio = frequencies[i] / frequencies[i - 1]
            XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.001)
        }
    }

    @MainActor
    func testFrequenciesForBandCount_allWithinRange() {
        for bandCount in [1, 2, 8, 16, 32, 64] {
            let frequencies = EQConfiguration.frequenciesForBandCount(bandCount)

            for (index, freq) in frequencies.enumerated() {
                XCTAssertGreaterThanOrEqual(freq, 20.0, "Band \(index) frequency \(freq) is below minimum")
                // Allow small floating-point tolerance above 26000
                XCTAssertLessThanOrEqual(freq, 26001.0, "Band \(index) frequency \(freq) is above maximum")
            }
        }
    }

    // MARK: - Band Count Clamping Tests

    @MainActor
    func testClampBandCount_boundaries() {
        // Lower boundary: 1
        XCTAssertEqual(EQConfiguration.clampBandCount(1), 1)

        // Upper boundary: 64
        XCTAssertEqual(EQConfiguration.clampBandCount(64), 64)

        // Mid-range values
        XCTAssertEqual(EQConfiguration.clampBandCount(32), 32)
        XCTAssertEqual(EQConfiguration.clampBandCount(16), 16)
    }

    @MainActor
    func testClampBandCount_invalidValues() {
        // Zero should clamp to 1
        XCTAssertEqual(EQConfiguration.clampBandCount(0), 1)

        // Negative values should clamp to 1
        XCTAssertEqual(EQConfiguration.clampBandCount(-1), 1)
        XCTAssertEqual(EQConfiguration.clampBandCount(-100), 1)

        // Values above 64 should clamp to 64
        XCTAssertEqual(EQConfiguration.clampBandCount(65), 64)
        XCTAssertEqual(EQConfiguration.clampBandCount(100), 64)
        XCTAssertEqual(EQConfiguration.clampBandCount(1000), 64)
    }

    func testClampBandCount_maxBandCountConstant() {
        // Verify maxBandCount is 64 as documented
        XCTAssertEqual(EQConfiguration.maxBandCount, 64)
    }

    func testClampBandCount_defaultBandCountConstant() {
        // Verify defaultBandCount is 32 as documented
        XCTAssertEqual(EQConfiguration.defaultBandCount, 32)
    }

    // MARK: - EQConfiguration Instance Tests

    @MainActor
    func testInit_withDefaultBandCount() {
        let storage = UserDefaults(suiteName: "TestSuite-\(UUID().uuidString)")!
        let config = EQConfiguration(storage: storage)

        XCTAssertEqual(config.activeBandCount, EQConfiguration.defaultBandCount)
        XCTAssertEqual(config.bands.count, EQConfiguration.maxBandCount)
    }

    @MainActor
    func testInit_withCustomBandCount() {
        let storage = UserDefaults(suiteName: "TestSuite-\(UUID().uuidString)")!
        let config = EQConfiguration(initialBandCount: 16, storage: storage)

        XCTAssertEqual(config.activeBandCount, 16)
    }

    @MainActor
    func testInit_clampsInvalidBandCount() {
        let storage = UserDefaults(suiteName: "TestSuite-\(UUID().uuidString)")!

        // Band count too high
        let configHigh = EQConfiguration(initialBandCount: 100, storage: storage)
        XCTAssertEqual(configHigh.activeBandCount, 64)

        // Band count too low
        let configLow = EQConfiguration(initialBandCount: 0, storage: storage)
        XCTAssertEqual(configLow.activeBandCount, 1)
    }

    @MainActor
    func testSetActiveBandCount_clampsValue() {
        let storage = UserDefaults(suiteName: "TestSuite-\(UUID().uuidString)")!
        let config = EQConfiguration(storage: storage)

        let result = config.setActiveBandCount(100)
        XCTAssertEqual(result, 64)
        XCTAssertEqual(config.activeBandCount, 64)
    }

    func testDefaultBandwidth() {
        // Verify default bandwidth constant
        XCTAssertEqual(EQConfiguration.defaultBandwidth, 0.67)
    }
}
