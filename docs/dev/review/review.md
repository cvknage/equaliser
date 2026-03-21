# Comprehensive Code Review: Equaliser App

**Review Date:** March 21, 2026  
**Reviewers:** OpenCode (GLM-5) & Claude Code (GLM-5)  
**Codebase:** Swift 6, macOS 15+, Apple Silicon

---

## Executive Summary

This is a well-architected macOS menu bar audio equalizer application with professional-grade audio engineering. 
The codebase demonstrates strong adherence to Swift best practices, clean separation of concerns, and proper 
real-time audio thread safety. The architecture follows layered design with domain types, services, coordinators, 
view models, and views.

**Overall Rating:** 8/10 (Production Ready)

### Key Strengths

- **Excellent real-time audio safety** – Lock-free ring buffer, pre-allocated buffers, no allocations in render path
- **Clean layered architecture** – Domain → Services → Coordinators → ViewModels → Views
- **Protocol-based dependency injection** – Enables testability through protocols
- **Pure function domain logic** – `DeviceChangeDetector`, `HeadphoneSwitchPolicy`, `OutputDeviceSelection`
- **Swift 6 concurrency adoption** – Proper `@MainActor`, `nonisolated(unsafe)`, `Sendable` usage
- **Comprehensive memory management** – Weak self captures, unowned view model references, proper buffer cleanup

### Key Improvement Areas

- **SRP violations** in main store and coordinator classes
- **Theoretical race condition** in gain updates (P0)
- **Missing audio pipeline tests** for critical rendering path
- **Silent error handling** in file operations and initialization

---

## 1. Architecture & Design Patterns

### Overall Assessment: **Good**

#### Strengths

**Layered Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│  View Layer (SwiftUI)                                       │
│  - Renders UI components                                    │
│  - Binds to ViewModels                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Presentation Layer (ViewModels)                            │
│  - RoutingViewModel: status colors, device names            │
│  - PresetViewModel: preset list, modification state         │
│  - EQViewModel: band configuration, formatted display       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Coordination Layer                                         │
│  - EqualiserStore: thin coordinator                         │
│  - AudioRoutingCoordinator: device selection, pipeline      │
│  - DeviceChangeCoordinator: device events, history          │
│  - VolumeManager: driver ↔ output volume sync               │
│  - CompareModeTimer: auto-revert timer                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Service Layer (via Protocols)                              │
│  - DeviceEnumerationService: device enumeration, events     │
│  - DeviceVolumeService: volume control                      │
│  - DriverManager: driver lifecycle                          │
│  - PresetManager: preset file management                    │
│  - MeterStore: 30 FPS meter updates                         │
└─────────────────────────────────────────────────────────────┘
```

**Protocol-Based DI:**

```swift
protocol Enumerating: ObservableObject { ... }
protocol VolumeControlling: AnyObject { ... }
protocol SampleRateObserving: AnyObject { ... }
protocol DriverLifecycleManaging: ObservableObject { ... }
```

**Pure Function Domain:**

```swift
enum HeadphoneSwitchPolicy {
    static func shouldSwitch(...) -> Bool { ... }
}

enum OutputDeviceSelection {
    static func determine(...) -> OutputDeviceSelection { ... }
}
```

#### SRP Violations

**Issue 1.1: EqualiserStore Multiple Responsibilities**

| Location | Description |
|----------|-------------|
| `EqualiserStore.swift:18-571` | Acts as both coordinator AND state container |

Responsibilities include:
- EQ band control
- Preset management delegation
- Device selection delegation
- Snapshot persistence
- Routing status forwarding

**Recommendation:** Extract concerns into focused services.

---

**Issue 1.2: AudioRoutingCoordinator Too Large**

| Location | Lines |
|----------|-------|
| `AudioRoutingCoordinator.swift` | 740 lines |

Handles:
- Device selection
- Sample rate sync
- Driver naming (complex logic lines 650-739)
- Headphone detection callbacks
- Pipeline lifecycle
- Volume sync setup

**Recommendation:** Extract `DriverNameManager` for naming logic (lines 650-739).

---

#### ISP Violation

**Issue 1.3: DeviceManager Facade Too Broad**

| Location | Description |
|----------|-------------|
| `DeviceManager.swift:114-332` | Protocol `Enumerating` is thin while class has 25+ methods |

**Recommendation:** Split into focused interfaces:
- `DeviceEnumerating` (device lists)
- `DeviceVolumeControlling`
- `DeviceSampleRateQuerying`

---

#### Hidden Singleton Dependency

**Issue 1.4: DriverManager Singleton Access**

| Location | Description |
|----------|-------------|
| `AudioRoutingCoordinator.swift:155-156` | Direct `DriverManager.shared` access |

```swift
guard DriverManager.shared.isReady else {
    routingStatus = .driverNotInstalled
}
```

Creates hidden singleton dependency making testing difficult.

**Recommendation:** Create `DriverAccessing` protocol and inject:

```swift
protocol DriverAccessing {
    var isReady: Bool { get }
    var deviceID: AudioDeviceID? { get }
    func setDeviceName(_ name: String) -> Bool
}

init(driverManager: DriverAccessing = DriverManager.shared, ...)
```

---

## 2. Audio Engine & DSP Logic

### Overall Assessment: **Excellent (with one theoretical issue)**

#### Strengths

**Dual HAL Architecture:** Correct use of separate HAL units with ring buffer for clock drift:

```
┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│ Input Device │ ──▶ │  Input HAL   │ ──▶ │ Input Callback│
└──────────────┘     └──────────────┘     └───────────────┘
                                                  │
                                                  ▼
                                          ┌──────────────┐
                                          │  Ring Buffer │
                                          └──────────────┘
                                                  │
                                                  ▼
┌──────────────┐     ┌──────────────┐     ┌────────────────────┐
│ Output Device│ ◀── │  Output HAL  │ ◀── │ Output Callback    │
└──────────────┘     └──────────────┘     │ + Manual Rendering │
                                           │ + EQ (64 bands)    │
                                           └────────────────────┘
```

**Lock-Free Ring Buffer:**

```swift
@inline(__always)
func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex...)
    // ... lock-free implementation
}
```

**Pre-Allocation:** All buffers allocated once during init, no allocations in render path.

**Correct Processing Mode Logic:**

```swift
// Boost is ALWAYS applied (not inside bypass check)
context.applyGain(to: context.inputSampleBuffers, ...)

// Input gain is skipped in bypass mode
if context.processingMode != 0 {
    context.applyGain(...)
}
```

#### Critical Issues

**Issue 2.1: Gain Race Condition (P0)**

| Location | Lines | Impact |
|----------|-------|--------|
| `RenderCallbackContext.swift` | 56-81 | Audio artifacts, theoretical crashes |

```swift
nonisolated(unsafe) var inputGainLinear: Float = 1.0
nonisolated(unsafe) var targetInputGainLinear: Float = 1.0
nonisolated(unsafe) var outputGainLinear: Float = 1.0
nonisolated(unsafe) var targetOutputGainLinear: Float = 1.0
nonisolated(unsafe) var boostGainLinear: Float = 1.0
nonisolated(unsafe) var targetBoostGainLinear: Float = 1.0
```

While comments indicate single-writer/single-reader, the gain ramping in `applyGain()` (lines 244-271) writes to `currentGain` while it's being read. This is technically a race condition, though benign in practice since floats are atomic on x86/ARM.

**Recommendation:**

```swift
import Atomics

final class RenderCallbackContext: @unchecked Sendable {
    let targetInputGainLinear: ManagedAtomic<Float> = ManagedAtomic(1.0)
    nonisolated(unsafe) var inputGainLinear: Float = 1.0  // Only audio thread writes

    func updateTargetInputGain(_ value: Float) {
        targetInputGainLinear.store(value, ordering: .relaxed)
    }
}
```

---

**Issue 2.2: Deprecated Atomic APIs**

| Location | Lines |
|----------|-------|
| `AudioRingBuffer.swift` | 103-104 |

`OSAtomicAdd64Barrier` is deprecated. Modern Swift should use `os_unfair_lock`, `DispatchQueue`, or the Swift Atomics package.

---

**Issue 2.3: Hardcoded Ring Buffer Size**

| Location | Lines |
|----------|-------|
| `RenderPipeline.swift` | 65 |

```swift
private let ringBufferCapacity: Int = 8192
```

Capacity hardcoded to 8192 samples (~85ms at 96kHz). Should be configurable.

---

**Issue 2.4: Potential Buffer Overrun**

| Location | Lines |
|----------|-------|
| `RenderCallbackContext.swift` | 348-385 |

If `frameCount` ever exceeds `framesPerBuffer`, buffer overrun could occur. Should add assertion:

```swift
precondition(frameCount <= framesPerBuffer, "Frame count exceeds buffer capacity")
```

---

## 3. Swift Code Quality

### Overall Assessment: **Strong**

#### Strengths

| Pattern | Usage |
|---------|-------|
| `@MainActor` | UI-bound classes (coordinators, view models) |
| `actor` | `ParameterSmoother` for thread-safe state |
| `nonisolated(unsafe)` | Audio thread state access |
| `Sendable` | Domain types for cross-thread safety |
| `@Observable` | SwiftUI view model binding |
| `unowned` | View model store references |

**Error Handling:** Extensive use of `Result<Success, Error>`:

```swift
func configure(deviceID: AudioDeviceID) -> Result<Void, HALIOError>
```

**Naming:** Follows project guidelines consistently (British English: "equaliser", "behaviour").

#### Issues

**Issue 3.1: Silent Failure in EQConfiguration**

| Location | Lines |
|----------|-------|
| `EQConfiguration.swift` | 107 |

```swift
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
}
```

Silent failure if band count doesn't match.

**Fix:**

```swift
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
} else {
    logger.warning("Snapshot has \(snapshot.bands.count) bands, expected \(EQConfiguration.maxBandCount)")
}
```

---

**Issue 3.2: Force Unwrap in PresetManager**

| Location | Lines |
|----------|-------|
| `PresetManager.swift` | 85 |

```swift
let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
```

Force unwrap could crash.

**Fix:**

```swift
guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
    logger.error("Failed to locate Application Support directory")
    return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Equaliser/Presets", isDirectory: true)
}
```

---

**Issue 3.3: Redundant Change Notification**

| Location | Lines |
|----------|-------|
| `EQConfiguration.swift` | 229 |

```swift
func updateBandGain(index: Int, gain: Float) {
    bands[index].gain = gain
    objectWillChange.send()  // Redundant - @Published already does this
}
```

Since `bands` is `@Published`, the manual notification is redundant.

---

**Issue 3.4: Manual Codable Implementation**

| Location | Lines |
|----------|-------|
| `EQBandConfiguration.swift` | 23-40 |

Could use synthesized conformance since Swift 5.5.

---

## 4. Concurrency & Threading

### Overall Assessment: **Good**

#### Strengths

**Main Thread Isolation:** All `@MainActor` classes properly annotate their methods.

**Weak Self Captures:** All callbacks use `[weak self]`:

```swift
systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
    self?.handleSystemDefaultChanged(device)
}
```

**CoreAudio Callback Bridging:**

```swift
let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
    Task { @MainActor in
        self?.refreshDevices()
    }
}
```

#### Issues

**Issue 4.1: DispatchQueue vs Task**

| Location | Lines |
|----------|-------|
| `AudioRoutingCoordinator.swift` | 535-538 |

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
    self?.reconfigureRouting()
}
```

Should use `Task` for consistency:

```swift
Task { @MainActor [weak self] in
    try? await Task.sleep(nanoseconds: 100_000_000)
    self?.reconfigureRouting()
}
```

---

**Issue 4.2: Main Thread Meter Processing**

| Location | Lines |
|----------|-------|
| `MeterStore.swift` | 139-143 |

Meter calculations run on main thread at 30 FPS. Consider background processing:

```swift
private let processingQueue = DispatchQueue(
    label: "net.knage.equaliser.meter.processing",
    qos: .userInteractive
)
```

---

## 5. Memory Management

### Overall Assessment: **Excellent**

#### Strengths

- All callbacks use `[weak self]`
- View models use `unowned` store references
- `RenderCallbackContext` properly deinitializes all buffers
- No retain cycles identified

#### Minor Issues

**Issue 5.1: Unnecessary Weak Capture**

| Location | Lines |
|----------|-------|
| `ManualRenderingEngine.swift` | 181 |

The `[weak context]` in `AVAudioSourceNode` is unnecessary (context owned by pipeline which owns engine), though harmless.

---

## 6. Performance

### Overall Assessment: **Good**

#### Strengths

- Pre-allocated buffers (no allocations in render path)
- Lock-free ring buffer
- Efficient meter calculation (single-pass peak/RMS)
- Observer pattern for meters avoids unnecessary redraws

#### Issues

**Issue 6.1: Array Allocation on Device Change**

| Location | Description |
|----------|-------------|
| `DeviceEnumerationService.refreshDevices()` | New arrays allocated on every device change |

Consider caching and delta updates.

---

## 7. UI / UX Code

### Overall Assessment: **Good**

#### Strengths

- Views use `@Observable` macro
- Proper window lifecycle management
- Custom `NSView` with `CALayer` for meters
- Window visibility tracking for meter updates

#### Issues

**Issue 7.1: View Model Recreation**

| Location | Lines |
|----------|-------|
| `EQWindowView.swift` | 11-18 |

```swift
private var routingViewModel: RoutingViewModel {
    RoutingViewModel(store: store)  // Creates new instance each access
}
```

**Fix:**

```swift
@State private var routingViewModel: RoutingViewModel?

private func getRoutingViewModel() -> RoutingViewModel {
    if let vm = routingViewModel { return vm }
    let vm = RoutingViewModel(store: store)
    routingViewModel = vm
    return vm
}
```

---

## 8. Testability & Test Coverage

### Overall Assessment: **Needs Improvement**

#### Strengths

- Pure function domain logic trivially testable
- Protocol-based DI enables mock implementations
- Test organization mirrors source structure

#### Critical Gap

**Issue 8.1: Missing Audio Pipeline Tests (High)**

The critical audio path has minimal coverage:
- `RenderPipeline` – No tests
- `HALIOManager` – No tests
- `ManualRenderingEngine` – No tests

Only `AudioRingBufferTests.swift` exists.

**Recommended Tests:**

```swift
func testRingBufferWriteReadRoundTrip()
func testRingBufferUnderrunReturnsZero()
func testRingBufferOverflowDropsSamples()
func testRenderPipelineFormatValidation()
func testHALIOManagerInputOnlyMode()
func testHALIOManagerOutputOnlyMode()
```

**Issue 8.2: Minimal Mock Implementations**

Only `MockCompareModeTimer` and `MockSystemDefaultObserver` exist. Missing:
- `MockDeviceEnumerationService`
- `MockVolumeService`
- `MockDriverManager`

**Issue 8.3: No Integration Tests**

No tests verify full audio pipeline end-to-end.

---

## 9. Security & Best Practices

### Overall Assessment: **Good**

#### Strengths

- No hardcoded secrets
- Proper entitlements (minimal)
- Gain clamping prevents extreme values
- All CoreAudio status codes checked

#### Issues

**Issue 9.1: No Preset Import Validation**

| Location | Description |
|----------|-------------|
| `EasyEffectsImporter.swift` | Malformed JSON could crash |

Should validate:
- Band count within limits
- Frequency within valid range
- Bandwidth within valid range
- Gain within valid range

**Issue 9.2: UserDefaults for State**

State persisted to `UserDefaults` without encryption. For sensitive settings, consider `Keychain`.

---

## 10. Prioritized Recommendations

### Critical (P0) – Fix Immediately

| Issue | Location | Impact |
|-------|----------|--------|
| Gain race condition | `RenderCallbackContext.swift:56-81` | Audio artifacts, potential crashes |

### High Priority (P1) – Fix Soon

| Issue | Location | Impact |
|-------|----------|--------|
| Missing audio pipeline tests | `tests/services/audio/` | Regression risk, hard to refactor |
| Silent failures | `EQConfiguration.swift:107`, `PresetManager.swift:85` | Hidden bugs |
| Singleton dependency | `AudioRoutingCoordinator.swift:155` | Testing difficulty |
| SRP violation | `EqualiserStore.swift` | Maintainability |
| ISP violation | `DeviceManager.swift` | Interface design |

### Medium Priority (P2) – Fix When Possible

| Issue | Location | Impact |
|-------|----------|--------|
| Deprecated atomic APIs | `AudioRingBuffer.swift` | Future compatibility |
| Large coordinator class | `AudioRoutingCoordinator.swift` | Maintainability |
| Main thread meter processing | `MeterStore.swift` | UI responsiveness |
| Buffer overrun potential | `RenderCallbackContext.swift` | Edge case safety |
| View model recreation | `EQWindowView.swift` | Minor performance |

### Low Priority (P3) – Nice to Have

| Issue | Location | Impact |
|-------|----------|--------|
| Hardcoded ring buffer size | `RenderPipeline.swift:65` | Flexibility |
| Manual Codable implementation | `EQBandConfiguration.swift` | Code reduction |
| Device enumeration allocation | `DeviceEnumerationService.swift` | Minor performance |
| Preset import validation | `EasyEffectsImporter.swift` | Edge case robustness |
| Constants extraction | Move to `AudioConstants.swift` | Organization |
| Documentation | Add threading model comments | Maintainability |

---

## Top 5 Concrete Fixes

### 1. Fix Gain Race Condition (P0)

**File:** `RenderCallbackContext.swift`

```swift
// Before (lines 56-81):
nonisolated(unsafe) var inputGainLinear: Float = 1.0
nonisolated(unsafe) var targetInputGainLinear: Float = 1.0

// After: Use atomic operations
import Atomics

final class RenderCallbackContext: @unchecked Sendable {
    let targetInputGainLinear: ManagedAtomic<Float> = ManagedAtomic(1.0)
    nonisolated(unsafe) var inputGainLinear: Float = 1.0

    func updateTargetInputGain(_ value: Float) {
        targetInputGainLinear.store(value, ordering: .relaxed)
    }
}
```

---

### 2. Add Ring Buffer Tests (P1)

**File:** `tests/services/audio/AudioRingBufferTests.swift`

```swift
func testWriteReadRoundTrip() {
    let buffer = AudioRingBuffer(capacity: 1024)
    let samples: [Float] = (0..<512).map { Float($0) }

    let written = buffer.write(samples, count: 512)
    XCTAssertEqual(written, 512)

    var output = [Float](repeating: 0, count: 512)
    let read = buffer.read(into: &output, count: 512)
    XCTAssertEqual(read, 512)
    XCTAssertEqual(output, samples)
}

func testUnderrunReturnsZero() {
    let buffer = AudioRingBuffer(capacity: 1024)
    var output = [Float](repeating: 1, count: 512)

    let read = buffer.read(into: &output, count: 512)
    XCTAssertEqual(read, 0)
    XCTAssertEqual(output, [Float](repeating: 0, count: 512))
}

func testOverflowDropsSamples() {
    let buffer = AudioRingBuffer(capacity: 128)
    let samples: [Float] = (0..<256).map { Float($0) }

    let written = buffer.write(samples, count: 256)
    XCTAssertLessThan(written, 256)
    XCTAssertGreaterThan(buffer.getOverflowCount(), 0)
}
```

---

### 3. Fix Force Unwrap in PresetManager (P1)

**File:** `src/services/presets/PresetManager.swift`

```swift
// Before:
private var presetsDirectory: URL {
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Equaliser/Presets", isDirectory: true)
}

// After:
private var presetsDirectory: URL {
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        logger.error("Failed to locate Application Support directory")
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Equaliser/Presets", isDirectory: true)
    }
    return appSupport.appendingPathComponent("Equaliser/Presets", isDirectory: true)
}
```

---

### 4. Add Validation to EQConfiguration (P1)

**File:** `src/domain/eq/EQConfiguration.swift`

```swift
// Before:
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
}

// After:
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
} else {
    logger.warning("Snapshot has \(snapshot.bands.count) bands, expected \(EQConfiguration.maxBandCount). Using defaults.")
}
```

---

### 5. Inject DriverManager Dependency (P1)

**File:** `src/services/driver/protocols/DriverAccessing.swift` (new file)

```swift
protocol DriverAccessing {
    var isReady: Bool { get }
    var deviceID: AudioDeviceID? { get }
    func setDeviceName(_ name: String) -> Bool
    func setDriverSampleRate(matching rate: Float64) -> Float64?
    static var shared: DriverAccessing { get }
}
```

**File:** `src/store/coordinators/AudioRoutingCoordinator.swift`

```swift
init(
    driverManager: DriverAccessing = DriverManager.shared,
    // ...
) {
    self.driverManager = driverManager
    // ...
}
```

---

## Conclusion

This codebase demonstrates professional-grade Swift audio programming with:

### Key Strengths
- **Excellent real-time audio safety** – Lock-free ring buffer, pre-allocated buffers, no allocations in render path
- **Clean layered architecture** – Domain → Services → Coordinators → ViewModels → Views
- **Protocol-based dependency injection** – Enables testability
- **Comprehensive domain types** – Pure functions for complex business logic
- **Swift 6 concurrency adoption** – Proper actor isolation, Sendable conformance

### Key Improvements Needed
- **Fix gain race condition** – Theoretical but should be addressed
- **Add audio pipeline tests** – Critical path lacks coverage
- **Resolve SRP violations** – Large classes should be split
- **Improve error propagation** – Silent failures hide bugs
- **Inject singleton dependencies** – Better testability

**Overall Rating:** 8/10 – Production ready with recommended refactorings

---

*Review synthesized from OpenCode (GLM-5) and Claude (Opus 4.6) reviews on March 21, 2026*
