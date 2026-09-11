import Foundation

/// Converts scroll-wheel and trackpad movement into EQ gain steps.
struct GainScrollAdjustment {
    static let gainStep: Float = 0.1
    static let trackpadPointsPerStep: CGFloat = 4
    static let mouseWheelDeltaPerStep: CGFloat = 1

    private var trackpadRemainder: CGFloat = 0

    mutating func adjustedGain(
        from gain: Float,
        scrollingDeltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) -> Float {
        let stepCount = scrollStepCount(
            scrollingDeltaY: scrollingDeltaY,
            hasPreciseScrollingDeltas: hasPreciseScrollingDeltas
        )
        guard stepCount != 0 else { return gain }

        let currentStep = (gain / Self.gainStep).rounded()
        let adjusted = (currentStep + Float(stepCount)) * Self.gainStep
        return AudioConstants.clampGain(adjusted)
    }

    private mutating func scrollStepCount(
        scrollingDeltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) -> Int {
        guard scrollingDeltaY != 0 else { return 0 }

        guard hasPreciseScrollingDeltas else {
            trackpadRemainder = 0
            let direction = scrollingDeltaY > 0 ? 1 : -1
            let acceleratedStepCount = max(
                1,
                Int(abs(scrollingDeltaY) / Self.mouseWheelDeltaPerStep)
            )
            return direction * acceleratedStepCount
        }

        trackpadRemainder += scrollingDeltaY
        let stepCount = Int(trackpadRemainder / Self.trackpadPointsPerStep)
        trackpadRemainder -= CGFloat(stepCount) * Self.trackpadPointsPerStep
        return stepCount
    }
}
