# Phase 4: Extract Meter Services

## Goal

Consolidate meter-related constants and calculation logic into shared utilities to eliminate duplication and improve maintainability, while preserving real-time safety for audio thread code.

---

## Current State Analysis

### Files with Meter-Related Code

| File | Lines | Purpose |
|------|-------|---------|
| `MeterStore.swift` | 402 | UI meter state management, smoothing, peak hold |
| `RenderCallbackContext.swift` | 422 | Real-time meter calculations on audio thread |
| `MeterScaleView.swift` | 75 | Meter scale visualization constants and normalization |
| `MeterCalculationTests.swift` | 213 | Tests for meter math |

### Constants Duplication

| Constant | MeterStore.swift | RenderCallbackContext.swift | MeterScaleView.swift |
|----------|------------------|----------------------------|----------------------|
| Silence floor | `silenceThreshold = -85` | `silenceDB = -90` | — |
| Meter range | `-36...0` | — | `-36...0` |
| Gamma | `0.5` | — | `0.5` |
| Max channels | — | `maxMeterChannels = 2` | — |

### Formula Duplication

**dB to Normalized Position (0-1)**:

```swift
// MeterStore.swift (line 388-400)
private static func normalize(db: Float) -> Float {
    if db <= meterRange.lowerBound { return 0 }
    if db >= meterRange.upperBound { return 1 }
    let amp = powf(10.0, 0.05 * db)
    let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
    let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
    let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
    return powf(normalizedAmp, gamma)
}

// MeterScaleView.swift (lines 11-19)
static func normalizedPosition(for db: Float) -> Float {
    if db <= meterRange.lowerBound { return 0 }
    if db >= meterRange.upperBound { return 1 }
    let amp = powf(10.0, 0.05 * db)
    let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
    let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
    let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
    return powf(normalizedAmp, gamma)
}
```

**These are IDENTICAL implementations.**

### Linear-to-dB Conversion

```swift
// RenderCallbackContext.swift (line 380)
let db = max(Self.silenceDB, 20 * log10(max(peak, 1e-7)))
```

This is the standard formula, could be centralized.

---

## Architecture Approach

```
Sources/Core/Meters/
├── MeterConstants.swift    ← All shared constants
├── MeterMath.swift         ← Pure functions (real-time safe)
└── (future protocols)

Sources/Core/
├── MeterStore.swift        ← Updated to use MeterConstants, MeterMath
└── ...

Sources/Audio/Rendering/
└── RenderCallbackContext.swift  ← Updated to use MeterConstants.silenceDB

Sources/Views/Meters/
└── MeterScaleView.swift    ← Updated to use MeterConstants
```

### Key Design Principles

1. **Real-Time Safety**: `MeterMath` functions must be:
   - `@inline(__always)` for performance
   - No allocations
   - No locks
   - Pure functions (no side effects)

2. **Constants Centralization**: All magic numbers in one place with clear documentation

3. **Minimal Changes**: Keep existing logic intact, just relocate

---

## Files to Modify

| File | Change |
|------|--------|
| `MeterStore.swift` | Use `MeterConstants`, `MeterMath` |
| `RenderCallbackContext.swift` | Use `MeterConstants.silenceDB` |
| `MeterScaleView.swift` | Use `MeterConstants` (remove local `enum`) |

## Files to Create

| File | Purpose |
|------|---------|
| `Sources/Core/Meters/MeterConstants.swift` | All meter-related constants |
| `Sources/Core/Meters/MeterMath.swift` | Pure calculation functions |

---

## Step-by-Step Implementation Plan

### Step 1: Create MeterConstants.swift

**Location**: `Sources/Core/Meters/MeterConstants.swift`

**Content**:
```swift
/// Shared constants for audio level meter calculations and visualization.
/// Used by both real-time audio code (RenderCallbackContext) and UI (MeterStore, MeterScaleView).
enum MeterConstants {
    // MARK: - Thresholds
    
    /// Minimum dB value for meters (silence floor).
    /// Values below this are treated as complete silence.
    static let silenceDB: Float = -90
    
    /// Threshold below which meters are considered silent (for rest detection).
    /// Used by MeterStore to stop updating when audio is quiet.
    static let silenceThreshold: Float = -85
    
    /// Threshold for at-rest state (meters stop updating).
    static let atRestThreshold: Float = 0.01
    
    // MARK: - Display Range
    
    /// The dB range for meter display.
    /// -36 dB to 0 dB is a common range for audio meters.
    static let meterRange: ClosedRange<Float> = -36...0
    
    // MARK: - Timing
    
    /// Meter update interval (30 FPS).
    static let meterInterval: TimeInterval = 1.0 / 30.0
    
    /// Duration to hold peak before decay.
    static let peakHoldDuration: TimeInterval = 1.0
    
    /// Duration to show clipping indicator.
    static let clipHoldDuration: TimeInterval = 0.5
    
    // MARK: - Smoothing
    
    /// Smoothing for peak attack (fast rise).
    static let peakAttackSmoothing: Float = 1.0
    
    /// Smoothing for peak release (slow fall).
    static let peakReleaseSmoothing: Float = 0.33
    
    /// Smoothing for RMS meter.
    static let rmsSmoothing: Float = 0.12
    
    /// Peak hold decay per tick.
    static let peakHoldDecayPerTick: Float = 0.02
    
    // MARK: - Display
    
    /// Gamma value for perceptual scaling.
    static let gamma: Float = 0.5
    
    /// Maximum number of meter channels (stereo = 2).
    static let maxMeterChannels: Int = 2
    
    /// Minimum change threshold for UI updates.
    static let changeThreshold: Float = 0.002
    
    /// Height of the meter scale view in points.
    static let meterHeight: CGFloat = 126
    
    /// Standard dB tick values for meter scale marks.
    static let standardTickValues: [Float] = [0, -6, -12, -18, -24, -30, -36]
    
    // MARK: - Normalization
    
    /// Converts a dB value to a normalized position (0-1) for meter display.
    /// Uses gamma correction for perceptual uniformity.
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
```

### Step 2: Create MeterMath.swift

**Location**: `Sources/Core/Meters/MeterMath.swift`

**Content**:
```swift
import Foundation

/// Pure functions for meter calculations.
/// All functions are real-time safe: no allocations, no locks, no side effects.
/// Safe to call from audio render thread.
enum MeterMath {
    // MARK: - dB Conversion
    
    /// Converts linear amplitude to decibels.
    /// - Parameter linear: Linear amplitude (0-1 typical range).
    /// - Returns: dBFS value (0 = full scale, negative = quieter).
    @inline(__always)
    static func linearToDB(_ linear: Float, silence: Float = -90) -> Float {
        guard linear > 1e-7 else { return silence }
        return max(silence, 20 * log10(linear))
    }
    
    /// Converts decibels to linear amplitude.
    /// - Parameter db: dBFS value.
    /// - Returns: Linear amplitude.
    @inline(__always)
    static func dbToLinear(_ db: Float) -> Float {
        powf(10.0, 0.05 * db)
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
```

### Step 3: Update MeterStore.swift

Replace constants and `normalize` method:

```swift
// Remove local constants (lines 49-59):
// private static let peakHoldHoldDuration...
// private static let peakHoldDecayPerTick...
// etc.

// Add import if needed (already in same module)

// Update method calls:
// - Self.meterRange → MeterConstants.meterRange
// - Self.normalize(db:) → MeterConstants.normalizedPosition(for:)
// - Self.silenceThreshold → MeterConstants.silenceThreshold
// - Self.peakAttackSmoothing → MeterConstants.peakAttackSmoothing
// - etc.

// Remove static func normalize(db:) (lines 388-400) - use MeterConstants.normalizedPosition
```

### Step 4: Update RenderCallbackContext.swift

```swift
// Replace:
private static let silenceDB: Float = -90

// With:
private static let silenceDB: Float = MeterConstants.silenceDB

// Replace:
private static let maxMeterChannels = 2

// With:
private static let maxMeterChannels = MeterConstants.maxMeterChannels

// The inline dB conversion can stay inline (it's real-time critical):
// let db = max(Self.silenceDB, 20 * log10(max(peak, 1e-7)))
// This is fine - using MeterConstants.silenceDB for the floor value
```

### Step 5: Update MeterScaleView.swift

```swift
// Remove local enum MeterConstants (lines 4-20)
// Use MeterConstants directly:
// - MeterConstants.meterRange
// - MeterConstants.gamma
// - MeterConstants.meterHeight
// - MeterConstants.standardTickValues
// - MeterConstants.normalizedPosition(for:)
```

### Step 6: Update Tests

Update `MeterCalculationTests.swift` to test `MeterMath`:

```swift
// Add tests for:
// - MeterMath.linearToDB
// - MeterMath.dbToLinear
// - MeterMath.calculatePeak
// - MeterMath.calculateRMS
// - MeterMath.smoothMeter

// Existing tests for MeterConstants.normalizedPosition should pass unchanged
```

---

## Verification Checklist

- [ ] `swift build` compiles without errors
- [ ] `swift test` passes all tests
- [ ] App launches and meters display correctly
- [ ] Peak meters respond to audio
- [ ] RMS meters respond to audio
- [ ] Peak hold decay works correctly
- [ ] Clip indicator shows when audio clips
- [ ] Meters go to rest when audio stops
- [ ] Meter scale visual matches normalized values

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Real-time safety violation | Low | High | All MeterMath functions are pure, no allocations |
| Behavior change | Low | Medium | Keep existing formulas, just relocate |
| Test coverage gap | Low | Low | Add new tests for MeterMath before refactoring |

---

## Files Summary

```
Sources/Core/Meters/
├── MeterConstants.swift   ← NEW: All constants + normalizedPosition
└── MeterMath.swift         ← NEW: Pure calculation functions

Sources/Core/MeterStore.swift           ← MODIFIED: Use MeterConstants
Sources/Audio/Rendering/RenderCallbackContext.swift  ← MODIFIED: Use MeterConstants
Sources/Views/Meters/MeterScaleView.swift  ← MODIFIED: Use MeterConstants
Tests/MeterCalculationTests.swift  ← MODIFIED: Add MeterMath tests
```

---

## Success Criteria

1. ✅ All meter constants defined once in `MeterConstants`
2. ✅ `normalize(db:)` / `normalizedPosition(for:)` unified
3. ✅ `MeterMath` provides real-time safe calculations
4. ✅ All tests pass (141+ tests)
5. ✅ No behavior changes in meter display
6. ✅ No allocations in audio thread code