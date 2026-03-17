import Foundation
import CoreGraphics

/// Shared constants for audio level meter calculations and visualization.
/// Used by both real-time audio code (RenderCallbackContext) and UI (MeterStore, MeterScaleView).
/// 
/// All constants are defined in one place to ensure consistency across the codebase
/// and to make the meter behavior predictable and documented.
enum MeterConstants {
    // MARK: - Silence Thresholds
    
    /// Minimum dB value for meters (silence floor).
    /// Values below this are treated as complete silence.
    /// Used by RenderCallbackContext for meter calculations.
    static let silenceDB: Float = -90
    
    /// Threshold below which meters are considered silent (for rest detection).
    /// Used by MeterStore to stop updating when audio is quiet.
    /// Slightly above silenceDB to provide hysteresis.
    static let silenceThreshold: Float = -85
    
    /// Threshold for at-rest state (meters stop updating).
    /// When normalized meter values fall below this, the meter enters rest mode.
    static let atRestThreshold: Float = 0.01
    
    // MARK: - Display Range
    
    /// The dB range for meter display.
    /// -36 dB to 0 dB is a common range for audio meters.
    /// Values outside this range are clamped to the range boundaries.
    static let meterRange: ClosedRange<Float> = -36...0
    
    // MARK: - Timing
    
    /// Meter update interval (30 FPS).
    /// Balances smooth animation with CPU efficiency.
    static let meterInterval: TimeInterval = 1.0 / 30.0
    
    /// Duration to hold peak before decay.
    /// Peak hold keeps the highest level visible briefly for easier reading.
    static let peakHoldDuration: TimeInterval = 1.0
    
    /// Duration to show clipping indicator.
    /// Visual feedback for clipping events.
    static let clipHoldDuration: TimeInterval = 0.5
    
    // MARK: - Smoothing Factors
    
    /// Smoothing for peak attack (fast rise).
    /// Value of 1.0 means instant attack for responsive peaks.
    static let peakAttackSmoothing: Float = 1.0
    
    /// Smoothing for peak release (slow fall).
    /// Lower values create smoother decay.
    static let peakReleaseSmoothing: Float = 0.33
    
    /// Smoothing for RMS meter (slower, more averaged).
    /// RMS responds more slowly than peak for averaged levels.
    static let rmsSmoothing: Float = 0.12
    
    /// Peak hold decay per tick (at 30 FPS).
    /// Controls how fast the held peak drops after hold duration.
    static let peakHoldDecayPerTick: Float = 0.02
    
    // MARK: - Display Gamma
    
    /// Gamma value for perceptual scaling of meter display.
    /// Values < 1.0 emphasize lower levels, making quiet sounds more visible.
    /// This provides a more natural perceptual response from -60dB to 0dB.
    static let gamma: Float = 0.5
    
    // MARK: - Channel Limits
    
    /// Maximum number of meter channels (stereo = 2).
    /// Limits meter processing to left/right channels.
    static let maxMeterChannels: Int = 2
    
    /// Minimum change threshold for UI updates.
    /// Prevents excessive redraws for tiny changes.
    static let changeThreshold: Float = 0.002
    
    // MARK: - UI Constants
    
    /// Height of the meter scale view in points.
    static let meterHeight: CGFloat = 126
    
    /// Standard dB tick values for meter scale marks.
    /// These are the labeled positions on the meter scale.
    static let standardTickValues: [Float] = [0, -6, -12, -18, -24, -30, -36]
    
    // MARK: - Normalization
    
    /// Converts a dB value to a normalized position (0-1) for meter display.
    /// Uses gamma correction for perceptual uniformity.
    /// 
    /// - Parameter db: The dBFS value to normalize.
    /// - Returns: Normalized value 0-1 where 0 is minimum and 1 is maximum.
    @inline(__always)
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