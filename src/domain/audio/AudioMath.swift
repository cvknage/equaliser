import Foundation

/// Pure functions for audio math conversions.
/// All functions are real-time safe: no allocations, no locks, no side effects.
enum AudioMath {
    /// Converts decibels to linear amplitude.
    /// - Parameter db: dBFS value.
    /// - Returns: Linear amplitude (10^(db/20)).
    @inline(__always)
    static func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }

    /// Converts linear amplitude to decibels.
    /// - Parameters:
    ///   - linear: Linear amplitude.
    ///   - silence: The silence floor value to return for very low inputs (default: -90).
    /// - Returns: dBFS value.
    @inline(__always)
    static func linearToDB(_ linear: Float, silence: Float = -90) -> Float {
        guard linear > 1e-7 else { return silence }
        return max(silence, 20 * log10(linear))
    }
}