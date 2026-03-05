import XCTest
@testable import EqualiserApp

final class MeterCalculationTests: XCTestCase {
    // MARK: - dB to Linear Conversion Tests

    /// Standard audio formula: linear = 10^(dB/20)
    private func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }

    /// Standard audio formula: dB = 20 * log10(linear)
    private func linearToDb(_ linear: Float) -> Float {
        guard linear > 0 else { return -.infinity }
        return 20.0 * log10(linear)
    }

    func testDbToLinear_referenceValues() {
        // 0 dB → 1.0 (unity gain)
        XCTAssertEqual(dbToLinear(0), 1.0, accuracy: 0.001)

        // +6 dB → ~2.0 (double amplitude)
        XCTAssertEqual(dbToLinear(6), 2.0, accuracy: 0.01)

        // -6 dB → ~0.5 (half amplitude)
        XCTAssertEqual(dbToLinear(-6), 0.5, accuracy: 0.01)

        // -20 dB → ~0.1
        XCTAssertEqual(dbToLinear(-20), 0.1, accuracy: 0.001)

        // -12 dB → ~0.25 (quarter amplitude)
        XCTAssertEqual(dbToLinear(-12), 0.25, accuracy: 0.01)

        // +20 dB → 10.0
        XCTAssertEqual(dbToLinear(20), 10.0, accuracy: 0.001)
    }

    func testLinearToDb_referenceValues() {
        // 1.0 → 0 dB
        XCTAssertEqual(linearToDb(1.0), 0, accuracy: 0.001)

        // 2.0 → ~+6 dB
        XCTAssertEqual(linearToDb(2.0), 6.02, accuracy: 0.02)

        // 0.5 → ~-6 dB
        XCTAssertEqual(linearToDb(0.5), -6.02, accuracy: 0.02)

        // 0.1 → -20 dB
        XCTAssertEqual(linearToDb(0.1), -20, accuracy: 0.01)

        // 10.0 → +20 dB
        XCTAssertEqual(linearToDb(10.0), 20, accuracy: 0.01)
    }

    func testDbLinear_roundTrip() {
        let testDbValues: [Float] = [-60, -36, -20, -12, -6, 0, 6, 12, 20]

        for db in testDbValues {
            let linear = dbToLinear(db)
            let roundTripped = linearToDb(linear)
            XCTAssertEqual(roundTripped, db, accuracy: 0.001, "dB value \(db) failed round-trip")
        }
    }

    // MARK: - Normalized Position Tests

    func testNormalizedPosition_boundaries() {
        // 0 dB (max) → 1.0
        XCTAssertEqual(MeterConstants.normalizedPosition(for: 0), 1.0, accuracy: 0.001)

        // -36 dB (min) → 0.0
        XCTAssertEqual(MeterConstants.normalizedPosition(for: -36), 0.0, accuracy: 0.001)
    }

    func testNormalizedPosition_outOfRange() {
        // Above 0 dB should clamp to 1.0
        XCTAssertEqual(MeterConstants.normalizedPosition(for: 6), 1.0, accuracy: 0.001)
        XCTAssertEqual(MeterConstants.normalizedPosition(for: 20), 1.0, accuracy: 0.001)

        // Below -36 dB should clamp to 0.0
        XCTAssertEqual(MeterConstants.normalizedPosition(for: -40), 0.0, accuracy: 0.001)
        XCTAssertEqual(MeterConstants.normalizedPosition(for: -100), 0.0, accuracy: 0.001)
    }

    func testNormalizedPosition_midRange() {
        // Test that mid-range values are properly scaled
        // The function uses gamma correction (gamma = 0.5), so the relationship isn't linear

        // At -18 dB (middle of -36 to 0 range), should be somewhere in the middle
        let midPosition = MeterConstants.normalizedPosition(for: -18)
        XCTAssertGreaterThan(midPosition, 0.2)
        XCTAssertLessThan(midPosition, 0.8)

        // -6 dB should be higher than -18 dB
        let minus6Position = MeterConstants.normalizedPosition(for: -6)
        XCTAssertGreaterThan(minus6Position, midPosition)

        // -30 dB should be lower than -18 dB
        let minus30Position = MeterConstants.normalizedPosition(for: -30)
        XCTAssertLessThan(minus30Position, midPosition)
    }

    func testNormalizedPosition_monotonicallyIncreasing() {
        // Higher dB values should always give higher normalized positions
        let dbValues: [Float] = [-36, -30, -24, -18, -12, -6, 0]
        var previousPosition: Float = -1

        for db in dbValues {
            let position = MeterConstants.normalizedPosition(for: db)
            XCTAssertGreaterThan(position, previousPosition, "Position should increase as dB increases")
            previousPosition = position
        }
    }

    // MARK: - Meter Constants Tests

    func testMeterRange_values() {
        XCTAssertEqual(MeterConstants.meterRange.lowerBound, -36)
        XCTAssertEqual(MeterConstants.meterRange.upperBound, 0)
    }

    func testGamma_value() {
        XCTAssertEqual(MeterConstants.gamma, 0.5)
    }

    func testStandardTickValues() {
        let expectedTicks: [Float] = [0, -6, -12, -18, -24, -30, -36]
        XCTAssertEqual(MeterConstants.standardTickValues, expectedTicks)
    }

    // MARK: - Peak Detection Tests

    func testPeakDetection_maxAbsValue() {
        // Test that peak detection finds maximum absolute value
        let samples: [Float] = [-0.5, 0.3, -0.8, 0.2, 0.6]
        let peak = samples.map { abs($0) }.max() ?? 0

        XCTAssertEqual(peak, 0.8, accuracy: 0.001)
    }

    func testPeakDetection_negativeOnly() {
        let samples: [Float] = [-0.2, -0.5, -0.3, -0.1]
        let peak = samples.map { abs($0) }.max() ?? 0

        XCTAssertEqual(peak, 0.5, accuracy: 0.001)
    }

    func testPeakDetection_silence() {
        let samples: [Float] = [0, 0, 0, 0]
        let peak = samples.map { abs($0) }.max() ?? 0

        XCTAssertEqual(peak, 0)
    }

    // MARK: - RMS Calculation Tests

    /// Standard RMS formula: sqrt(sum(x^2) / n)
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }

    func testRmsCalculation_dcSignal() {
        // For a constant (DC) signal, RMS equals the amplitude
        let amplitude: Float = 0.5
        let samples = [Float](repeating: amplitude, count: 100)
        let rms = calculateRMS(samples)

        XCTAssertEqual(rms, amplitude, accuracy: 0.001)
    }

    func testRmsCalculation_sineWave() {
        // For a sine wave, RMS = amplitude / sqrt(2)
        let amplitude: Float = 1.0
        let sampleCount = 1000
        var samples = [Float]()

        for i in 0..<sampleCount {
            let phase = Float(i) / Float(sampleCount) * 2 * .pi
            samples.append(amplitude * sin(phase))
        }

        let rms = calculateRMS(samples)
        let expectedRMS = amplitude / sqrt(2)

        XCTAssertEqual(rms, expectedRMS, accuracy: 0.01)
    }

    func testRmsCalculation_silence() {
        let samples: [Float] = [0, 0, 0, 0, 0]
        let rms = calculateRMS(samples)

        XCTAssertEqual(rms, 0)
    }

    func testRmsCalculation_squareWave() {
        // For a square wave oscillating between +A and -A, RMS equals |A|
        let amplitude: Float = 0.8
        var samples = [Float]()

        for i in 0..<100 {
            samples.append(i % 2 == 0 ? amplitude : -amplitude)
        }

        let rms = calculateRMS(samples)

        XCTAssertEqual(rms, amplitude, accuracy: 0.001)
    }

    // MARK: - ChannelMeterState Tests

    func testChannelMeterState_silentConstant() {
        let silent = ChannelMeterState.silent

        XCTAssertEqual(silent.peak, 0)
        XCTAssertEqual(silent.peakHold, 0)
        XCTAssertEqual(silent.peakHoldTimeRemaining, 0)
        XCTAssertEqual(silent.clipHold, 0)
        XCTAssertEqual(silent.rms, 0)
        XCTAssertFalse(silent.isClipping)
    }

    func testChannelMeterState_isClipping() {
        // Not clipping when clipHold is 0
        var state = ChannelMeterState(peak: 1.0, peakHold: 1.0, peakHoldTimeRemaining: 0, clipHold: 0, rms: 0.5)
        XCTAssertFalse(state.isClipping)

        // Clipping when clipHold > 0
        state.clipHold = 0.5
        XCTAssertTrue(state.isClipping)
    }

    // MARK: - StereoMeterState Tests

    func testStereoMeterState_silentConstant() {
        let silent = StereoMeterState.silent

        XCTAssertEqual(silent.left, ChannelMeterState.silent)
        XCTAssertEqual(silent.right, ChannelMeterState.silent)
    }
}
