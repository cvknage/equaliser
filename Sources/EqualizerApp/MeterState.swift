import Foundation

struct ChannelMeterState: Equatable {
    var peak: Float
    var peakHold: Float
    var peakHoldTimeRemaining: TimeInterval
    var clipHold: TimeInterval
    var rms: Float

    var isClipping: Bool { clipHold > 0 }

    static let silent = ChannelMeterState(peak: 0, peakHold: 0, peakHoldTimeRemaining: 0, clipHold: 0, rms: 0)
}

struct StereoMeterState: Equatable {
    var left: ChannelMeterState
    var right: ChannelMeterState

    static let silent = StereoMeterState(left: .silent, right: .silent)
}

/// Shared constants for meter visualization.
enum MeterConstants {
    static let meterRange: ClosedRange<Float> = -36...0
    static let gamma: Float = 0.5
    static let meterHeight: CGFloat = 126
    static let standardTickValues: [Float] = [0, -6, -12, -18, -24, -30, -36]

    /// Converts a dB value to a normalized position (0-1) matching the meter visual.
    static func normalizedPosition(for db: Float) -> Float {
        if db <= meterRange.lowerBound { return 0 }
        if db >= meterRange.upperBound { return 1 }
        let amp = powf(10.0, 0.05 * db)
        let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
        let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
        let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
        return powf(normalizedAmp, gamma)
    }
}
