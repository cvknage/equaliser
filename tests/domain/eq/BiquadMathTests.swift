import XCTest
@testable import Equaliser

final class BiquadMathTests: XCTestCase {
    // MARK: - Test Constants

    let sampleRate: Double = 48000.0
    let tolerance: Double = 1e-6

    // MARK: - Identity Tests

    func testIdentityCoefficients() {
        let identity = BiquadCoefficients.identity

        XCTAssertEqual(identity.b0, 1.0, accuracy: tolerance)
        XCTAssertEqual(identity.b1, 0.0, accuracy: tolerance)
        XCTAssertEqual(identity.b2, 0.0, accuracy: tolerance)
        XCTAssertEqual(identity.a1, 0.0, accuracy: tolerance)
        XCTAssertEqual(identity.a2, 0.0, accuracy: tolerance)
    }

    // MARK: - Parametric EQ Tests

    func testParametricBoost() {
        // +6 dB boost at 1 kHz, Q=1.0
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 1.0,
            gain: 6.0
        )

        // For a boost, b0 should be greater than 1 at resonance
        // The exact values depend on the formula implementation
        XCTAssertGreaterThan(coeffs.b0, 1.0)
        XCTAssertLessThan(abs(coeffs.a1), 2.0) // Stability check
    }

    func testParametricCut() {
        // -6 dB cut at 1 kHz, Q=1.0
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 1.0,
            gain: -6.0
        )

        // For a cut, b0 should be less than 1 at resonance
        XCTAssertLessThan(coeffs.b0, 1.0)
        XCTAssertLessThan(abs(coeffs.a1), 2.0) // Stability check
    }

    func testParametric0DBGain() {
        // 0 dB gain should produce approximately unity gain at center frequency
        // The filter still has shape (Q affects bandwidth) but no boost/cut
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 1.0,
            gain: 0.0
        )

        // With 0 dB gain, the filter should be close to unity at all frequencies
        // b0 ≈ 1 and other coefficients should be small
        XCTAssertGreaterThan(coeffs.b0, 0.9)
        XCTAssertLessThan(abs(coeffs.a1), 2.0) // Stability check
    }

    // MARK: - Low-Pass Tests

    func testLowPass() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .lowPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 0.707, // Butterworth Q
            gain: 0.0
        )

        // Low-pass: b0 = b2, b1 = 2*b0 (symmetric)
        XCTAssertEqual(coeffs.b0, coeffs.b2, accuracy: tolerance)
        XCTAssertEqual(coeffs.b1, 2.0 * coeffs.b0, accuracy: tolerance)
        XCTAssertGreaterThan(coeffs.b0, 0.0)
    }

    func testLowPassButterworthQ() {
        // Butterworth (maximally flat) Q = 0.707
        let coeffs = BiquadMath.calculateCoefficients(
            type: .lowPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 0.707,
            gain: 0.0
        )

        // At DC, low-pass gain should be 1 (b0+b1+b2)/(1+a1+a2)
        let dcGain = (coeffs.b0 + coeffs.b1 + coeffs.b2) / (1.0 + coeffs.a1 + coeffs.a2)
        XCTAssertEqual(dcGain, 1.0, accuracy: 0.01)
    }

    // MARK: - High-Pass Tests

    func testHighPass() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .highPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 0.707, // Butterworth Q
            gain: 0.0
        )

        // High-pass: b0 = b2 (but opposite sign to low-pass), b1 = -2*b0
        XCTAssertEqual(coeffs.b0, coeffs.b2, accuracy: tolerance)
        XCTAssertEqual(coeffs.b1, -2.0 * coeffs.b0, accuracy: tolerance)

        // At Nyquist, high-pass gain should approach 1
        // This is harder to verify with coefficients alone
    }

    func testHighPassButterworthQ() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .highPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 0.707,
            gain: 0.0
        )

        // At high frequencies, high-pass gain should be 1
        // b0 + b1 + b2 should be close to 0 (DC blocking)
        // and 1 + a1 + a2 should be close to (1 + a1 + a2) for normalization
        let dcGain = (coeffs.b0 + coeffs.b1 + coeffs.b2) / (1.0 + coeffs.a1 + coeffs.a2)
        XCTAssertEqual(abs(dcGain), 0.0, accuracy: 0.01) // DC should be blocked
    }

    // MARK: - Shelf Tests

    func testLowShelfBoost() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .lowShelf,
            sampleRate: sampleRate,
            frequency: 200.0,
            bandwidth: 0.0, // Not used for shelves
            gain: 6.0
        )

        // At DC, low-shelf gain should equal the boost
        let dcGainLinear = (coeffs.b0 + coeffs.b1 + coeffs.b2) / (1.0 + coeffs.a1 + coeffs.a2)
        let expectedGain = pow(10.0, 6.0 / 20.0) // 6 dB ≈ 1.995
        XCTAssertEqual(dcGainLinear, expectedGain, accuracy: 0.1)
    }

    func testHighShelfBoost() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .highShelf,
            sampleRate: sampleRate,
            frequency: 8000.0,
            bandwidth: 0.0,
            gain: 6.0
        )

        // At Nyquist, high-shelf gain should equal the boost
        // For 2nd-order biquad, this is approximate
        XCTAssertGreaterThan(coeffs.b0, 0.0)
    }

    func testLowShelf0DBGain() {
        // With 0 dB gain, a shelf should pass signal unchanged (identity)
        let coeffs = BiquadMath.calculateCoefficients(
            type: .lowShelf,
            sampleRate: sampleRate,
            frequency: 200.0,
            bandwidth: 0.0,
            gain: 0.0
        )

        // DC gain should be 1 (0 dB)
        let dcGain = (coeffs.b0 + coeffs.b1 + coeffs.b2) / (1.0 + coeffs.a1 + coeffs.a2)
        XCTAssertEqual(abs(dcGain), 1.0, accuracy: 0.01)
    }

    // MARK: - Band Pass / Notch Tests

    func testBandPass() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .bandPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 1.0,
            gain: 0.0
        )

        // Band-pass: b1 = 0, b2 = -b0
        XCTAssertEqual(coeffs.b1, 0.0, accuracy: tolerance)
        XCTAssertEqual(coeffs.b2, -coeffs.b0, accuracy: tolerance)
    }

    func testNotch() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .notch,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 1.0,
            gain: 0.0
        )

        // Notch: b0 = 1, b1 = -2*cos(w), b2 = 1, a0 = 1+alpha, a1 = -2*cos(w), a2 = 1-alpha
        XCTAssertEqual(coeffs.b0, coeffs.b2, accuracy: tolerance)
        XCTAssertEqual(coeffs.b1, coeffs.a1, accuracy: tolerance)
    }

    // MARK: - Resonant Filter Tests

    func testResonantLowPass() {
        // Resonant low-pass uses bandwidth as Q directly
        let coeffs = BiquadMath.calculateCoefficients(
            type: .resonantLowPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 5.0, // High Q for resonance
            gain: 0.0
        )

        // High Q should produce coefficients with resonance
        // The b coefficients should be positive for low-pass
        XCTAssertGreaterThan(coeffs.b0, 0.0)
        XCTAssertFalse(coeffs.b0.isNaN)
        XCTAssertFalse(coeffs.a1.isNaN)
    }

    func testResonantHighPass() {
        let coeffs = BiquadMath.calculateCoefficients(
            type: .resonantHighPass,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 5.0,
            gain: 0.0
        )

        // Similar structure to high-pass but with resonant Q
        XCTAssertEqual(coeffs.b0, coeffs.b2, accuracy: tolerance)
        XCTAssertFalse(coeffs.b0.isNaN)
        XCTAssertFalse(coeffs.a1.isNaN)
    }

    func testResonantShelfQ() {
        // Resonant shelves accept Q parameter
        let coeffsLowShelf = BiquadMath.calculateCoefficients(
            type: .resonantLowShelf,
            sampleRate: sampleRate,
            frequency: 200.0,
            bandwidth: 2.0, // Q = 2
            gain: 6.0
        )

        let coeffsHighShelf = BiquadMath.calculateCoefficients(
            type: .resonantHighShelf,
            sampleRate: sampleRate,
            frequency: 8000.0,
            bandwidth: 2.0,
            gain: 6.0
        )

        // Both should have valid coefficients
        XCTAssertGreaterThan(coeffsLowShelf.b0, 0.0)
        XCTAssertGreaterThan(coeffsHighShelf.b0, 0.0)
    }

    // MARK: - Edge Cases

    func testLowFrequency() {
        // Very low frequency near DC
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 20.0,
            bandwidth: 1.0,
            gain: 6.0
        )

        // Should still produce valid coefficients
        XCTAssertFalse(coeffs.b0.isNaN)
        XCTAssertFalse(coeffs.b1.isNaN)
        XCTAssertFalse(coeffs.b2.isNaN)
        XCTAssertFalse(coeffs.a1.isNaN)
        XCTAssertFalse(coeffs.a2.isNaN)
    }

    func testHighFrequency() {
        // Frequency near Nyquist
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 20000.0,
            bandwidth: 1.0,
            gain: 6.0
        )

        // Should still produce valid coefficients
        XCTAssertFalse(coeffs.b0.isNaN)
        XCTAssertFalse(coeffs.b1.isNaN)
        XCTAssertFalse(coeffs.b2.isNaN)
        XCTAssertFalse(coeffs.a1.isNaN)
        XCTAssertFalse(coeffs.a2.isNaN)
    }

    func testNarrowBandwidth() {
        // Very narrow bandwidth (high Q)
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 0.1, // Very narrow
            gain: 6.0
        )

        // Narrow bandwidth = high Q = coefficients can be large
        XCTAssertFalse(coeffs.b0.isNaN)
        XCTAssertFalse(coeffs.a1.isNaN)
    }

    func testWideBandwidth() {
        // Very wide bandwidth (low Q)
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 8.0, // Very wide
            gain: 6.0
        )

        // Wide bandwidth = low Q = gentler slopes
        XCTAssertFalse(coeffs.b0.isNaN)
        XCTAssertFalse(coeffs.a1.isNaN)
    }

    // MARK: - Filter Type Tests

    func testAllFilterTypesProduceValidCoefficients() {
        let filterTypes: [FilterType] = FilterType.allCases

        for filterType in filterTypes {
            let coeffs = BiquadMath.calculateCoefficients(
                type: filterType,
                sampleRate: sampleRate,
                frequency: 1000.0,
                bandwidth: 0.67,
                gain: 6.0
            )

            XCTAssertFalse(coeffs.b0.isNaN, "\(filterType.displayName) produced NaN b0")
            XCTAssertFalse(coeffs.b1.isNaN, "\(filterType.displayName) produced NaN b1")
            XCTAssertFalse(coeffs.b2.isNaN, "\(filterType.displayName) produced NaN b2")
            XCTAssertFalse(coeffs.a1.isNaN, "\(filterType.displayName) produced NaN a1")
            XCTAssertFalse(coeffs.a2.isNaN, "\(filterType.displayName) produced NaN a2")
        }
    }

    // MARK: - Normalisation Test

    func testNormalisationPreservesTransferFunction() {
        // Verify that normalisation produces a stable filter
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            bandwidth: 1.0,
            gain: 6.0
        )

        // For stability, poles should be inside unit circle
        // This means |a2| < 1 and |a1| < 2 for real coefficients
        XCTAssertLessThan(abs(coeffs.a2), 1.0 + tolerance)
        XCTAssertLessThan(abs(coeffs.a1), 2.0 + tolerance)
    }
}