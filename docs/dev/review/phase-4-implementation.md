# Phase 4: Code Quality Improvements - Detailed Implementation Plan

**Priority:** P2-P3  
**Estimated Effort:** 1-2 days  
**Risk Level:** Low (minor refactoring, no architectural changes)

---

## Goal

Address minor issues and improve code consistency through targeted cleanups.

---

## Problems Identified

### Problem 4.1: View Models Recreated on Every Access

**Location:** `src/views/main/EQWindowView.swift:11-18`

```swift
/// View model for routing status.
private var routingViewModel: RoutingViewModel {
    RoutingViewModel(store: store)  // Creates new instance each time
}

/// View model for EQ configuration.
private var eqViewModel: EQViewModel {
    EQViewModel(store: store)  // Creates new instance each time
}
```

**Analysis:**
- Computed properties create new instances on every access
- View models are accessed multiple times during view updates
- Minor performance overhead, but unnecessary

**Impact:** Minor performance, code clarity.

**Approach:**
Use `@State` for view model storage and create lazily on first access.

---

### Problem 4.2: Replace DispatchQueue with Task (Already Done)

**Status:** ✅ COMPLETED in Phase 3

The `DispatchQueue.main.asyncAfter` in `updateDriverName()` has been replaced with `Task.sleep` in the extracted `DriverNameManager` class.

Remaining `DispatchQueue` usages are appropriate:
- Background queues for audio listeners (correct)
- `DispatchQueue.main` for UI updates (correct)
- `.receive(on: DispatchQueue.main)` for Combine (correct)

---

### Problem 4.3: Redundant Change Notifications (NOT APPLICABLE)

**Status:** ⏭️ SKIPPED - Analysis was incorrect

**Analysis:**
Upon investigation, the `objectWillChange.send()` calls are **NOT redundant**.

The `bands` property is declared as `@Published private(set) var bands`. When you modify `bands[index].gain`, you're modifying an element **inside** the array, not reassigning the `bands` property itself. 

`@Published` only triggers `objectWillChange` when you assign to the whole property:
- ✅ `bands = newArray` → triggers `objectWillChange`
- ❌ `bands[index].gain = 5` → does NOT trigger `objectWillChange`

Therefore, the manual `objectWillChange.send()` calls are **required** for SwiftUI to detect element-level changes.

**Impact:** No change needed - code is correct.

---

### Problem 4.4: Synthesized Codable (Not Applicable)

**Status:** ⏭️ NOT APPLICABLE

Upon investigation, `EQBandConfiguration.swift` does not exist. The codable implementations for EQ bands are in `EQConfiguration.swift` and use synthesized Codable from the `PresetBand` type in the preset domain, not manual implementations.

---

### Problem 4.5: Preset Import Validation

**Location:** `src/services/presets/EasyEffectsImporter.swift:257-286`

```swift
private static func parseBand(_ data: [String: Any], index: Int, warnings: inout [String]) -> PresetBand {
    let frequency = (data["frequency"] as? NSNumber)?.floatValue ?? defaultFrequency(for: index)
    let gain = (data["gain"] as? NSNumber)?.floatValue ?? 0
    let q = (data["q"] as? NSNumber)?.floatValue ?? 1.41
    // ... no validation of bounds
}
```

**Analysis:**
- Frequency, gain, bandwidth values arenot validated
- Could produce invalid EQ settings
- Malformed presets could cause issues

**Impact:** Edge case robustness.

**Approach:**
Add validation for:
- Frequency: 20 Hz - 20 kHz (clamped)
- Gain: ±24 dB (clamped, AUNBandEQ limit)
- Bandwidth: 0.1 - 8.0 octaves (clamped, meaningful range)

---

### Problem 4.6: Extract Audio Constants

**Locations:**
- `src/services/audio/rendering/RenderPipeline.swift:62-65`

```swift
private let maxFrameCount: UInt32 = 4096
private let ringBufferCapacity: Int = 8192
```

**Analysis:**
- Hardcoded values in render pipeline
- No documentation of why these values were chosen
- Scattered across files (RenderCallbackContext also has frame counts)

**Impact:** Organization, maintainability.

**Approach:**
Create `AudioConstants.swift` with documented constants.

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/views/main/EQWindowView.swift` | Cache view models with `@State` |
| `src/domain/eq/EQConfiguration.swift` | Remove redundant notifications |
| `src/services/presets/EasyEffectsImporter.swift` | Add validation |
| `src/services/audio/AudioConstants.swift` | NEW - Centralized constants |
| `src/services/audio/rendering/RenderPipeline.swift` | Use constants |
| `src/services/audio/rendering/RenderCallbackContext.swift` | Use constants |

---

## Step-by-Step Implementation

### Step 1: Cache View Models

**File:** `src/views/main/EQWindowView.swift`

Replace computed properties with `@State`:

```swift
struct EQWindowView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var showCompareHelp = false
    @State private var metersEnabledUI = false
    
    // Cached view models - created once per view lifecycle
    @State private var routingViewModel: RoutingViewModel!
    @State private var eqViewModel: EQViewModel!
    
    var body: some View {
        VStack(spacing: 12) {
            // ... existing code using routingViewModel and eqViewModel
        }
        .onAppear {
            // Lazily create view models on first appear
            if routingViewModel == nil {
                routingViewModel = RoutingViewModel(store: store)
            }
            if eqViewModel == nil {
                eqViewModel = EQViewModel(store: store)
            }
            store.meterStore.windowBecameVisible()
        }
        // ... rest unchanged
    }
}
```

---

### Step 2: Remove Redundant Notifications

**File:** `src/domain/eq/EQConfiguration.swift`

Remove `objectWillChange.send()` calls from all band update methods:

```swift
/// Updates the gain for a specific band.
func updateBandGain(index: Int, gain: Float) {
    guard isValidIndex(index) else { return }
    bands[index].gain = gain
    // objectWillChange.send() removed - @Published handles this
}

/// Updates the bandwidth for a specific band.
func updateBandBandwidth(index: Int, bandwidth: Float) {
    guard isValidIndex(index) else { return }
    bands[index].bandwidth = bandwidth
    // objectWillChange.send() removed
}

/// Updates the frequency for a specific band.
func updateBandFrequency(index: Int, frequency: Float) {
    guard isValidIndex(index) else { return }
    bands[index].frequency = frequency
    // objectWillChange.send() removed
}

/// Updates the bypass state for a specific band.
func updateBandBypass(index: Int, bypass: Bool) {
    guard isValidIndex(index) else { return }
    bands[index].bypass = bypass
    // objectWillChange.send() removed
}

/// Updates the filter type for a specific band.
func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
    guard isValidIndex(index) else { return }
    bands[index].filterType = filterType
    // objectWillChange.send() removed
}
```

---

### Step 3: Add Preset Import Validation

**File:** `src/services/presets/EasyEffectsImporter.swift`

Add validation helper and update `parseBand`:

```swift
// MARK: - Validation Constants

private enum BandValidation {
    static let minFrequency: Float = 20
    static let maxFrequency: Float = 20000
    static let minGain: Float = -96  // dB, AUNBandEQ practical limit
    static let maxGain: Float = 24    // dB, AUNBandEQ limit
    static let minBandwidth: Float = 0.1  // octaves
    static let maxBandwidth: Float = 8.0   // octaves
    
    static func clampFrequency(_ value: Float) -> Float {
        max(minFrequency, min(maxFrequency, value))
    }
    
    static func clampGain(_ value: Float) -> Float {
        max(minGain, min(maxGain, value))
    }
    
    static func clampBandwidth(_ value: Float) -> Float {
        max(minBandwidth, min(maxBandwidth, value))
    }
}

private static func parseBand(_ data: [String: Any], index: Int, warnings: inout [String]) -> PresetBand {
    let rawFrequency = (data["frequency"] as? NSNumber)?.floatValue ?? defaultFrequency(for: index)
    let rawGain = (data["gain"] as? NSNumber)?.floatValue ?? 0
    let rawQ = (data["q"] as? NSNumber)?.floatValue ?? 1.41
    let mute = data["mute"] as? Bool ?? false
    let typeString = data["type"] as? String ?? "Bell"
    
    // Validate and clamp values
    let frequency = BandValidation.clampFrequency(rawFrequency)
    let gain = BandValidation.clampGain(rawGain)
    let bandwidth = BandValidation.clampBandwidth(BandwidthConverter.qToBandwidth(rawQ))
    
    // Warn if values were clamped
    if frequency != rawFrequency {
        warnings.append("Band \(index): frequency clamped from \(rawFrequency) Hz to \(frequency) Hz")
    }
    if gain != rawGain {
        warnings.append("Band \(index): gain clamped from \(rawGain) dB to \(gain) dB")
    }
    
    // Convert filter type
    let filterType = mapFilterType(typeString)
    
    // Check for ignored parameters
    if data["solo"] as? Bool == true {
        warnings.append("Band \(index): Solo mode is ignored")
    }
    
    return PresetBand(
        frequency: frequency,
        bandwidth: BandwidthConverter.clampBandwidth(bandwidth),
        gain: gain,
        filterType: filterType,
        bypass: mute
    )
}
```

---

### Step 4: Extract Audio Constants

**File:** `src/services/audio/AudioConstants.swift` (NEW)

```swift
// AudioConstants.swift
// Centralized constants for audio pipeline configuration

import Foundation

/// Constants for audio rendering pipeline configuration.
///
/// These values were chosen based on:
/// - Real-time safety requirements
/// - Memory constraints
/// - Latency vs. stability tradeoffs
enum AudioConstants {
    // MARK: - Render Pipeline
    
    /// Maximum frames per render callback.
    ///
    /// This is the worst-case frame count that CoreAudio may request.
    /// Setting this too low causes buffer overflows on high sample rates.
    /// Setting too high wastes memory.
    ///
    /// - 4096 frames = ~85ms at 48kHz, ~43ms at 96kHz
    static let maxFrameCount: UInt32 = 4096
    
    /// Ring buffer capacity in sample frames per channel.
    ///
    /// Must be a power of 2 for efficient modulo arithmetic.
    /// Larger values provide more resilience against clock drift but increase latency.
    ///
    /// - 8192 samples = ~170ms at 48kHz, ~85ms at 96kHz
    /// - Chosen to handle reasonable clock drift between devices
    static let ringBufferCapacity: Int = 8192
    
    // MARK: - Format Constants
    
    /// Minimum allowed EQ frequency in Hz.
    static let minEQFrequency: Float = 20
    
    /// Maximum allowed EQ frequency in Hz.
    static let maxEQFrequency: Float = 20000
    
    /// Minimum gain in dB (AUNBandEQ practical limit).
    static let minGain: Float = -96
    
    /// Maximum gain in dB (AUNBandEQ hard limit).
    static let maxGain: Float = 24
    
    /// Minimum bandwidth in octaves.
    static let minBandwidth: Float = 0.1
    
    /// Maximum bandwidth in octaves.
    static let maxBandwidth: Float = 8.0
}
```

**File:** `src/services/audio/rendering/RenderPipeline.swift`

Update to use constants:

```swift
// Replace:
private let maxFrameCount: UInt32 = 4096
private let ringBufferCapacity: Int = 8192

// With:
private let maxFrameCount: UInt32 = AudioConstants.maxFrameCount
private let ringBufferCapacity: Int = AudioConstants.ringBufferCapacity
```

**File:** `src/services/audio/rendering/RenderCallbackContext.swift`

If there are similar hardcoded values, update similarly.

---

## Test Plan

### Step 1 Tests: View Model Caching
- Existing EQ window tests pass
- View models are created once
- State persists across view updates

### Step 2 Tests: Redundant Notifications
- `swift test --filter EQConfigurationTests` passes
- EQ band updates still trigger SwiftUI refresh

### Step 3 Tests: Preset Validation
- Test import with out-of-bounds values
- Verify warnings are generated
- Verify clamped values are applied

### Step 4 Tests: Audio Constants
- `swift build` succeeds
- `swift test` passes
- Audio pipeline functions correctly

---

## Rollback Strategy

If issues arise:

1. **Git revert:**
   ```bash
   git revert <commit-hash>
   ```

2. **Individual reversions:**
   - Step 1: Revert to computed properties
   - Step 2: Add back `objectWillChange.send()` calls
   - Step 3: Remove validation from importer
   - Step 4: Inline constants back

---

## Success Criteria

- [ ] View models created once per view lifecycle
- [ ] No redundant change notifications
- [ ] Preset import validates and clamps values
- [ ] Audio constants centralized with documentation
- [ ] All tests pass
- [ ] Build succeeds in release mode

---

## Notes

### Why Not Use `@StateObject`?

`@StateObject` is for objects owned by the view, but these view models hold `unowned` references to the store. The current pattern works correctly - we just need to avoid recreating them unnecessarily.

### Why Keep DispatchQueue in Other Places?

The remaining `DispatchQueue` usages are correct:
- Background queues for CoreAudio listeners (required for real-time safety)
- `DispatchQueue.main` for UI thread dispatching
- `.receive(on: DispatchQueue.main)` for Combine subscription

These should not be converted to `Task` as they serve different purposes.

### Why Validate on Import?

AUNBandEQ has hard limits that could cause unexpected behaviour:
- Gain clamped to ±24 dB by the audio unit
- Frequencies outside 20Hz-20kHz are filtered by the sample rate
- Bandwidth outside reasonable range can cause filter instability

Validating on import provides early warning to users.

---

*This plan should be followed step-by-step. Each step should be verified with builds and tests before proceeding to the next.*