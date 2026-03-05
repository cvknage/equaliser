import XCTest
@testable import EqualiserApp

final class BandwidthConverterTests: XCTestCase {
    // MARK: - Q to Bandwidth Tests

    func testQToBandwidth_referenceValues() {
        // Butterworth: Q = 0.707 → BW ≈ 1.9 octaves (not exactly 2.0)
        XCTAssertEqual(BandwidthConverter.qToBandwidth(0.707), 1.9, accuracy: 0.05)

        // Unity Q = 1.0 → BW ≈ 1.39 octaves
        XCTAssertEqual(BandwidthConverter.qToBandwidth(1.0), 1.39, accuracy: 0.05)

        // Q = 1.41 → BW ≈ 1.0 octave
        XCTAssertEqual(BandwidthConverter.qToBandwidth(1.41), 1.0, accuracy: 0.05)

        // AutoEQ default: Q = 4.36 → BW ≈ 0.33 octaves
        XCTAssertEqual(BandwidthConverter.qToBandwidth(4.36), 0.33, accuracy: 0.02)
    }

    func testQToBandwidth_zeroAndNegative() {
        // Invalid Q values should return 0
        XCTAssertEqual(BandwidthConverter.qToBandwidth(0), 0)
        XCTAssertEqual(BandwidthConverter.qToBandwidth(-1), 0)
        XCTAssertEqual(BandwidthConverter.qToBandwidth(-0.5), 0)
    }

    // MARK: - Bandwidth to Q Tests

    func testBandwidthToQ_referenceValues() {
        // BW = 2.0 octaves → Q ≈ 0.667 (slightly below Butterworth)
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(2.0), 0.667, accuracy: 0.01)

        // BW = 1.9 octaves → Q ≈ 0.707 (Butterworth)
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(1.9), 0.707, accuracy: 0.02)

        // BW = 1.39 octaves → Q ≈ 1.0
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(1.39), 1.0, accuracy: 0.05)

        // BW = 1.0 octave → Q ≈ 1.41
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(1.0), 1.41, accuracy: 0.02)

        // BW = 0.33 octaves → Q ≈ 4.36 (AutoEQ default)
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(0.33), 4.36, accuracy: 0.1)
    }

    func testBandwidthToQ_zeroAndNegative() {
        // Invalid bandwidth values should return 0
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(0), 0)
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(-1), 0)
        XCTAssertEqual(BandwidthConverter.bandwidthToQ(-0.5), 0)
    }

    // MARK: - Round-Trip Tests

    func testRoundTrip_qToBandwidthToQ() {
        let testQValues: [Float] = [0.5, 0.707, 1.0, 1.41, 2.0, 4.36, 10.0]

        for q in testQValues {
            let bandwidth = BandwidthConverter.qToBandwidth(q)
            let roundTrippedQ = BandwidthConverter.bandwidthToQ(bandwidth)
            XCTAssertEqual(roundTrippedQ, q, accuracy: 0.001, "Q \(q) failed round-trip")
        }
    }

    func testRoundTrip_bandwidthToQToBandwidth() {
        let testBandwidthValues: [Float] = [0.1, 0.33, 0.5, 1.0, 1.39, 2.0, 3.0, 5.0]

        for bw in testBandwidthValues {
            let q = BandwidthConverter.bandwidthToQ(bw)
            let roundTrippedBW = BandwidthConverter.qToBandwidth(q)
            XCTAssertEqual(roundTrippedBW, bw, accuracy: 0.001, "Bandwidth \(bw) failed round-trip")
        }
    }

    // MARK: - Clamping Tests

    func testClampBandwidth_boundaries() {
        // Test lower boundary (0.05 octaves)
        XCTAssertEqual(BandwidthConverter.clampBandwidth(0.01), 0.05)
        XCTAssertEqual(BandwidthConverter.clampBandwidth(0.05), 0.05)

        // Test upper boundary (5.0 octaves)
        XCTAssertEqual(BandwidthConverter.clampBandwidth(5.0), 5.0)
        XCTAssertEqual(BandwidthConverter.clampBandwidth(10.0), 5.0)

        // Test values within range
        XCTAssertEqual(BandwidthConverter.clampBandwidth(1.0), 1.0)
        XCTAssertEqual(BandwidthConverter.clampBandwidth(2.5), 2.5)
    }

    func testClampQ_boundaries() {
        // Test lower boundary (0.1)
        XCTAssertEqual(BandwidthConverter.clampQ(0.01), 0.1)
        XCTAssertEqual(BandwidthConverter.clampQ(0.1), 0.1)

        // Test upper boundary (100)
        XCTAssertEqual(BandwidthConverter.clampQ(100), 100)
        XCTAssertEqual(BandwidthConverter.clampQ(150), 100)

        // Test values within range
        XCTAssertEqual(BandwidthConverter.clampQ(1.0), 1.0)
        XCTAssertEqual(BandwidthConverter.clampQ(50.0), 50.0)
    }

    // MARK: - Reference Table Tests

    func testReferenceTable_consistency() {
        // Verify that the reference table values are consistent with computed values
        for entry in BandwidthConverter.referenceTable {
            let computedBandwidth = BandwidthConverter.qToBandwidth(entry.q)
            XCTAssertEqual(
                entry.bandwidth,
                computedBandwidth,
                accuracy: 0.001,
                "Reference table entry for Q=\(entry.q) (\(entry.description)) is inconsistent"
            )
        }
    }

    func testReferenceTable_containsExpectedValues() {
        // Verify expected entries exist in the reference table
        let qValues = BandwidthConverter.referenceTable.map { $0.q }

        XCTAssertTrue(qValues.contains(0.707), "Missing Butterworth Q value")
        XCTAssertTrue(qValues.contains(1.0), "Missing unity Q value")
        XCTAssertTrue(qValues.contains(1.41), "Missing 1-octave Q value")
        XCTAssertTrue(qValues.contains(4.36), "Missing AutoEQ default Q value")
    }
}
