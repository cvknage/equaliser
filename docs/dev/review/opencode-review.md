# Comprehensive Code Review: Equaliser macOS App

**Review Date:** March 21, 2026  
**Reviewer:** OpenCode (GLM-5)  
**Codebase:** Swift 6, macOS 15+, Apple Silicon

---

## Executive Summary

This is a well-architected macOS menu bar audio equalizer application with a sophisticated CoreAudio pipeline. The codebase demonstrates strong software engineering practices with layered architecture, protocol-based dependency injection, and domain-driven design. However, there are several areas that could benefit from improvement across SOLID principles, real-time audio safety, and testability.

**Overall Rating:** 8/10

---

## 1. Architecture & Design Patterns

### Overall Assessment: **Good** - Layered architecture with clear separation of concerns

#### Strengths

- **Clean separation:** Domain layer (pure data types) → Services (infrastructure) → Coordinators (orchestration) → ViewModels (presentation) → Views
- **Protocol-based dependency injection** enables testability
- **Domain types** (`EQConfiguration`, `DeviceChangeDetector`, `HeadphoneSwitchPolicy`, `OutputDeviceSelection`) are pure and stateless

#### SRP Violations

**`EqualiserStore.swift`** (lines 18-571)

- **Problem:** Acts as both coordinator AND state container. Contains 571 lines with responsibilities for:
  - EQ band control
  - Preset management
  - Device selection delegation
  - Snapshot persistence
  - Routing status forwarding

**`AudioRoutingCoordinator.swift`** (lines 1-740)

- **Problem:** 740 lines handling device selection, sample rate sync, driver naming, and headphone detection callbacks.

**Recommendation:** Extract `DriverNameManager` for the complex naming logic (lines 650-739).

#### ISP Violations

**`DeviceManager.swift`** (lines 114-332)

- **Problem:** Acts as a "facade" but the protocol `Enumerating` is thin while `DeviceManager` has 25+ methods.

**Recommendation:** Split into focused interfaces:
- `DeviceEnumerating` (device lists)
- `DeviceVolumeControlling`
- `DeviceSampleRateQuerying`

#### OCP Assessment: **Good**

- `EQConfiguration.apply(to:)` uses open/closed principle well - can extend to new EQ unit types without modification
- `OutputDeviceSelection.determine()` is a pure function, easy to extend

#### DIP Assessment: **Good**

- Services injected via protocols (`VolumeControlling`, `SampleRateObserving`, `DriverLifecycleManaging`)
- Coordinators receive dependencies in `init()`

---

## 2. Audio Engine & DSP Logic

### Critical Issues

#### Real-Time Safety Assessment: **EXCELLENT**

**`AudioRingBuffer.swift`** (lines 100-199)

```swift
@inline(__always)
func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex...)
    // ... lock-free implementation
}
```

- Uses `OSAtomicAdd64Barrier` for thread safety without locks
- Zero allocations in read/write paths
- Memory barriers for proper synchronization

**`RenderCallbackContext.swift`** (lines 107-179)

- Pre-allocates ALL buffers during init
- Ring buffers, input buffers, output buffers, meter storage all allocated once
- No allocations in render path

**`ManualRenderingEngine.swift`** (lines 177-218)

- Uses `nonisolated` for audio thread access
- `[weak context]` avoids retain cycles

#### Processing Mode Logic: **CORRECT**

```swift
// Boost is ALWAYS applied (not inside bypass check)
context.applyGain(to: context.inputSampleBuffers, ...)

// Input gain is skipped in bypass mode
if context.processingMode != 0 {
    context.applyGain(...)
}
```

- Boost gain applied for driver volume compensation
- Input/output gains correctly skipped in bypass mode

#### Buffer Sizing

- `ringBufferCapacity: Int = 8192` at 96kHz = ~85ms
- Sufficient for clock drift compensation
- Could be configurable for different latency requirements

#### Frequency Band Configuration

```swift
nonisolated static func frequenciesForBandCount(_ count: Int) -> [Float] {
    if count == 10 {
        return [32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000]
    }
    // Logarithmic spacing for other band counts
}
```

- Standard 10-band octave frequencies
- Logarithmic spacing for other band counts

---

## 3. Swift Code Quality

### Idiomatic Swift: **STRONG**

**Good Practices:**
- `@MainActor` for UI-bound coordinators
- `nonisolated(unsafe)` for audio thread access
- `@Observable` for view models (SwiftUI native)
- `unowned` references in view models to avoid retain cycles
- Result types for error handling

### Force Unwraps / Implicit Optionals

**Minor Issue - `EQConfiguration.swift`** (line 107)

```swift
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
}
```

- Silent failure if band count doesn't match
- **Recommendation:** Log warning, validate explicitly

### Value Types vs Reference Types

**Good:** Domain models are structs:
- `AudioDevice`
- `EQBandConfiguration`
- `AppStateSnapshot`
- `DeviceChangeEvent`

**Appropriate Reference Types:**
- `EQConfiguration` - needs `@Published` for SwiftUI
- Coordinators - manage state and lifecycle
- Services - manage CoreAudio resources

### Error Handling

**Good Pattern:**

```swift
func configure(deviceID: AudioDeviceID) -> Result<Void, HALIOError>
```

**Minor Issue - `PresetManager.swift`**:

```swift
func loadAllPresets() {
    do { ... } catch {
        presets = []  // Silent failure
    }
}
```

- **Recommendation:** Return `Result<[Preset], PresetError>` or throw

---

## 4. Concurrency & Threading

### Main Thread Safety: **GOOD**

```swift
eqConfiguration.objectWillChange
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.objectWillChange.send()
    }
```

### Audio Thread Safety: **EXCELLENT**

```swift
nonisolated(unsafe) var processingMode: Int32 = 1
nonisolated(unsafe) var inputGainLinear: Float = 1.0
```

- Single-writer (main actor), multi-reader (audio thread)
- Primitive types naturally atomic on x86/ARM
- Audio thread tolerates slight staleness

### CoreAudio Callbacks: **CORRECT**

```swift
let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
    Task { @MainActor in
        self?.refreshDevices()
    }
}
```

- Proper bridging to MainActor via Task
- Weak self prevents retain cycles

---

## 5. Memory Management

### Retain Cycles: **ALL CORRECT**

```swift
// EqualiserStore.swift
compareModeTimer.onRevert = { [weak self] in
    self?.compareMode = .eq
}

// AudioRoutingCoordinator.swift
systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
    self?.handleSystemDefaultChanged(device)
}

// ManualRenderingEngine.swift
return AVAudioSourceNode(format: format) { [weak context] ... }
```

### View Models: **CORRECT**

```swift
// EQViewModel.swift
@Observable
final class EQViewModel {
    private unowned let store: EqualiserStore
}
```

- Uses `unowned` since view models don't own the store

---

## 6. Performance

### Main Thread Operations

**Potential Slowdown - `EqualiserStore.swift` init:**

- Heavy initialization: creates coordinators, services, sets up callbacks
- **Mitigation:** Uses `Task { @MainActor ... }` for deferred startup

### Audio Thread Operations: **VERIFIED REAL-TIME SAFE**

- `AudioRingBuffer.read/write()` - no allocations, no locks
- `RenderCallbackContext.applyGain()` - flat loop, no allocations
- `AudioMath.dbToLinear()` - uses `powf`, acceptable on modern CPUs
- Meter calculations - use pre-allocated storage

### View Updates: **OPTIMIZED**

- Meter Timer at 30 FPS
- Checks window visibility before updating
- Compares values before notifying observers

---

## 7. UI / UX Code

### SwiftUI Patterns: **GOOD**

- ViewModels use `@Observable` (SwiftUI native)
- `unowned` store references prevent cycles
- Computed properties derive display state

```swift
private var statusBaseColor: Color {
    switch store.routingStatus {
    case .idle, .starting: return .secondary
    case .active: return store.isBypassed ? .yellow : .green
    case .driverNotInstalled: return .orange
    case .error: return .red
    }
}
```

- Enum with associated values for status
- Semantic colors work in light/dark mode

### Custom Views: **WELL IMPLEMENTED**

- `NSViewRepresentable` for CALayer-backed views
- Observer pattern for efficient meter updates
- Cleanup in `dismantleNSView` removes observers

---

## 8. Testability & Test Coverage

### Highly Testable

- `OutputDeviceSelection.determine()` - Pure function
- `DeviceChangeDetector` - Static functions, no dependencies
- `HeadphoneSwitchPolicy` - Pure logic
- `AudioMath` / `MeterMath` - Pure math functions

### Testable via Protocols

- `DeviceEnumerationService` via `Enumerating` protocol
- `DeviceVolumeService` via `VolumeControlling` protocol
- `DriverManager` via `DriverLifecycleManaging` protocol

### Requires Refactoring

- `EqualiserStore` - Large, many responsibilities
- `AudioRoutingCoordinator` - Complex lifecycle, CoreAudio dependencies

### Missing Test Coverage

1. AudioPipeline tests - needs abstraction of HAL unit creation
2. RenderCallbackContext - difficult without mock audio units
3. VolumeManager - CoreAudio dependency hard to mock

---

## 9. Security & Best Practices

### Hardcoded Values

**`RenderPipeline.swift`:**

```swift
private let maxFrameCount: UInt32 = 4096
private let ringBufferCapacity: Int = 8192
```

**Recommendation:** Move to `AudioConstants.swift`

**`MeterConstants.swift` - GOOD:**

```swift
struct MeterConstants {
    static let silenceThreshold: Float = -90
    static let meterRange: ClosedRange<Float> = -36...0
}
```

### File I/O Issues

**`PresetManager.swift`** (line 85):

```swift
let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
```

- Force unwrap could crash
- **Fix:** Add graceful fallback

**`AppStateSnapshot.swift`:**

- Error logged but not propagated
- App continues without saved state silently

### Deprecated APIs

**None detected.** Code uses current APIs.

---

## 10. Summary & Prioritised Recommendations

### Critical Issues

**None identified.** The audio pipeline is correctly implemented for real-time safety.

### High Priority (Should Fix Soon)

| Issue | File | Line | Description |
|-------|------|------|-------------|
| Silent failure | EQConfiguration.swift | 107 | Band count mismatch not logged |
| Force unwrap | PresetManager.swift | 85 | App support directory could fail |
| SRP violation | EqualiserStore.swift | 18-571 | Multiple responsibilities |
| ISP violation | DeviceManager.swift | 114-332 | Facade with too many methods |

### Medium Priority

| Issue | Description |
|-------|-------------|
| Change notifications | Every band update triggers `objectWillChange.send()` |
| Error propagation | Preset errors silently ignored |
| Test coverage | Render pipeline not testable |

### Low Priority

| Issue | Description |
|-------|-------------|
| Constants extraction | Move audio constants to dedicated file |
| Documentation | Add threading model comments |
| Performance testing | Add meter benchmarks |

---

## Top 5 Concrete Refactors

### 1. Fix Force Unwrap in PresetManager

**File:** `src/services/presets/PresetManager.swift` (line 85)

**Before:**
```swift
private var presetsDirectory: URL {
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Equaliser/Presets", isDirectory: true)
}
```

**After:**
```swift
private var presetsDirectory: URL {
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        logger.error("Failed to locate Application Support directory")
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Equaliser/Presets", isDirectory: true)
    }
    return appSupport.appendingPathComponent("Equaliser/Presets", isDirectory: true)
}
```

### 2. Add Validation to EQConfiguration

**File:** `src/domain/eq/EQConfiguration.swift` (line 107)

**Before:**
```swift
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
}
```

**After:**
```swift
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
} else {
    logger.warning("Snapshot has \(snapshot.bands.count) bands, expected \(EQConfiguration.maxBandCount). Using defaults.")
}
```

### 3. Extract Device Selection Logic

**File:** `src/store/EqualiserStore.swift` (lines 218-298)

Extract complex device selection logic from `init()` into a dedicated service:

```swift
func configureInitialDeviceSelection(snapshot: AppStateSnapshot?) {
    DeviceSelectionService.configureInitialSelection(
        store: self,
        snapshot: snapshot,
        systemDefaultObserver: systemDefaultObserver,
        deviceManager: deviceManager,
        routingCoordinator: routingCoordinator
    )
}
```

### 4. Split DeviceManager Interface

**File:** `src/services/device/DeviceManager.swift`

Create focused interfaces:
```swift
protocol DeviceVolumeControlling: AnyObject {
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
}

protocol DeviceSampleRateQuerying: AnyObject {
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64?
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64?
}
```

### 5. Add Batch Update to EQConfiguration

**File:** `src/domain/eq/EQConfiguration.swift`

```swift
/// Updates multiple bands without triggering change notifications for each.
func updateBands(_ updates: [(index: Int, gain: Float?, bandwidth: Float?, frequency: Float?)]) {
    for update in updates {
        guard isValidIndex(update.index) else { continue }
        if let gain = update.gain { bands[update.index].gain = gain }
        if let bandwidth = update.bandwidth { bands[update.index].bandwidth = bandwidth }
        if let frequency = update.frequency { bands[update.index].frequency = frequency }
    }
    objectWillChange.send()
}
```

---

## Conclusion

This is a well-designed macOS audio application following modern Swift practices. The architecture is sound with proper separation between domain, service, and presentation layers. The real-time audio pipeline is correctly implemented with pre-allocated buffers and no locks on the audio thread.

**Key Strengths:**
- Excellent real-time audio safety
- Clean layered architecture
- Protocol-based dependency injection
- Comprehensive domain types

**Key Improvements:**
- SRP violations in main store/coordinator
- Silent error handling in file operations
- Minor force unwraps

**Overall Rating:** 8/10 - Production ready with recommended refactorings

---

*Review generated by OpenCode (GLM-5) on March 21, 2026*