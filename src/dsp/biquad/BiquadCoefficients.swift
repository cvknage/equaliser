/// Normalised biquad filter coefficients.
///
/// These coefficients represent a second-order IIR filter using the standard
/// transfer function:
///
///   H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
///
/// The coefficients are "normalised" meaning a0 has been divided out,
/// so the denominator is expressed as (1 + a1*z^-1 + a2*z^-2) rather
/// than (a0 + a1*z^-1 + a2*z^-2).
///
/// This value type is safe to copy between threads and requires no
/// synchronisation.
struct BiquadCoefficients: Sendable, Equatable {
    /// Feedforward coefficient b0
    let b0: Double
    /// Feedforward coefficient b1
    let b1: Double
    /// Feedforward coefficient b2
    let b2: Double
    /// Feedback coefficient a1 (already normalised by a0)
    let a1: Double
    /// Feedback coefficient a2 (already normalised by a0)
    let a2: Double

    /// Identity (passthrough) coefficients — passes input to output unchanged.
    /// b0=1, all other coefficients = 0
    static let identity = BiquadCoefficients(b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)

    /// Creates coefficients for a DC-blocking filter (high-pass at very low frequency).
    /// Useful for removing DC offset from audio.
    static var dcBlocker: BiquadCoefficients {
        // Simple one-pole high-pass at ~20 Hz
        let coeff = 0.995
        return BiquadCoefficients(
            b0: (1.0 + coeff) / 2.0,
            b1: -(1.0 + coeff) / 2.0,
            b2: 0.0,
            a1: -coeff,
            a2: 0.0
        )
    }
}