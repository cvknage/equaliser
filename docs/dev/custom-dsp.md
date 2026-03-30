# L/R Channel EQ Implementation Plan (Custom DSP)

## Context

Implementing completely independent EQ for left and right audio channels:

- Different band configurations per channel (frequencies, bandwidths, filter types, counts)
- Custom biquad DSP implementation replacing `AVAudioUnitEQ`
- All currently supported filter types must be implemented (11 types)
- L and R processed in the same output render callback (deterministic, no drift)
- Architecture supports stacking multiple EQ layers in future (e.g. headphone correction + genre + user EQ)

## Why Custom DSP

Apple's `AVAudioUnitEQ` applies the **same filter configuration to all channels** — only per-band gains can differ. For completely independent L/R setups (different frequencies, Q values, filter types, band counts), we need custom biquad filters.

## Key Architectural Decision: Remove AVAudioEngine

The **only** reason `AVAudioEngine` exists in this codebase is to host `AVAudioUnitEQ` nodes. Once we replace those with custom biquads, the engine adds nothing except complexity and an extra buffer copy per render cycle.

**Current signal flow (output callback):**

```
Ring Buffer → outputReadBuffers
  → AudioRenderContext.setInputBuffers()
  → engine.manualRenderingBlock()
    → SourceNode copies inputBuffers into engine graph
    → AVAudioUnitEQ processes
    → outputNode produces result
  → output gain applied to ioData
  → written to output HAL
```

**New signal flow (output callback):**

```
Ring Buffer → outputReadBuffers
  → EQ layer 0 (user EQ) processes L and R in-place
  → [future: EQ layer 1 (headphone correction) processes L and R in-place]
  → [future: EQ layer 2 ...]
  → copy to ioData
  → output gain applied to ioData
  → written to output HAL
```

**What this removes:**

| File | Lines | Reason |
|------|-------|--------|
| `ManualRenderingEngine.swift` | 286 | No longer needed — hosted AVAudioEngine |
| `AudioRenderContext.swift` | 104 | No longer needed — was bridge to engine |

**What this simplifies:**

- One fewer buffer copy per render cycle (source node copy eliminated)
- No AVAudioEngine lifecycle management (create, start, stop, manual rendering mode)
- No EQ unit capacity management (32-band units, chaining multiple units)
- Biquad processing happens directly in `RenderCallbackContext`, matching the existing pattern for gains and meters

---

## Architecture

```
[Driver/HAL Input] → [Ring Buffer] → outputReadBuffers (deinterleaved)
                                          |
        +---------------------------------+---------------------------------+
        |                                                                   |
   outputReadBuffers[0] (L)                                   outputReadBuffers[1] (R)
        |                                                                   |
   [EQ Layer 0 — User EQ]                                    [EQ Layer 0 — User EQ]
   Chain L: bands[0..N]                                       Chain R: bands[0..M]
        |                                                                   |
   [EQ Layer 1 — reserved]                                    [EQ Layer 1 — reserved]
   (passthrough until enabled)                                (passthrough until enabled)
        |                                                                   |
   [EQ Layer 2 — reserved]                                    [EQ Layer 2 — reserved]
   (passthrough until enabled)                                (passthrough until enabled)
        |                                                                   |
        +--→ ioData channel 0 (L)                  ioData channel 1 (R) ←---+
                                          |
                                   [Output Gain]
                                          |
                                   [Output HAL]
```

Multiple EQ layers are processed in series per channel. Each layer is an independent `EQChain` with its own bands, coefficients, and bypass state. Unused layers have 0 active bands and cost nothing at runtime (the processing loop skips them).

**Current implementation uses 1 layer (User EQ).** The architecture pre-allocates capacity for `maxLayerCount` (4) layers per channel so that headphone correction, genre presets, or other stacked EQs can be added later without pipeline restarts or format migrations.

Each channel has completely independent (per layer):

- Number of active bands (up to 64 per layer)
- Filter frequencies
- Bandwidths (Q values)
- Filter types (all 11 supported types)
- Per-band gains
- Per-band bypass
- Per-layer bypass

---

## Filter Types

The app supports 7 filter types. All filter types use Q as a user-controlled parameter (industry standard approach).

| FilterType | RBJ Cookbook Formula | Notes |
|------------|---------------------|-------|
| `.parametric` | peakingEQ | Standard bell/peaking |
| `.lowPass` | LPF | Q controls resonance at cutoff |
| `.highPass` | HPF | Q controls resonance at cutoff |
| `.lowShelf` | lowShelf | Q controls shelf slope |
| `.highShelf` | highShelf | Q controls shelf slope |
| `.bandPass` | BPF (constant 0 dB peak) | Bandwidth-controlled |
| `.notch` | notch | Band reject |

Q = 0.707 (1/√2) produces Butterworth response (maximally flat). Higher Q values create resonance peaks at the cutoff frequency for LPF/HPF, or steeper shelf transitions for shelf filters.

---

## Real-Time Safety

All DSP operations must be real-time safe. No allocations, no locks, no blocking on the audio thread.

| Operation | Real-Time Safe? | Where | Implementation |
|-----------|-----------------|-------|----------------|
| Process audio through biquads | ✅ Yes | Audio thread | Pre-allocated buffers, `vDSP_biquad` |
| Read active coefficients | ✅ Yes | Audio thread | Bounded copy from pending slot |
| Check for pending updates | ✅ Yes | Audio thread | `ManagedAtomic<Bool>` load |
| Calculate new coefficients | ❌ No | Main thread | Pure maths in `BiquadMath` |
| Write pending coefficients | ❌ No | Main thread | Writes to pending slot, sets flag |
| Allocate filter state | ❌ No | Init only | `vDSP_biquad_CreateSetup` |
| Deallocate filter state | ❌ No | Deinit only | `vDSP_biquad_DestroySetup` |

### Coefficient Update Pattern (Lock-Free)

Follows the existing `RenderCallbackContext` pattern where `ManagedAtomic<Int32>` is used for gain values. Extended here for coefficient arrays using double-buffering:

```swift
// Double-buffered coefficient storage (pre-allocated, fixed size)
private var activeCoefficients: [BiquadCoefficients]   // audio thread reads
private var pendingCoefficients: [BiquadCoefficients]   // main thread writes
private let hasPendingUpdate = ManagedAtomic<Bool>(false)

// Main thread: calculate and stage new coefficients
func updateBand(index: Int, config: EQBandConfiguration, sampleRate: Double) {
    pendingCoefficients[index] = BiquadMath.calculateCoefficients(
        type: config.filterType,
        sampleRate: sampleRate,
        frequency: Double(config.frequency),
        bandwidth: Double(config.bandwidth),
        gain: Double(config.gain)
    )
    hasPendingUpdate.store(true, ordering: .release)
}

// Audio thread: apply pending coefficients (bounded copy, no allocation)
@inline(__always)
func applyPendingCoefficients() {
    if hasPendingUpdate.exchange(false, ordering: .acquire) {
        // Fixed-size array copy — bounded, deterministic time
        for i in 0..<maxBandCount {
            activeCoefficients[i] = pendingCoefficients[i]
        }
        // Rebuild vDSP setups with new coefficients
        rebuildSetups()
    }
}
```

**Why this is safe:**
- `ManagedAtomic<Bool>` with acquire/release ordering ensures the coefficient writes are visible
- The copy is bounded (64 bands × 5 doubles = 2.5 KB) and takes constant time
- No heap allocation — arrays are pre-allocated at init
- Matches the existing pattern in `RenderCallbackContext` for atomic gain updates

### vDSP Precision Choice

Coefficients are calculated in **Double** precision for numerical stability (narrow filters at low frequencies need this). Processing uses **single-precision** `vDSP_biquad` to match the existing `Float` buffer format throughout the pipeline. Coefficients are converted from Double to Float when building the `vDSP_biquad_Setup`.

---

## Implementation Phases

### Phase 1: Domain Model — FilterType and BiquadMath

Pure types with zero dependencies. Can be unit tested immediately.

**File:** `src/domain/eq/FilterType.swift` (NEW)

```swift
/// Custom filter type enum replacing AVAudioUnitEQFilterType.
/// Lives in domain layer — no framework dependencies.
enum FilterType: Int, Codable, Sendable, CaseIterable {
    case parametric = 0   // Peaking EQ (bell)
    case lowPass = 1      // 2nd-order low pass (Q controls resonance)
    case highPass = 2     // 2nd-order high pass (Q controls resonance)
    case lowShelf = 3     // Low shelf (Q controls slope)
    case highShelf = 4    // High shelf (Q controls slope)
    case bandPass = 5     // Band pass (constant 0 dB peak)
    case notch = 6        // Band stop / notch
}
```

**File:** `src/domain/eq/BiquadCoefficients.swift` (NEW)

```swift
/// Normalised biquad coefficients (a0 divided out).
/// Value type — safe to copy between threads.
struct BiquadCoefficients: Sendable {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double  // Already normalised (divided by a0)
    let a2: Double  // Already normalised (divided by a0)

    /// Identity (passthrough) coefficients.
    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
}
```

**File:** `src/domain/eq/BiquadMath.swift` (NEW)

```swift
/// Pure coefficient calculation using RBJ Audio EQ Cookbook.
/// All functions are pure — no state, no side effects, no allocations.
/// Calculations in Double precision for numerical stability.
enum BiquadMath {
    /// Calculates biquad coefficients for the given filter parameters.
    static func calculateCoefficients(
        type: FilterType,
        sampleRate: Double,
        frequency: Double,
        q: Double,           // Q factor for all filter types
        gain: Double         // dB (only used by parametric and shelf types)
    ) -> BiquadCoefficients

    // Internal helpers per filter type:
    // - parametric: peakingEQ from RBJ cookbook
    // - lowPass/highPass: 2nd-order with Q controlling resonance
    // - lowShelf/highShelf: shelf formulas with Q controlling slope
    // - bandPass: BPF (constant 0 dB peak gain)
    // - notch: band-reject
}
```

**Sources for formulas:**
- [Audio EQ Cookbook](https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt)
- [EarLevel Engineering](https://www.earlevel.com/main/2011/01/02/biquad-formulas/)

**Tests:** `tests/domain/eq/BiquadMathTests.swift`
- Known reference values for each filter type (compare against scipy or MATLAB output)
- Edge cases: Nyquist frequency, very narrow bandwidth (0.1 oct), very wide (8 oct)
- Identity: bypass band returns passthrough coefficients

---

### Phase 2: Domain Model — ChannelMode, EQLayerState, ChannelEQState

**File:** `src/domain/eq/ChannelMode.swift` (NEW)

```swift
/// How audio is processed — determines whether one or two EQ chains are active.
enum ChannelMode: String, Codable, Sendable, CaseIterable {
    case linked   // One configuration applied to both L and R
    case stereo   // Independent L and R configurations
}
```

Note: which channel the user is *editing* in the UI (L vs R focus) is UI state only, not a domain concept. That lives in the view layer as a `ChannelFocus` enum.

**File:** `src/domain/eq/EQLayerState.swift` (NEW)

```swift
/// State for a single EQ layer (e.g. user EQ, headphone correction, genre).
/// Pure value type. Each layer has its own band configuration and bypass.
struct EQLayerState: Codable, Sendable {
    /// Human-readable label for this layer (e.g. "User EQ", "Headphone Correction").
    var label: String

    /// Band configurations for this layer.
    var bands: [EQBandConfiguration]

    /// Number of active bands in this layer (may be less than bands.count).
    var activeBandCount: Int

    /// Whether this entire layer is bypassed.
    var bypass: Bool

    static func userEQ(bandCount: Int = EQConfiguration.defaultBandCount) -> EQLayerState {
        EQLayerState(
            label: "User EQ",
            bands: EQConfiguration.defaultBands(),
            activeBandCount: bandCount,
            bypass: false
        )
    }
}
```

**File:** `src/domain/eq/ChannelEQState.swift` (NEW)

```swift
/// Per-channel EQ state containing one or more layers.
/// Pure value type.
struct ChannelEQState: Codable, Sendable {
    /// Ordered list of EQ layers. Processed in series (index 0 first).
    /// Currently contains exactly one layer (User EQ).
    /// Future: headphone correction, genre presets, etc.
    var layers: [EQLayerState]

    /// Convenience: the primary user EQ layer (always index 0).
    var userEQ: EQLayerState {
        get { layers[0] }
        set { layers[0] = newValue }
    }

    static func `default`(bandCount: Int = EQConfiguration.defaultBandCount) -> ChannelEQState {
        ChannelEQState(layers: [.userEQ(bandCount: bandCount)])
    }
}
```

This extracts the per-channel data that currently lives monolithically in `EQConfiguration`. The layer array allows stacking multiple EQs in future (headphone correction, genre presets) without restructuring the data model or migrating the preset format — new layers are simply appended to the array.

The existing `EQBandConfiguration` struct is reused as-is but its `filterType` property changes from `AVAudioUnitEQFilterType` to `FilterType` (Phase 6).

**File:** `src/domain/eq/EQLayerConstants.swift` (NEW)

```swift
/// Constants for the EQ layer system.
enum EQLayerConstants {
    /// Maximum number of EQ layers per channel.
    /// Pre-allocated at pipeline init. Unused layers are passthrough (zero CPU cost).
    static let maxLayerCount = 4

    /// Well-known layer indices.
    static let userEQLayerIndex = 0
    // Future: static let headphoneCorrectionLayerIndex = 1
    // Future: static let genreLayerIndex = 2
}
```

---

### Phase 3: Biquad DSP Implementation

Service-layer types that own vDSP state. These live inside `RenderCallbackContext` (not independently `@unchecked Sendable`).

Each `EQChain` represents **one layer on one channel**. `RenderCallbackContext` owns `maxLayerCount` chains per channel (see Phase 4). Layers are processed in series — the output of layer 0 feeds into layer 1, etc. Unused layers have 0 active bands and their `process()` is a no-op.

**File:** `src/services/audio/dsp/BiquadFilter.swift` (NEW)

```swift
/// Single biquad filter section using vDSP.
/// Owns a vDSP_biquad_Setup and pre-allocated delay elements.
/// NOT Sendable — owned exclusively by RenderCallbackContext.
final class BiquadFilter {
    private var setup: vDSP_biquad_Setup?   // Single-precision processing
    private var delay: [Float]               // 2 * (sections + 1) delay elements
    private var currentCoefficients: BiquadCoefficients

    init() {
        // Allocate with identity (passthrough) coefficients
        currentCoefficients = .identity
        delay = [Float](repeating: 0, count: 4 + 2)  // vDSP needs sections*2+2
        setup = vDSP_biquad_CreateSetup(/* identity coeffs */, 1)
    }

    deinit {
        if let s = setup { vDSP_biquad_DestroySetupD(s) }
    }

    /// Rebuilds the vDSP setup with new coefficients.
    /// Called from audio thread ONLY during applyPendingCoefficients().
    func updateSetup(coefficients: BiquadCoefficients) {
        if let s = setup { vDSP_biquad_DestroySetup(s) }
        // Convert Double coefficients to Float for vDSP
        let b0 = Float(coefficients.b0)
        // ... etc
        setup = vDSP_biquad_CreateSetup(/* new coeffs */, 1)
        delay = [Float](repeating: 0, count: 4 + 2)
        currentCoefficients = coefficients
    }

    /// Process audio (real-time safe — vDSP_biquad only).
    @inline(__always)
    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: UInt
    ) {
        guard let s = setup else { return }
        vDSP_biquad(s, &delay, input, 1, output, 1, frameCount)
    }
}
```

**File:** `src/services/audio/dsp/EQChain.swift` (NEW)

```swift
/// Chain of biquad filters for one audio channel.
/// Pre-allocates maxBandCount filters. Unused bands are passthrough.
/// NOT Sendable — owned exclusively by RenderCallbackContext.
final class EQChain {
    static let maxBandCount = EQConfiguration.maxBandCount  // 64

    private let filters: [BiquadFilter]  // Always maxBandCount, pre-allocated
    private var activeBandCount: Int = 0
    private var bypassFlags: [Bool]       // Per-band bypass (pre-allocated)

    // Double-buffered coefficients for lock-free updates
    private var activeCoefficients: [BiquadCoefficients]
    private var pendingCoefficients: [BiquadCoefficients]
    private var pendingActiveBandCount: Int = 0
    private var pendingBypassFlags: [Bool]
    private let hasPendingUpdate = ManagedAtomic<Bool>(false)

    // Scratch buffer for intermediate processing (pre-allocated)
    private let scratchBuffer: UnsafeMutablePointer<Float>
    private let scratchCapacity: Int

    init(maxFrameCount: UInt32) {
        // Pre-allocate everything at init — nothing allocated at runtime
        filters = (0..<Self.maxBandCount).map { _ in BiquadFilter() }
        activeCoefficients = [BiquadCoefficients](repeating: .identity, count: Self.maxBandCount)
        pendingCoefficients = [BiquadCoefficients](repeating: .identity, count: Self.maxBandCount)
        bypassFlags = [Bool](repeating: false, count: Self.maxBandCount)
        pendingBypassFlags = [Bool](repeating: false, count: Self.maxBandCount)
        scratchCapacity = Int(maxFrameCount)
        scratchBuffer = .allocate(capacity: scratchCapacity)
        scratchBuffer.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        scratchBuffer.deinitialize(count: scratchCapacity)
        scratchBuffer.deallocate()
    }

    // MARK: - Main Thread API

    /// Stages new coefficients for a single band.
    func stageBandUpdate(index: Int, coefficients: BiquadCoefficients, bypass: Bool) {
        pendingCoefficients[index] = coefficients
        pendingBypassFlags[index] = bypass
        hasPendingUpdate.store(true, ordering: .release)
    }

    /// Stages a full configuration update (e.g. preset load, band count change).
    func stageFullUpdate(
        coefficients: [BiquadCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int
    ) {
        for i in 0..<Self.maxBandCount {
            pendingCoefficients[i] = i < coefficients.count ? coefficients[i] : .identity
            pendingBypassFlags[i] = i < bypassFlags.count ? bypassFlags[i] : false
        }
        pendingActiveBandCount = activeBandCount
        hasPendingUpdate.store(true, ordering: .release)
    }

    // MARK: - Audio Thread API

    /// Applies any pending coefficient updates. Call once per render cycle.
    @inline(__always)
    func applyPendingUpdates() {
        guard hasPendingUpdate.exchange(false, ordering: .acquire) else { return }
        activeBandCount = pendingActiveBandCount
        for i in 0..<Self.maxBandCount {
            activeCoefficients[i] = pendingCoefficients[i]
            bypassFlags[i] = pendingBypassFlags[i]
            filters[i].updateSetup(coefficients: activeCoefficients[i])
        }
    }

    /// Processes audio through active bands in series.
    /// Input and output may alias (in-place processing supported).
    @inline(__always)
    func process(
        buffer: UnsafeMutablePointer<Float>,
        frameCount: UInt32
    ) {
        let count = UInt(frameCount)
        for i in 0..<activeBandCount {
            guard !bypassFlags[i] else { continue }
            // Ping-pong between buffer and scratch to avoid extra copies
            filters[i].process(input: buffer, output: scratchBuffer, frameCount: count)
            memcpy(buffer, scratchBuffer, Int(frameCount) * MemoryLayout<Float>.size)
        }
    }
}
```

**Tests:** `tests/services/audio/dsp/BiquadFilterTests.swift`
- Impulse response: pass a single 1.0 sample, verify output matches expected response
- Passthrough: identity coefficients produce input == output
- DC offset: low-pass at high frequency passes DC unchanged

---

### Phase 4: Integrate Biquads into RenderCallbackContext

This is the core integration. `EQChain` instances are owned by `RenderCallbackContext` (which already owns ring buffers, gain state, and meter storage). This replaces the `renderContext: AudioRenderContext?` property.

`RenderCallbackContext` owns `maxLayerCount` chains **per channel**, pre-allocated at init. Each chain corresponds to one EQ layer (user EQ, headphone correction, etc.). Currently only layer 0 (User EQ) is active. Unused layers have 0 active bands and their `process()` loop body never executes — zero CPU cost.

**File:** `src/services/audio/rendering/RenderCallbackContext.swift` (MODIFY)

Changes:

1. **Remove** `renderContext` property (was `AudioRenderContext?`)
2. **Add** arrays of `EQChain` instances (one per layer per channel):

```swift
final class RenderCallbackContext: @unchecked Sendable {
    // ... existing properties (ring buffers, gains, meters) ...

    // REMOVE:
    // let renderContext: AudioRenderContext?

    // ADD:
    /// Per-channel EQ chain arrays. Index = layer (0 = user EQ, 1+ = future layers).
    /// Pre-allocated at init. Unused layers are passthrough (0 active bands).
    let leftEQChains: [EQChain]    // length = EQLayerConstants.maxLayerCount
    let rightEQChains: [EQChain]   // length = EQLayerConstants.maxLayerCount
```

3. **Update init** to create EQ chains instead of accepting a render context:

```swift
    init(
        inputHALUnit: AudioComponentInstance?,
        channelCount: UInt32,
        maxFrameCount: UInt32,
        ringBufferCapacity: Int = AudioConstants.ringBufferCapacity
    ) {
        // ... existing ring buffer and gain setup ...
        let layerCount = EQLayerConstants.maxLayerCount
        self.leftEQChains = (0..<layerCount).map { _ in EQChain(maxFrameCount: maxFrameCount) }
        self.rightEQChains = (0..<layerCount).map { _ in EQChain(maxFrameCount: maxFrameCount) }
    }
```

4. **Add** a new method for EQ processing (called from output callback):

```swift
    /// Processes all EQ layers on the output read buffers in-place.
    /// Layers are processed in series: layer 0 output feeds into layer 1, etc.
    /// Called from the audio thread in the output callback.
    @inline(__always)
    func processEQ(frameCount: UInt32) {
        // Process L channel through all layers in series
        for chain in leftEQChains {
            chain.applyPendingUpdates()
            chain.process(buffer: outputReadBuffers[0], frameCount: frameCount)
        }

        // Process R channel through all layers in series
        if channelCount > 1 {
            for chain in rightEQChains {
                chain.applyPendingUpdates()
                chain.process(buffer: outputReadBuffers[1], frameCount: frameCount)
            }
        }
    }
```

**File:** `src/services/audio/rendering/RenderPipeline.swift` (MODIFY)

The output callback changes significantly. The core of the change:

**Current output callback (lines 739–812):**
```swift
// 2. Set input buffers on render context
renderCtx.setInputBuffers(inputBuffers, frameCount: ...)
// 3. Render through EQ chain (via AVAudioEngine)
let renderStatus = renderCtx.render(frameCount: ..., outputBuffer: ioData)
// 4. Clear input buffer reference
renderCtx.clearInputBuffer()
```

**New output callback:**
```swift
// 2. Process EQ on the read buffers in-place (no engine, no copy)
if context.processingMode == 1 {
    context.processEQ(frameCount: frameCount)
}

// 3. Copy processed buffers to output (ioData)
let abl = UnsafeMutableAudioBufferListPointer(ioData)
for (channelIndex, buffer) in abl.enumerated() {
    if let destData = buffer.mData?.assumingMemoryBound(to: Float.self),
       channelIndex < context.outputReadBufferCount {
        memcpy(destData, context.outputReadBuffer(channel: channelIndex),
               Int(frameCount) * MemoryLayout<Float>.size)
    }
}
```

This eliminates `AudioRenderContext`, `ManualRenderingEngine`, `AVAudioSourceNode`, and the entire `AVAudioEngine` lifecycle.

**File:** `src/services/audio/rendering/RenderPipeline.swift` (MODIFY continued)

Additional changes to `RenderPipeline`:

1. **Remove** `renderingEngine: ManualRenderingEngine?` property
2. **Remove** the engine creation in `start()` (lines 300–312)
3. **Remove** all `renderingEngine?.updateBand*()` forwarding methods
4. **Replace** with coefficient staging methods:

```swift
    /// Stages updated coefficients for a single band on the given channel and layer.
    /// Called from main thread. Coefficients are picked up by audio thread next render cycle.
    /// - Parameters:
    ///   - channel: Which channel(s) to target (.left, .right, .both).
    ///   - layerIndex: Which EQ layer (0 = user EQ). Default 0.
    ///   - bandIndex: Band index within the layer.
    ///   - coefficients: Pre-calculated biquad coefficients.
    ///   - bypass: Whether this band is bypassed.
    func updateBandCoefficients(
        channel: EQChannelTarget,
        layerIndex: Int = EQLayerConstants.userEQLayerIndex,
        bandIndex: Int,
        coefficients: BiquadCoefficients,
        bypass: Bool
    ) {
        guard layerIndex < EQLayerConstants.maxLayerCount else { return }
        switch channel {
        case .left:
            callbackContext?.leftEQChains[layerIndex].stageBandUpdate(
                index: bandIndex, coefficients: coefficients, bypass: bypass)
        case .right:
            callbackContext?.rightEQChains[layerIndex].stageBandUpdate(
                index: bandIndex, coefficients: coefficients, bypass: bypass)
        case .both:
            callbackContext?.leftEQChains[layerIndex].stageBandUpdate(
                index: bandIndex, coefficients: coefficients, bypass: bypass)
            callbackContext?.rightEQChains[layerIndex].stageBandUpdate(
                index: bandIndex, coefficients: coefficients, bypass: bypass)
        }
    }

    /// Stages a full configuration update for a channel and layer (preset load, band count change).
    func stageFullUpdate(
        channel: EQChannelTarget,
        layerIndex: Int = EQLayerConstants.userEQLayerIndex,
        coefficients: [BiquadCoefficients],
        bypassFlags: [Bool],
        activeBandCount: Int
    ) {
        guard layerIndex < EQLayerConstants.maxLayerCount else { return }
        // ... similar switch on channel, targeting the chain at layerIndex ...
    }
```

Where `EQChannelTarget` is:

```swift
enum EQChannelTarget {
    case left
    case right
    case both  // Used in linked mode
}
```

**Files to DELETE:**

| File | Reason |
|------|--------|
| `src/services/audio/rendering/ManualRenderingEngine.swift` | Replaced by EQChain in RenderCallbackContext |
| `src/services/audio/rendering/AudioRenderContext.swift` | Replaced by direct biquad processing |

---

### Phase 5: Update Call Chain and EQConfiguration

The band update call chain changes fundamentally. Currently updates flow through 5 layers passing only an index, with `EQConfiguration.apply*()` methods talking directly to `AVAudioUnitEQ` nodes. The new chain calculates coefficients on the main thread and stages them for the audio thread.

**Current call chain (per-band update):**

```
EqualiserStore.updateBandGain(index:gain:)           // stores value
  → eqConfiguration.updateBandGain(index:gain:)      // updates band array
  → routingCoordinator.updateBandGain(index:)         // forwards index
    → renderPipeline.updateBandGain(index:)           // forwards index
      → renderingEngine.updateBandGain(index:)        // forwards index
        → eqConfiguration.applyBandGain(index:to:)   // writes to AVAudioUnitEQ
```

**New call chain (per-band update):**

```
EqualiserStore.updateBandGain(index:gain:)             // stores value in layer 0
  → eqConfiguration.updateBandGain(index:gain:)        // updates band in userEQ layer
  → routingCoordinator.updateBandCoefficients(index:)   // calculates + stages
    → BiquadMath.calculateCoefficients(...)             // pure maths (main thread)
    → renderPipeline.updateBandCoefficients(            // stages for audio thread
        channel: .both/.left/.right,
        layerIndex: 0,                                  // user EQ layer
        bandIndex: index,
        coefficients: newCoeffs,
        bypass: band.bypass
      )
      → callbackContext.leftEQChains[0].stageBandUpdate()  // atomic flag set
```

The `layerIndex` defaults to 0 (user EQ) throughout the current implementation. When headphone correction or genre layers are added later, they use `layerIndex: 1`, `layerIndex: 2`, etc. — the staging API and audio thread processing already handle arbitrary layers.

**Key changes:**

1. Coefficient calculation happens in `AudioRoutingCoordinator` (main thread), not on the audio thread
2. `AudioRoutingCoordinator` needs access to `EQConfiguration` and current sample rate to calculate coefficients
3. The `apply*(to: [AVAudioUnitEQ])` methods on `EQConfiguration` are removed entirely
4. Channel targeting (`left`/`right`/`both`) is determined by `EQConfiguration.channelMode`
5. Layer targeting (`layerIndex`) is passed through the chain — defaults to 0 for user EQ

**File:** `src/domain/eq/EQConfiguration.swift` (MODIFY)

```swift
@MainActor
final class EQConfiguration: ObservableObject {
    // MARK: - Existing (unchanged)
    nonisolated static let maxBandCount: Int = 64
    nonisolated static let defaultBandCount: Int = 10
    nonisolated static let defaultBandwidth: Float = 0.67

    @Published var globalBypass: Bool = false
    @Published var inputGain: Float = 0
    @Published var outputGain: Float = 0

    // MARK: - New: Channel Mode
    @Published var channelMode: ChannelMode = .linked

    // MARK: - New: Per-Channel State
    @Published var linkedState: ChannelEQState
    @Published var leftState: ChannelEQState
    @Published var rightState: ChannelEQState

    // MARK: - Removed
    // @Published private(set) var activeBandCount: Int       — now per-channel
    // @Published private(set) var bands: [EQBandConfiguration] — now per-channel
    // func apply(to eqUnits: [AVAudioUnitEQ])                 — removed
    // func applyBand*(index:to:)                               — removed

    // MARK: - Convenience (User EQ layer)
    // These convenience properties access the user EQ layer (layer 0) for backward
    // compatibility with existing UI and store code. Future layers will have their
    // own dedicated access paths.

    /// Returns the active band count for the user EQ layer in the current mode.
    var activeBandCount: Int {
        switch channelMode {
        case .linked: return linkedState.userEQ.activeBandCount
        case .stereo: return max(leftState.userEQ.activeBandCount, rightState.userEQ.activeBandCount)
        }
    }

    /// Returns the bands for the user EQ layer in the current mode.
    /// UI uses this plus channelFocus to decide what to display.
    var bands: [EQBandConfiguration] {
        switch channelMode {
        case .linked: return linkedState.userEQ.bands
        case .stereo: return leftState.userEQ.bands  // UI overrides with channelFocus
        }
    }

    // MARK: - Band Updates
    // These update the appropriate channel state based on channelMode.
    // The caller (EqualiserStore) still calls routingCoordinator to stage coefficients.
    func updateBandGain(index: Int, gain: Float) { ... }
    func updateBandBandwidth(index: Int, bandwidth: Float) { ... }
    func updateBandFrequency(index: Int, frequency: Float) { ... }
    func updateBandFilterType(index: Int, filterType: FilterType) { ... }
    func updateBandBypass(index: Int, bypass: Bool) { ... }
}
```

**File:** `src/store/coordinators/AudioRoutingCoordinator.swift` (MODIFY)

Add a stored sample rate and coefficient calculation:

```swift
@MainActor
final class AudioRoutingCoordinator {
    // ... existing properties ...
    private var currentSampleRate: Double = 48000  // Updated when pipeline starts

    /// Calculates coefficients and stages them for the audio thread (user EQ layer).
    func updateBandCoefficients(index: Int) {
        guard let config = eqConfiguration else { return }
        let band = config.bands[index]  // Gets band from active channel's user EQ layer
        let coefficients = BiquadMath.calculateCoefficients(
            type: band.filterType,
            sampleRate: currentSampleRate,
            frequency: Double(band.frequency),
            bandwidth: Double(band.bandwidth),
            gain: Double(band.gain)
        )
        let target: EQChannelTarget = config.channelMode == .linked ? .both : .left // or .right based on channelFocus
        renderPipeline?.updateBandCoefficients(
            channel: target,
            layerIndex: EQLayerConstants.userEQLayerIndex,
            bandIndex: index,
            coefficients: coefficients,
            bypass: band.bypass
        )
    }

    /// Recalculates ALL coefficients for all layers (preset load, sample rate change, band count change).
    func reapplyAllCoefficients() {
        guard let config = eqConfiguration else { return }
        // For each channel state (linked, or left+right):
        //   For each layer in channelState.layers:
        //     Calculate coefficients for all active bands
        //     Stage full update on the corresponding EQ chain
        // ...
    }
}
```

**Sample rate change handling:** When the output device changes and the pipeline restarts, `currentSampleRate` is updated in `start()` and `reapplyAllCoefficients()` is called to recalculate everything.

---

### Phase 6: Preset Migration and FilterType Adoption

`AVAudioUnitEQFilterType` currently appears in 22 locations across the codebase. This phase migrates them all to `FilterType`.

**File:** `src/domain/eq/EQConfiguration.swift` (MODIFY)

Change `EQBandConfiguration.filterType` from `AVAudioUnitEQFilterType` to `FilterType`:

```swift
struct EQBandConfiguration: Codable, Sendable {
    var frequency: Float
    var bandwidth: Float
    var gain: Float
    var filterType: FilterType    // Changed from AVAudioUnitEQFilterType
    var bypass: Bool

    // Backward-compatible decoding: reads Int raw value,
    // maps through FilterType(from: AVAudioUnitEQFilterType) for old data
    init(from decoder: Decoder) throws {
        // ...
        let filterTypeRaw = try container.decode(Int.self, forKey: .filterType)
        // Raw values 0-10 map identically between AVAudioUnitEQFilterType and FilterType
        filterType = FilterType(rawValue: filterTypeRaw) ?? .parametric
    }
}
```

**File:** `src/domain/presets/PresetModel.swift` (MODIFY)

```swift
struct PresetSettings: Codable, Sendable {
    var globalBypass: Bool
    var inputGain: Float
    var outputGain: Float

    // New: channel mode (defaults to .linked for legacy presets)
    var channelMode: ChannelMode

    // New: per-channel state
    var linkedConfig: ChannelEQState
    var leftConfig: ChannelEQState
    var rightConfig: ChannelEQState

    // Legacy fields for backward-compatible decoding
    // var activeBandCount: Int  — decoded into linkedConfig
    // var bands: [PresetBand]   — decoded into linkedConfig
}
```

Bump `Preset.currentVersion` to 2.

**Backward-compatible decoding:**

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    globalBypass = try container.decode(Bool.self, forKey: .globalBypass)
    inputGain = try container.decode(Float.self, forKey: .inputGain)
    outputGain = try container.decode(Float.self, forKey: .outputGain)

    // Try new format first
    if let mode = try container.decodeIfPresent(ChannelMode.self, forKey: .channelMode) {
        channelMode = mode
        linkedConfig = try container.decode(ChannelEQState.self, forKey: .linkedConfig)
        leftConfig = try container.decode(ChannelEQState.self, forKey: .leftConfig)
        rightConfig = try container.decode(ChannelEQState.self, forKey: .rightConfig)
    } else {
        // Legacy format: single band array → linked mode, single layer
        channelMode = .linked
        let bands = try container.decode([PresetBand].self, forKey: .bands)
        let bandCount = try container.decode(Int.self, forKey: .activeBandCount)
        let layer = EQLayerState(
            label: "User EQ",
            bands: bands.map { $0.toEQBandConfiguration() },
            activeBandCount: bandCount,
            bypass: false
        )
        let state = ChannelEQState(layers: [layer])
        linkedConfig = state
        leftConfig = state   // Copy for stereo if user switches later
        rightConfig = state
    }
}
```

**File:** `src/domain/presets/PresetModel.swift` (MODIFY continued)

Change `PresetBand.filterType` from `AVAudioUnitEQFilterType` to `FilterType`.

**Files to update** (mechanical `AVAudioUnitEQFilterType` → `FilterType` replacement):

| File | Change |
|------|--------|
| `src/domain/eq/EQConfiguration.swift` | `filterType` property type |
| `src/domain/presets/PresetModel.swift` | `PresetBand.filterType`, `PresetSettings` structure |
| `src/store/EqualiserStore.swift` | `updateBandFilterType` signature |
| `src/viewmodels/EQViewModel.swift` | `updateBandFilterType` signature |
| `src/views/eq/EQBandSliderView.swift` | Filter type picker binding |
| `src/views/shared/AVAudioUnitEQFilterTypeExtension.swift` | Move display names to `FilterType` extension, keep file for migration or delete |
| `src/services/presets/EasyEffectsImporter.swift` | `mapFilterType` returns `FilterType` |
| `src/services/presets/EasyEffectsExporter.swift` | `mapFilterType` accepts `FilterType` |
| `src/services/presets/PresetManager.swift` | `applyPreset` uses `FilterType` |
| `src/app/AppStateSnapshot.swift` | Bands use `FilterType` (backward-compatible decode) |
| `tests/domain/presets/PresetCodableTests.swift` | Update filter type references |
| `tests/domain/presets/EasyEffectsImportExportTests.swift` | Update filter type references |

**Note:** Since `FilterType` raw values 0–10 are identical to `AVAudioUnitEQFilterType` raw values 0–10, existing persisted JSON decodes correctly without any data migration. The only change is the Swift type.

---

### Phase 7: AppStateSnapshot Migration

**File:** `src/app/AppStateSnapshot.swift` (MODIFY)

```swift
struct AppStateSnapshot: Codable, Sendable {
    // MARK: - EQ Configuration
    var globalBypass: Bool
    var inputGain: Float
    var outputGain: Float
    var channelMode: ChannelMode          // NEW

    // Per-channel state (NEW)
    var linkedState: ChannelEQState
    var leftState: ChannelEQState
    var rightState: ChannelEQState

    // MARK: - App State (unchanged)
    var inputDeviceID: String?
    var outputDeviceID: String?
    var bandwidthDisplayMode: String
    var manualModeEnabled: Bool
    var captureMode: Int
    var metersEnabled: Bool

    // Legacy fields removed:
    // var activeBandCount: Int  — now in per-channel state
    // var bands: [EQBandConfiguration]  — now in per-channel state
}
```

**Backward-compatible decoding:** Same pattern as `PresetSettings` — detect legacy format by absence of `channelMode` key, load single band array into `linkedState`, copy to `leftState`/`rightState`.

---

### Phase 8: UI Changes

**File:** `src/views/eq/EQBandGridView.swift` (MODIFY)

Add channel mode selector and channel focus toggle:

```swift
struct EQBandGridView: View {
    @EnvironmentObject var store: EqualiserStore

    // UI-only state: which channel is being edited in stereo mode
    @State private var channelFocus: ChannelFocus = .left

    var body: some View {
        VStack {
            // Channel mode selector
            Picker("Mode", selection: $store.channelMode) {
                Text("Linked").tag(ChannelMode.linked)
                Text("Stereo").tag(ChannelMode.stereo)
            }
            .pickerStyle(.segmented)

            // Channel focus (only visible in stereo mode)
            if store.channelMode == .stereo {
                Picker("Channel", selection: $channelFocus) {
                    Text("L").tag(ChannelFocus.left)
                    Text("R").tag(ChannelFocus.right)
                }
                .pickerStyle(.segmented)
            }

            // Band sliders — show bands for the active channel/focus
            ForEach(0..<activeBandCount, id: \.self) { index in
                EQBandSliderView(
                    // ... bind to appropriate channel's band based on channelFocus
                )
            }
        }
    }
}
```

**File:** `src/views/eq/EQBandSliderView.swift` (MODIFY)

- Filter type picker uses `FilterType` instead of `AVAudioUnitEQFilterType`
- Display names and abbreviations move to `FilterType` extension

**File:** `src/views/shared/AVAudioUnitEQFilterTypeExtension.swift` (DELETE or REPURPOSE)

- Move `displayName`, `abbreviation`, `allCasesInUIOrder` to a new `FilterType` extension
- Delete the old file once all references are migrated

**New file:** `src/domain/eq/FilterType+Display.swift` or add to `FilterType.swift`:

```swift
extension FilterType {
    var displayName: String {
        switch self {
        case .parametric: return "Parametric"
        case .lowPass: return "Low Pass"
        case .highPass: return "High Pass"
        // ... all 11 types
        }
    }

    var abbreviation: String {
        switch self {
        case .parametric: return "Bell"
        case .lowPass: return "LP"
        // ... all 7 types
        }
    }

    static var allCasesInUIOrder: [FilterType] {
        [.parametric, .lowPass, .highPass, .lowShelf, .highShelf,
         .bandPass, .notch]
    }
}
```

**UI state type:**

```swift
/// Which channel the user is editing. UI-only, not persisted.
enum ChannelFocus: String, Sendable {
    case left
    case right
}
```

This lives in the views layer (e.g. `src/views/eq/ChannelFocus.swift`) since it is presentation state, not domain state.

---

## Complete File Reference

### New Files

| File | Layer | Purpose |
|------|-------|---------|
| `src/domain/eq/FilterType.swift` | Domain | Filter type enum (replaces `AVAudioUnitEQFilterType`) |
| `src/domain/eq/BiquadCoefficients.swift` | Domain | Normalised coefficient value type |
| `src/domain/eq/BiquadMath.swift` | Domain | Pure RBJ Cookbook coefficient calculation |
| `src/domain/eq/ChannelMode.swift` | Domain | `linked` / `stereo` enum |
| `src/domain/eq/EQLayerState.swift` | Domain | Per-layer band configuration value type |
| `src/domain/eq/EQLayerConstants.swift` | Domain | Layer count limits and well-known indices |
| `src/domain/eq/ChannelEQState.swift` | Domain | Per-channel state containing ordered layers |
| `src/services/audio/dsp/BiquadFilter.swift` | Service | vDSP biquad wrapper with delay state |
| `src/services/audio/dsp/EQChain.swift` | Service | Per-layer-per-channel filter chain with lock-free updates |
| `src/views/eq/ChannelFocus.swift` | View | UI-only L/R editing focus enum |
| `tests/domain/eq/BiquadMathTests.swift` | Test | Coefficient calculation tests |
| `tests/domain/eq/FilterTypeTests.swift` | Test | FilterType mapping and coding tests |
| `tests/services/audio/dsp/BiquadFilterTests.swift` | Test | DSP processing tests |
| `tests/services/audio/dsp/EQChainTests.swift` | Test | Chain processing and coefficient staging tests |
| `tests/domain/presets/PresetMigrationTests.swift` | Test | Legacy → v2 preset decoding tests |

### Modified Files

| File | Changes |
|------|---------|
| `src/domain/eq/EQConfiguration.swift` | Per-channel state, `FilterType`, remove `apply(to:)` methods |
| `src/domain/presets/PresetModel.swift` | Per-channel `PresetSettings`, `FilterType`, backward-compat decode |
| `src/app/AppStateSnapshot.swift` | Per-channel state, backward-compat decode |
| `src/services/audio/rendering/RenderCallbackContext.swift` | Own `EQChain` arrays (maxLayerCount per channel), add `processEQ()`, remove `renderContext` |
| `src/services/audio/rendering/RenderPipeline.swift` | Remove engine lifecycle, new output callback, coefficient staging API |
| `src/store/coordinators/AudioRoutingCoordinator.swift` | Coefficient calculation, `reapplyAllCoefficients()`, sample rate tracking |
| `src/store/EqualiserStore.swift` | `FilterType` in API, `channelMode` property, update forwarding |
| `src/viewmodels/EQViewModel.swift` | `FilterType` in API |
| `src/views/eq/EQBandGridView.swift` | Channel mode selector, channel focus toggle |
| `src/views/eq/EQBandSliderView.swift` | `FilterType` picker |
| `src/services/presets/PresetManager.swift` | `FilterType`, per-channel preset apply |
| `src/services/presets/EasyEffectsImporter.swift` | `FilterType` mapping |
| `src/services/presets/EasyEffectsExporter.swift` | `FilterType` mapping |
| `tests/domain/presets/PresetCodableTests.swift` | `FilterType` references |
| `tests/domain/presets/EasyEffectsImportExportTests.swift` | `FilterType` references |

### Deleted Files

| File | Reason |
|------|--------|
| `src/services/audio/rendering/ManualRenderingEngine.swift` | Replaced by `EQChain` in `RenderCallbackContext` |
| `src/services/audio/rendering/AudioRenderContext.swift` | Replaced by direct biquad processing |
| `src/views/shared/AVAudioUnitEQFilterTypeExtension.swift` | Replaced by `FilterType` extension |

---

## Verification Plan

### Unit Tests

| Test | What It Verifies |
|------|------------------|
| `BiquadMathTests` | Coefficient values match reference (scipy/MATLAB) for all 11 filter types |
| `BiquadMathTests` | Edge cases: Nyquist frequency, 0.1 oct bandwidth, 8 oct bandwidth, 0 dB gain |
| `BiquadMathTests` | Identity: bypassed band returns passthrough coefficients |
| `FilterTypeTests` | Round-trip: `FilterType` → `AVAudioUnitEQFilterType` → `FilterType` |
| `FilterTypeTests` | Codable: encode/decode preserves raw values |
| `BiquadFilterTests` | Impulse response matches expected for parametric +6 dB at 1 kHz |
| `BiquadFilterTests` | Passthrough: identity coefficients produce input == output |
| `EQChainTests` | Multiple bands process in series correctly |
| `EQChainTests` | Bypassed bands are skipped (output unchanged) |
| `EQChainTests` | `stageBandUpdate` + `applyPendingUpdates` applies new coefficients |
| `PresetMigrationTests` | Legacy v1 preset decodes into linked mode with correct bands |
| `PresetMigrationTests` | New v2 preset round-trips through encode/decode |
| `PresetCodableTests` | Updated for `FilterType` (existing tests still pass) |

### Integration Tests

| Test | What It Verifies |
|------|------------------|
| L channel isolation | Modifying L EQ chain does not affect R output |
| R channel isolation | Modifying R EQ chain does not affect L output |
| Linked mode | Updates both channels identically |
| Preset load | Loading legacy preset produces correct coefficients on both channels |
| Sample rate change | Pipeline restart recalculates all coefficients |

### Manual Testing

| Scenario | Expected |
|----------|----------|
| Load legacy preset | Linked mode, same EQ on both channels, sounds identical to v1 |
| Switch to stereo mode | L and R become independent, can modify separately |
| Modify L only in stereo | R channel unchanged, hear difference in stereo field |
| Play mono content in linked mode | Identical to current app behaviour |
| Change output device (different sample rate) | Pipeline restarts, EQ sounds the same |
| Rapid slider movement | No clicks, pops, or glitches (coefficient ramping is smooth) |

---

## Risks and Mitigations

### Channel Drift

**Concern:** Will separate processing chains cause L/R phase drift?

**Analysis:** Biquad IIR filters have deterministic phase response that depends only on the coefficients, not on which instance processes them. Same parameters → identical phase. Different parameters → intentional stereo imaging change. This is expected behaviour for independent channel EQ.

**Verdict:** Not a risk.

### vDSP Setup Rebuild Cost

**Concern:** `vDSP_biquad_CreateSetup` allocates internally. Calling it from the audio thread when coefficients change could cause a glitch.

**Mitigation:** The `applyPendingUpdates()` method calls `vDSP_biquad_CreateSetup` for each changed band. This is a bounded operation (at most 64 bands × one small allocation each). In practice, most updates change 1 band at a time. If profiling shows this is too expensive:
- **Alternative A:** Use Direct Form 1 manual implementation instead of vDSP (no setup object needed, just 5 coefficients and 4 delay elements per band)
- **Alternative B:** Pre-build the new setup on the main thread and pass it via atomic pointer swap

Start with vDSP (simplest correct implementation), profile, and optimise only if needed.

### Coefficient Discontinuities

**Concern:** Swapping coefficients mid-stream could cause clicks if the filter's internal state (delay elements) is inconsistent with the new coefficients.

**Mitigation:** For small parameter changes (e.g. slider movement), the coefficient change is small enough that the transient is inaudible. For large changes (e.g. preset load), the delay elements are reset to zero, which produces a brief transient that decays within a few samples. This matches the behaviour of `AVAudioUnitEQ` when parameters are changed.

If audible artefacts occur during smooth slider sweeps, add per-sample coefficient interpolation as a follow-up (crossfade between old and new coefficients over one buffer).

### Existing Test Breakage

**Concern:** Many existing tests reference `AVAudioUnitEQFilterType`.

**Mitigation:** Phase 6 includes a mechanical replacement of all 22 references. Since raw values are identical, no test logic changes — only type names. Run `swift test` after each file change to catch regressions immediately.

---

## Implementation Order (Safe Incremental Steps)

Each step leaves the project in a compiling, working state.

| Step | Phase | Description | Compiles? | Audio Works? |
|------|-------|-------------|-----------|--------------|
| 1 | 1 | Add `FilterType.swift`, `BiquadCoefficients.swift`, `BiquadMath.swift` to domain | ✅ | ✅ (no changes to existing code) |
| 2 | 1 | Add `BiquadMathTests.swift`, `FilterTypeTests.swift` | ✅ | ✅ |
| 3 | 2 | Add `ChannelMode.swift`, `ChannelEQState.swift` to domain | ✅ | ✅ |
| 4 | 3 | Add `BiquadFilter.swift`, `EQChain.swift` to services | ✅ | ✅ |
| 5 | 3 | Add `BiquadFilterTests.swift`, `EQChainTests.swift` | ✅ | ✅ |
| 6 | 6 | Migrate `AVAudioUnitEQFilterType` → `FilterType` across all files | ✅ | ✅ (AVAudioUnitEQ still uses conversion) |
| 7 | 4 | Add `EQChain` to `RenderCallbackContext`, add `processEQ()` | ✅ | ✅ (EQ chains exist but not yet used) |
| 8 | 4 | Replace output callback EQ path: use `processEQ()` instead of `renderCtx.render()` | ✅ | ✅ (biquads now processing audio) |
| 9 | 4 | Remove `ManualRenderingEngine.swift`, `AudioRenderContext.swift` | ✅ | ✅ |
| 10 | 5 | Update call chain: coefficient calculation in coordinator, staging API | ✅ | ✅ |
| 11 | 5 | Modify `EQConfiguration` for per-channel state | ✅ | ✅ (linked mode only initially) |
| 12 | 6 | Update `PresetSettings`, `PresetBand`, backward-compat decode | ✅ | ✅ |
| 13 | 7 | Update `AppStateSnapshot` with per-channel state | ✅ | ✅ |
| 14 | 8 | Add channel mode UI, channel focus toggle | ✅ | ✅ |
| 15 | — | End-to-end manual testing and bug fixes | ✅ | ✅ |

**Critical gate:** After step 8, audio must work identically to the current implementation (linked mode, same EQ on both channels). This is the most important validation point. All subsequent steps add features on top of working audio.

---

## Estimated Complexity

| Phase | Work | Estimate |
|-------|------|----------|
| Phase 1 | FilterType, BiquadCoefficients, BiquadMath + tests | ~4 hours |
| Phase 2 | ChannelMode, EQLayerState, ChannelEQState, EQLayerConstants | ~2 hours |
| Phase 3 | BiquadFilter, EQChain + tests | ~4 hours |
| Phase 4 | RenderCallbackContext integration, output callback, delete old files | ~5 hours |
| Phase 5 | Update call chain, EQConfiguration per-channel state | ~4 hours |
| Phase 6 | FilterType migration (22 files), preset backward compat + tests | ~4 hours |
| Phase 7 | AppStateSnapshot migration | ~1 hour |
| Phase 8 | UI changes (channel mode, channel focus) | ~3 hours |
| — | End-to-end testing and bug fixes | ~4 hours |
| **Total** | | **~31 hours** |

---

## Future: Stacked EQ Layers

The architecture is designed to support multiple stacked EQ layers without structural changes. Here is what adding a new layer (e.g. headphone correction) would require:

| Area | Change Required |
|------|-----------------|
| Domain | Add a new `EQLayerState` to `ChannelEQState.layers` array |
| Constants | Add `headphoneCorrectionLayerIndex = 1` to `EQLayerConstants` |
| Audio thread | Already handled — `processEQ()` iterates all chains in series |
| Coordinator | New method `updateHeadphoneCorrectionBand(index:)` targeting `layerIndex: 1` |
| Pipeline | Already handled — `updateBandCoefficients(layerIndex:)` accepts any layer |
| Presets | Layers are an array in `ChannelEQState` — new layers serialise automatically |
| UI | New section/tab for the correction layer, same band slider components |
| Pipeline restart | **Not required** — chains are pre-allocated |
| Preset migration | **Not required** — old presets have 1-element layer array, new presets have N |

**What you do NOT need to change:**

- `EQChain` — already generic, works for any layer
- `BiquadFilter` / `BiquadMath` — layer-agnostic
- `RenderCallbackContext.processEQ()` — already iterates all chains
- `RenderPipeline` staging API — already accepts `layerIndex`
- Preset format — layers array is forward-compatible
