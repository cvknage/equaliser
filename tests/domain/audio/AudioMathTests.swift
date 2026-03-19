import XCTest
@testable import Equaliser

final class AudioMathTests: XCTestCase {
    // MARK: - dbToLinear Tests

    func testDbToLinear_referenceValues() {
        // 0 dB → 1.0 (unity gain)
        XCTAssertEqual(AudioMath.dbToLinear(0), 1.0, accuracy: 0.001)

        // +6 dB → ~2.0 (double amplitude)
        XCTAssertEqual(AudioMath.dbToLinear(6), 2.0, accuracy: 0.01)

        // -6 dB → ~0.5 (half amplitude)
        XCTAssertEqual(AudioMath.dbToLinear(-6), 0.5, accuracy: 0.01)

        // -20 dB → ~0.1
        XCTAssertEqual(AudioMath.dbToLinear(-20), 0.1, accuracy: 0.001)

        // -12 dB → ~0.25 (quarter amplitude)
        XCTAssertEqual(AudioMath.dbToLinear(-12), 0.25, accuracy: 0.01)

        // +20 dB → 10.0
        XCTAssertEqual(AudioMath.dbToLinear(20), 10.0, accuracy: 0.001)
    }

    // MARK: - linearToDB Tests

    func testLinearToDB_referenceValues() {
        // 1.0 → 0 dB
        XCTAssertEqual(AudioMath.linearToDB(1.0), 0, accuracy: 0.001)

        // 2.0 → ~+6 dB
        XCTAssertEqual(AudioMath.linearToDB(2.0), 6.02, accuracy: 0.02)

        // 0.5 → ~-6 dB
        XCTAssertEqual(AudioMath.linearToDB(0.5), -6.02, accuracy: 0.02)

        // 0.1 → -20 dB
        XCTAssertEqual(AudioMath.linearToDB(0.1), -20, accuracy: 0.01)

        // 10.0 → +20 dB
        XCTAssertEqual(AudioMath.linearToDB(10.0), 20, accuracy: 0.01)
    }

    func testLinearToDB_silence() {
        // Very low values should return silence floor
        XCTAssertEqual(AudioMath.linearToDB(0), -90, accuracy: 0.001)
        XCTAssertEqual(AudioMath.linearToDB(1e-8), -90, accuracy: 0.001)
        XCTAssertEqual(AudioMath.linearToDB(0, silence: -60), -60, accuracy: 0.001)
    }

    func testRoundTrip() {
        let testDbValues: [Float] = [-60, -36, -20, -12, -6, 0, 6, 12, 20]

        for db in testDbValues {
            let linear = AudioMath.dbToLinear(db)
            let roundTripped = AudioMath.linearToDB(linear)
            XCTAssertEqual(roundTripped, db, accuracy: 0.001, "dB value \(db) failed round-trip")
        }
    }
}