import Atomics
import Foundation

/// Chain of biquad filters for one audio channel.
///
/// Pre-allocates `maxBandCount` filters. Unused bands are passthrough.
/// NOT Sendable — owned exclusively by `RenderCallbackContext` (audio thread).
///
/// Uses double-buffered coefficients for lock-free updates from the main thread:
/// - `pendingCoefficients` is written by the main thread
/// - `activeCoefficients` is read by the audio thread
/// - `hasPendingUpdate` is an atomic flag that signals when updates are available
///
/// Only filters whose coefficients actually changed are rebuilt in `applyPendingUpdates()`.
/// A single-band slider drag rebuilds exactly 1 filter; a full preset load rebuilds all of them.
final class EQChain {
    // MARK: - Constants

    /// Maximum number of bands per layer (from EQConfiguration).
    static let maxBandCount = EQConfiguration.maxBandCount

    // MARK: - Properties

    /// Pre-allocated biquad filters (one per band).
    private let filters: [BiquadFilter]

    /// Number of active bands in this chain.
    private var activeBandCount: Int = 0

    /// Per-band bypass flags (active bands only).
    private var bypassFlags: [Bool]

    /// Layer-level bypass (all bands bypassed).
    private var layerBypass: Bool = false

    // MARK: - Double-Buffered Coefficients

    /// Coefficients currently in use by the audio thread.
    private var activeCoefficients: [BiquadCoefficients]

    /// Coefficients staged for next update (written by main thread).
    private var pendingCoefficients: [BiquadCoefficients]

    /// Staged active band count (written by main thread).
    private var pendingActiveBandCount: Int = 0

    /// Staged bypass flags (written by main thread).
    private var pendingBypassFlags: [Bool]

    /// Staged layer bypass (written by main thread).
    private var pendingLayerBypass: Bool = false

    /// Atomic flag indicating pending coefficient updates.
    private let hasPendingUpdate = ManagedAtomic<Bool>(false)

    /// Whether the next `applyPendingUpdates()` should reset filter delay state.
    /// Set to `true` by `stageFullUpdate()` (preset load, sample rate change).
    /// Left `false` by `stageBandUpdate()` (incremental slider drag).
    /// Read and cleared on the audio thread inside `applyPendingUpdates()`.
    private var pendingFullReset: Bool = false

    // MARK: - Initialization

    /// Creates a new EQ chain with pre-allocated resources.
    /// - Parameter maxFrameCount: Maximum frames per render call (unused, kept for API compatibility).
    init(maxFrameCount: UInt32) {
        // Pre-allocate filters (always maxBandCount)
        filters = (0..<Self.maxBandCount).map { _ in BiquadFilter() }

        // Pre-allocate coefficient arrays
        activeCoefficients = [BiquadCoefficients](repeating: .identity, count: Self.maxBandCount)
        pendingCoefficients = [BiquadCoefficients](repeating: .identity, count: Self.maxBandCount)

        // Pre-allocate bypass flags
        bypassFlags = [Bool](repeating: false, count: Self.maxBandCount)
        pendingBypassFlags = [Bool](repeating: false, count: Self.maxBandCount)
    }

    deinit {
        // No resources to deallocate - filters are value types with managed setups
    }

    // MARK: - Main Thread API

    /// Stages new coefficients for a single band (called from main thread).
    ///
    /// This is the incremental update path — used for slider drags and single-parameter changes.
    /// It does NOT set `pendingFullReset`, so `applyPendingUpdates()` will preserve filter delay
    /// state on all unchanged bands, preventing audible clicks.
    /// - Parameters:
    ///   - index: Band index within this chain.
    ///   - coefficients: New biquad coefficients.
    ///   - bypass: Whether this band is bypassed.
    func stageBandUpdate(index: Int, coefficients: BiquadCoefficients, bypass: Bool) {
        guard index >= 0 && index < Self.maxBandCount else { return }
        pendingCoefficients[index] = coefficients
        pendingBypassFlags[index] = bypass
        hasPendingUpdate.store(true, ordering: .releasing)
    }

    /// Stages a full configuration update (called from main thread).
    ///
    /// Used for preset load, band count change, or sample rate change. Sets `pendingFullReset`
    /// so that `applyPendingUpdates()` resets all filter delay state — producing a clean start.
    /// - Parameters:
    ///   - coefficients: All band coefficients.
    ///   - bypassFlags: Per-band bypass flags.
    ///   - activeBandCount: Number of active bands.
    ///   - layerBypass: Whether the entire layer is bypassed.
    func stageFullUpdate(
        coefficients: [BiquadCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int,
        layerBypass: Bool
    ) {
        // Copy coefficients (pad with identity if needed)
        for i in 0..<Self.maxBandCount {
            pendingCoefficients[i] = i < coefficients.count ? coefficients[i] : .identity
            pendingBypassFlags[i] = i < bypassFlags.count ? bypassFlags[i] : false
        }
        pendingActiveBandCount = min(activeBandCount, Self.maxBandCount)
        pendingLayerBypass = layerBypass
        // Full update resets delay state to give the new configuration a clean start
        pendingFullReset = true
        hasPendingUpdate.store(true, ordering: .releasing)
    }

    /// Sets the layer bypass state (called from main thread).
    ///
    /// Note: This is a standalone toggle for bypass state. When toggling bypass off,
    /// you should ensure `stageFullUpdate()` has been called previously (or will be called)
    /// to set the active band count correctly. If only bypass is toggled without prior
    /// full staging, `pendingActiveBandCount` remains at its initialised value (0).
    /// - Parameter bypass: Whether the entire layer is bypassed.
    func stageLayerBypass(_ bypass: Bool) {
        pendingLayerBypass = bypass
        hasPendingUpdate.store(true, ordering: .releasing)
    }

    // MARK: - Audio Thread API

    /// Applies any pending coefficient updates.
    /// Call once per render cycle before processing.
    ///
    /// Only rebuilds vDSP setups for bands whose coefficients actually changed.
    /// - For incremental updates (`stageBandUpdate`): rebuilds exactly the 1 changed filter,
    ///   preserving delay state (no clicks). The other 63 filters are not touched.
    /// - For full updates (`stageFullUpdate`): rebuilds all filters and resets delay state
    ///   (clean start for preset loads and sample rate changes).
    @inline(__always)
    func applyPendingUpdates() {
        guard hasPendingUpdate.exchange(false, ordering: .acquiringAndReleasing) else { return }

        // Capture and clear the full-reset flag
        let fullReset = pendingFullReset
        pendingFullReset = false

        // Update active band count and layer bypass
        activeBandCount = pendingActiveBandCount
        layerBypass = pendingLayerBypass

        // Update each band — only rebuild filters whose coefficients changed.
        // For a single-band slider drag, this loop touches exactly 1 filter out of 64.
        for i in 0..<Self.maxBandCount {
            bypassFlags[i] = pendingBypassFlags[i]

            let pending = pendingCoefficients[i]
            if pending != activeCoefficients[i] {
                // Coefficients changed: rebuild this filter's vDSP setup.
                // Use resetState only on full updates (preset loads) to avoid mid-stream clicks.
                activeCoefficients[i] = pending
                filters[i].setCoefficients(pending, resetState: fullReset)
            } else if fullReset {
                // Coefficients unchanged but a full reset was requested (e.g. the band was
                // already at identity before a preset load). Reset delay state so that any
                // residual ringing from a previous preset is cleared.
                filters[i].setCoefficients(pending, resetState: true)
            }
            // Otherwise: no coefficient change, no full reset — skip entirely.
        }
    }

    /// Processes audio through all active bands in this chain.
    /// Input and output may alias (in-place processing supported).
    /// - Parameters:
    ///   - buffer: Audio buffer to process (modified in place).
    ///   - frameCount: Number of frames to process.
    @inline(__always)
    func process(buffer: UnsafeMutablePointer<Float>, frameCount: UInt32) {
        // Layer bypass: skip all processing
        if layerBypass {
            return
        }

        // No active bands: passthrough
        if activeBandCount == 0 {
            return
        }

        // Process each active band in-place
        // BiquadFilter supports in-place processing (input == output)
        for i in 0..<activeBandCount {
            // Skip bypassed bands
            if bypassFlags[i] {
                continue
            }

            // Process through this band's biquad filter in-place
            filters[i].process(
                input: buffer,
                output: buffer,
                frameCount: frameCount
            )
        }
    }
}
