import Foundation

/// Pure coefficient calculation using RBJ Audio EQ Cookbook formulas.
///
/// All functions are pure — no state, no side effects, no allocations.
/// Calculations use Double precision for numerical stability (narrow filters
/// at low frequencies need this precision). Results can be converted to Float
/// when building vDSP setups.
///
/// Reference: https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt
enum BiquadMath {
    // MARK: - Main Entry Point

    /// Calculates biquad coefficients for the given filter parameters.
    ///
    /// - Parameters:
    ///   - type: The filter type (parametric, low-pass, high-pass, etc.)
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Centre/cutoff frequency in Hz
    ///   - bandwidth: Bandwidth in octaves (for standard types) or Q (for resonant types)
    ///   - gain: Gain in dB (for parametric and shelf types)
    /// - Returns: Normalised biquad coefficients
    static func calculateCoefficients(
        type: FilterType,
        sampleRate: Double,
        frequency: Double,
        bandwidth: Double,
        gain: Double
    ) -> BiquadCoefficients {
        switch type {
        case .parametric:
            return peakingEQ(
                sampleRate: sampleRate,
                frequency: frequency,
                bandwidth: bandwidth,
                gain: gain
            )
        case .lowPass:
            return lowPass(
                sampleRate: sampleRate,
                frequency: frequency,
                q: bandwidthToQ(bandwidth)
            )
        case .highPass:
            return highPass(
                sampleRate: sampleRate,
                frequency: frequency,
                q: bandwidthToQ(bandwidth)
            )
        case .lowShelf:
            return lowShelf(
                sampleRate: sampleRate,
                frequency: frequency,
                gain: gain
            )
        case .highShelf:
            return highShelf(
                sampleRate: sampleRate,
                frequency: frequency,
                gain: gain
            )
        case .bandPass:
            return bandPass(
                sampleRate: sampleRate,
                frequency: frequency,
                bandwidth: bandwidth
            )
        case .notch:
            return notch(
                sampleRate: sampleRate,
                frequency: frequency,
                bandwidth: bandwidth
            )
        case .resonantLowPass:
            return lowPass(
                sampleRate: sampleRate,
                frequency: frequency,
                q: bandwidth // For resonant types, bandwidth is Q directly
            )
        case .resonantHighPass:
            return highPass(
                sampleRate: sampleRate,
                frequency: frequency,
                q: bandwidth // For resonant types, bandwidth is Q directly
            )
        case .resonantLowShelf:
            return lowShelf(
                sampleRate: sampleRate,
                frequency: frequency,
                gain: gain,
                q: bandwidth // For resonant types, bandwidth is Q directly
            )
        case .resonantHighShelf:
            return highShelf(
                sampleRate: sampleRate,
                frequency: frequency,
                gain: gain,
                q: bandwidth // For resonant types, bandwidth is Q directly
            )
        }
    }

    // MARK: - Peaking EQ (Parametric)

    /// Peaking EQ filter (bell curve).
    ///
    /// Boosts or cuts frequencies around the centre frequency.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Centre frequency in Hz
    ///   - bandwidth: Bandwidth in octaves
    ///   - gain: Gain in dB (positive = boost, negative = cut)
    static func peakingEQ(
        sampleRate: Double,
        frequency: Double,
        bandwidth: Double,
        gain: Double
    ) -> BiquadCoefficients {
        let A = pow(10.0, gain / 40.0) // Gain as amplitude ratio (squared)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)

        // Bandwidth to Q: Q = sinOmega / (2 * sinh(ln(2)/2 * bandwidth * sinOmega/cosOmega))
        // Simplified: alpha = sinOmega * sinh(ln(2)/2 * bandwidth * omega/sinOmega)
        // Or more commonly: alpha = sinOmega * sinh(ln(2)/2 * BW * sinOmega)
        // Using the standard RBJ formula:
        let alpha = sinOmega * sinh(log(2.0) / 2.0 * bandwidth * omega / sinOmega)

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosOmega
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha / A

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - Low-Pass

    /// 2nd-order low-pass filter.
    ///
    /// Passes frequencies below cutoff, attenuates above.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Cutoff frequency in Hz
    ///   - q: Q factor (resonance), typically 0.707 for Butterworth
    static func lowPass(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> BiquadCoefficients {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)

        let b0 = (1.0 - cosOmega) / 2.0
        let b1 = 1.0 - cosOmega
        let b2 = (1.0 - cosOmega) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - High-Pass

    /// 2nd-order high-pass filter.
    ///
    /// Passes frequencies above cutoff, attenuates below.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Cutoff frequency in Hz
    ///   - q: Q factor (resonance), typically 0.707 for Butterworth
    static func highPass(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> BiquadCoefficients {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)

        let b0 = (1.0 + cosOmega) / 2.0
        let b1 = -(1.0 + cosOmega)
        let b2 = (1.0 + cosOmega) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - Low Shelf

    /// Low shelf filter.
    ///
    /// Boosts or cuts frequencies below the shelf frequency.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Shelf frequency in Hz
    ///   - gain: Gain in dB (positive = boost, negative = cut)
    ///   - q: Q factor for shelf slope (default 0.707 for standard shelf)
    static func lowShelf(
        sampleRate: Double,
        frequency: Double,
        gain: Double,
        q: Double = 0.707
    ) -> BiquadCoefficients {
        let A = pow(10.0, gain / 40.0) // Gain as amplitude ratio (squared)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)

        // Shelf slope from Q: higher Q = steeper transition
        // beta = sqrt(A*A + 1) / q gives resonant shelf behaviour
        let beta = sqrt(A * A + 1.0) / q

        let b0 = A * ((A + 1.0) - (A - 1.0) * cosOmega + beta * sinOmega)
        let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosOmega)
        let b2 = A * ((A + 1.0) - (A - 1.0) * cosOmega - beta * sinOmega)
        let a0 = (A + 1.0) + (A - 1.0) * cosOmega + beta * sinOmega
        let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosOmega)
        let a2 = (A + 1.0) + (A - 1.0) * cosOmega - beta * sinOmega

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - High Shelf

    /// High shelf filter.
    ///
    /// Boosts or cuts frequencies above the shelf frequency.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Shelf frequency in Hz
    ///   - gain: Gain in dB (positive = boost, negative = cut)
    ///   - q: Q factor for shelf slope (default 0.707 for standard shelf)
    static func highShelf(
        sampleRate: Double,
        frequency: Double,
        gain: Double,
        q: Double = 0.707
    ) -> BiquadCoefficients {
        let A = pow(10.0, gain / 40.0) // Gain as amplitude ratio (squared)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)

        // Shelf slope from Q: higher Q = steeper transition
        // beta = sqrt(A*A + 1) / q gives resonant shelf behaviour
        let beta = sqrt(A * A + 1.0) / q

        let b0 = A * ((A + 1.0) + (A - 1.0) * cosOmega + beta * sinOmega)
        let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosOmega)
        let b2 = A * ((A + 1.0) + (A - 1.0) * cosOmega - beta * sinOmega)
        let a0 = (A + 1.0) - (A - 1.0) * cosOmega + beta * sinOmega
        let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosOmega)
        let a2 = (A + 1.0) - (A - 1.0) * cosOmega - beta * sinOmega

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - Band Pass

    /// Band pass filter (constant 0 dB peak gain).
    ///
    /// Passes frequencies within a band, attenuates outside.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Centre frequency in Hz
    ///   - bandwidth: Bandwidth in octaves
    static func bandPass(
        sampleRate: Double,
        frequency: Double,
        bandwidth: Double
    ) -> BiquadCoefficients {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega * sinh(log(2.0) / 2.0 * bandwidth * omega / sinOmega)

        let b0 = alpha
        let b1 = 0.0
        let b2 = -alpha
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - Notch

    /// Notch (band-reject) filter.
    ///
    /// Attenuates frequencies within a narrow band, passes everything else.
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz
    ///   - frequency: Centre frequency in Hz
    ///   - bandwidth: Bandwidth in octaves
    static func notch(
        sampleRate: Double,
        frequency: Double,
        bandwidth: Double
    ) -> BiquadCoefficients {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega * sinh(log(2.0) / 2.0 * bandwidth * omega / sinOmega)

        let b0 = 1.0
        let b1 = -2.0 * cosOmega
        let b2 = 1.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha

        return normalise(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    // MARK: - Helper Functions

    /// Converts bandwidth in octaves to Q factor.
    ///
    /// For a peaking filter with bandwidth in octaves, Q is:
    ///   Q = 1 / (2 * sinh(ln(2)/2 * BW))
    static func bandwidthToQ(_ bandwidth: Double) -> Double {
        // Standard Butterworth Q for 2nd-order filter
        // This is a simplification — actual Q from bandwidth uses:
        // Q = 1 / (2 * sinh(ln(2)/2 * bandwidth))
        // For bandwidth = 0.67 (typical musical Q), Q ≈ 2.15
        // For bandwidth = 1.0 (1 octave), Q ≈ 1.41
        // For bandwidth = 2/3 (2/3 octave), Q ≈ 2.15
        return 1.0 / (2.0 * sinh(log(2.0) / 2.0 * bandwidth))
    }

    /// Normalises biquad coefficients by dividing by a0.
    ///
    /// This produces the standard form where the denominator is
    /// (1 + a1*z^-1 + a2*z^-2) rather than (a0 + a1*z^-1 + a2*z^-2).
    static func normalise(
        b0: Double,
        b1: Double,
        b2: Double,
        a0: Double,
        a1: Double,
        a2: Double
    ) -> BiquadCoefficients {
        let invA0 = 1.0 / a0
        return BiquadCoefficients(
            b0: b0 * invA0,
            b1: b1 * invA0,
            b2: b2 * invA0,
            a1: a1 * invA0,
            a2: a2 * invA0
        )
    }
}

