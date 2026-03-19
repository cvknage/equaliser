import Foundation

/// Pure functions for meter calculations.
/// All functions are real-time safe: no allocations, no locks, no side effects.
/// Safe to call from audio render thread.
///
/// These functions are marked `@inline(__always)` to ensure they are inlined
/// in performance-critical audio code paths.
enum MeterMath {
    // MARK: - dB Conversion

    /// Converts linear amplitude to decibels.
    /// - Parameters:
    ///   - linear: Linear amplitude (0-1 typical range).
    ///   - silence: The silence floor value to return for very low inputs.
    /// - Returns: dBFS value (0 = full scale, negative = quieter).
    @inline(__always)
    static func linearToDB(_ linear: Float, silence: Float = MeterConstants.silenceDB) -> Float {
        AudioMath.linearToDB(linear, silence: silence)
    }

    /// Converts decibels to linear amplitude.
    /// - Parameter db: dBFS value.
    /// - Returns: Linear amplitude.
    @inline(__always)
    static func dbToLinear(_ db: Float) -> Float {
        AudioMath.dbToLinear(db)
    }
    
    // MARK: - Peak/RMS Calculation
    
    /// Calculates peak level from a buffer of samples.
    /// - Parameters:
    ///   - buffer: Pointer to sample buffer.
    ///   - frameCount: Number of frames to process.
    /// - Returns: Linear peak value (0-1).
    @inline(__always)
    static func calculatePeak(buffer: UnsafePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        var peak: Float = 0
        var frame = 0
        while frame < frameCount {
            peak = max(peak, abs(buffer[frame]))
            frame += 1
        }
        return peak
    }
    
    /// Calculates RMS level from a buffer of samples.
    /// - Parameters:
    ///   - buffer: Pointer to sample buffer.
    ///   - frameCount: Number of frames to process.
    /// - Returns: Linear RMS value (0-1).
    @inline(__always)
    static func calculateRMS(buffer: UnsafePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        var sumSquares: Float = 0
        var frame = 0
        while frame < frameCount {
            let sample = buffer[frame]
            sumSquares += sample * sample
            frame += 1
        }
        return sqrt(sumSquares / Float(frameCount))
    }
    
    // MARK: - Smoothing
    
    /// Applies smoothing to a meter value with different attack/release rates.
    /// Attack is typically faster (higher smoothing) for responsive peaks.
    /// Release is typically slower (lower smoothing) for smooth decay.
    /// - Parameters:
    ///   - current: Current meter value (0-1).
    ///   - target: Target meter value (0-1).
    ///   - attackSmoothing: Smoothing for rising values (1.0 = instant).
    ///   - releaseSmoothing: Smoothing for falling values (lower = slower).
    /// - Returns: Smoothed value (0-1).
    @inline(__always)
    static func smoothMeter(
        current: Float,
        target: Float,
        attackSmoothing: Float,
        releaseSmoothing: Float
    ) -> Float {
        let delta = target - current
        let smoothing = delta >= 0 ? attackSmoothing : releaseSmoothing
        let raw = current + delta * smoothing
        return max(0, min(1, raw))
    }
}