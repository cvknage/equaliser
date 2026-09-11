import XCTest
@testable import Equaliser

final class GainScrollAdjustmentTests: XCTestCase {
    func testWheelScrollAdjustsByThreeTenthsOfADecibel() {
        var adjustment = GainScrollAdjustment()

        XCTAssertEqual(
            adjustment.adjustedGain(
                from: 0,
                scrollingDeltaY: 3,
                hasPreciseScrollingDeltas: false
            ),
            0.3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            adjustment.adjustedGain(
                from: 0,
                scrollingDeltaY: -3,
                hasPreciseScrollingDeltas: false
            ),
            -0.3,
            accuracy: 0.0001
        )
    }

    func testFineTrackpadMovementAccumulatesToOneTenthOfADecibel() {
        var adjustment = GainScrollAdjustment()

        XCTAssertEqual(
            adjustment.adjustedGain(
                from: 0,
                scrollingDeltaY: 1.5,
                hasPreciseScrollingDeltas: true
            ),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            adjustment.adjustedGain(
                from: 0,
                scrollingDeltaY: 2.5,
                hasPreciseScrollingDeltas: true
            ),
            0.1,
            accuracy: 0.0001
        )
    }

    func testAcceleratedTrackpadMovementAdjustsMultipleSteps() {
        var adjustment = GainScrollAdjustment()

        XCTAssertEqual(
            adjustment.adjustedGain(
                from: -3,
                scrollingDeltaY: 12,
                hasPreciseScrollingDeltas: true
            ),
            -2.7,
            accuracy: 0.0001
        )
    }

    func testAcceleratedMouseWheelMovementAdjustsMultipleSteps() {
        var adjustment = GainScrollAdjustment()

        XCTAssertEqual(
            adjustment.adjustedGain(
                from: -3,
                scrollingDeltaY: 9,
                hasPreciseScrollingDeltas: false
            ),
            -2.1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            adjustment.adjustedGain(
                from: -3,
                scrollingDeltaY: -9,
                hasPreciseScrollingDeltas: false
            ),
            -3.9,
            accuracy: 0.0001
        )
    }

    func testScrollAdjustmentClampsToGainRange() {
        var adjustment = GainScrollAdjustment()

        XCTAssertEqual(
            adjustment.adjustedGain(
                from: AudioConstants.maxGain,
                scrollingDeltaY: 10,
                hasPreciseScrollingDeltas: true
            ),
            AudioConstants.maxGain,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            adjustment.adjustedGain(
                from: AudioConstants.minGain,
                scrollingDeltaY: -10,
                hasPreciseScrollingDeltas: true
            ),
            AudioConstants.minGain,
            accuracy: 0.0001
        )
    }
}
