import Accelerate

/// Single biquad filter section using vDSP.
///
/// Owns a `vDSP_biquad_Setup` and pre-allocated delay elements.
/// NOT Sendable — must be owned exclusively by one thread (the audio thread via EQChain).
///
/// This class processes audio through a single second-order IIR filter section.
/// The transfer function is:
///
///   H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
///
/// Where coefficients are normalised (a0 has been divided out).
final class BiquadFilter {
    // MARK: - Properties

    /// The vDSP setup object for biquad processing.
    /// Created on init, recreated on coefficient change.
    private var setup: vDSP_biquad_Setup?

    /// Delay elements for the filter state (2 * (sections + 1) = 4 for single section).
    /// Pre-allocated to avoid runtime allocation.
    private var delay: [Float]

    /// Current coefficients stored as [b0, b1, b2, a1, a2] in Float for vDSP.
    private var coefficients: [Float]

    /// Whether the setup is valid (coefficients have been set).
    private var isValid: Bool = false

    // MARK: - Initialization

    init() {
        // Pre-allocate delay elements: 2 * (sections + 1) = 4 for a single biquad section
        // vDSP requires this exact size
        delay = [Float](repeating: 0, count: 4)

        // Pre-allocate coefficient storage: 5 coefficients (b0, b1, b2, a1, a2)
        coefficients = [Float](repeating: 0, count: 5)

        // Start with identity (passthrough), resetting delay state on init
        setCoefficients(BiquadCoefficients.identity, resetState: true)
    }

    deinit {
        if let s = setup {
            vDSP_biquad_DestroySetup(s)
        }
    }

    // MARK: - Coefficient Update

    /// Updates the filter with new coefficients.
    /// Must be called from the audio thread or during setup (not from main thread during audio).
    /// - Parameters:
    ///   - newCoefficients: The new biquad coefficients.
    ///   - resetState: Whether to zero the delay elements (filter state).
    ///     Pass `true` for preset loads and initialisation — produces a clean start at the cost
    ///     of a brief transient if audio is playing.
    ///     Pass `false` for incremental changes (slider drags) — preserves continuity and
    ///     avoids the audible click caused by resetting filter state mid-stream.
    func setCoefficients(_ newCoefficients: BiquadCoefficients, resetState: Bool) {
        // Store coefficients as Float for vDSP (for use in process)
        coefficients[0] = Float(newCoefficients.b0)
        coefficients[1] = Float(newCoefficients.b1)
        coefficients[2] = Float(newCoefficients.b2)
        coefficients[3] = Float(newCoefficients.a1)
        coefficients[4] = Float(newCoefficients.a2)

        // Destroy old setup if exists
        if let s = setup {
            vDSP_biquad_DestroySetup(s)
        }

        // Create new setup with the coefficients
        // vDSP_biquad_CreateSetup takes Double coefficients but creates a Float processing setup
        var coeffsD: [Double] = [
            newCoefficients.b0,
            newCoefficients.b1,
            newCoefficients.b2,
            newCoefficients.a1,
            newCoefficients.a2
        ]
        setup = vDSP_biquad_CreateSetup(&coeffsD, 1)

        // Only reset delay elements when explicitly requested.
        // For incremental coefficient changes (slider drags), preserving delay state
        // avoids a discontinuity that produces an audible click.
        if resetState {
            for i in 0..<4 { delay[i] = 0 }
        }

        isValid = true
    }

    // MARK: - Audio Processing

    /// Processes audio through this biquad filter.
    /// Input and output may alias (in-place processing supported).
    /// - Parameters:
    ///   - input: Pointer to input samples.
    ///   - output: Pointer to output samples (may be same as input).
    ///   - frameCount: Number of frames to process.
    @inline(__always)
    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: UInt32
    ) {
        guard isValid, let s = setup else {
            // If not set up, copy input to output (passthrough)
            if input != output {
                memcpy(output, input, Int(frameCount) * MemoryLayout<Float>.size)
            }
            return
        }

        // Process through vDSP biquad
        vDSP_biquad(s, &delay, input, 1, output, 1, vDSP_Length(frameCount))
    }
}
