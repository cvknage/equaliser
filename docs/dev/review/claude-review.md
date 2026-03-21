# Comprehensive Code Review: Equaliser App

**Review Date:** 2026-03-21
**Reviewer:** Claude Code (GLM-5)
**Codebase:** Swift 6, macOS 15+, Apple Silicon

---

## Executive Summary

This is a well-architected macOS menu bar equalizer application with professional-grade audio engineering. The codebase demonstrates strong adherence to Swift best practices, clean separation of concerns, and proper real-time audio thread safety. The main areas for improvement are test coverage for the audio pipeline and addressing theoretical race conditions in gain updates.

**Overall Rating: 8.5/10**

---

## 1. Architecture & Design Patterns

### ✅ Strengths

**Layered Architecture**: The app follows a clean, well-defined layered architecture:

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
│  - EQViewModel: band configuration, formatted display        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Coordination Layer                                         │
│  - EqualiserStore: thin coordinator                         │
│  - AudioRoutingCoordinator: device selection, pipeline      │
│  - DeviceChangeCoordinator: device events, history          │
│  - VolumeManager: driver ↔ output volume sync               │
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

**Coordinator Pattern**: `EqualiserStore` is a thin coordinator that delegates to specialized coordinators:

| Coordinator | Responsibility |
|-------------|---------------|
| `AudioRoutingCoordinator` | Device selection, pipeline lifecycle |
| `DeviceChangeCoordinator` | Device events, headphone detection |
| `VolumeManager` | Volume sync between driver and output device |
| `CompareModeTimer` | Auto-revert timer for compare mode |

**Protocol-Based DI**: All services are accessed via protocols for testability:

```swift
// Examples from src/services/device/protocols/
protocol Enumerating: ObservableObject { ... }
protocol VolumeControlling: AnyObject { ... }
protocol SampleRateObserving: AnyObject { ... }
protocol DriverLifecycleManaging: ObservableObject { ... }
```

**Pure Function Domain**: Domain logic uses pure functions in enums:

```swift
// src/domain/device/HeadphoneSwitchPolicy.swift
enum HeadphoneSwitchPolicy {
    static func shouldSwitch(...) -> Bool { ... }
}

// src/domain/device/OutputDeviceHistory.swift
enum OutputDeviceSelection {
    static func determine(...) -> OutputDeviceSelection { ... }
}
```

### ⚠️ Issues

#### Issue 1.1: Singleton Dependency (Medium)

**Location:** `AudioRoutingCoordinator.swift:155-156`

```swift
guard DriverManager.shared.isReady else {
    routingStatus = .driverNotInstalled
    ...
}
```

`DriverManager.shared` is accessed directly instead of through a protocol, creating a hidden singleton dependency that makes testing difficult.

**Recommendation:** Create a `DriverAccessing` protocol and inject it:

```swift
protocol DriverAccessing {
    var isReady: Bool { get }
    var deviceID: AudioDeviceID? { get }
    func setDeviceName(_ name: String) -> Bool
    // ...
}

// In AudioRoutingCoordinator init:
init(driverManager: DriverAccessing = DriverManager.shared, ...)
```

#### Issue 1.2: Large Coordinator Class (Medium)

**Location:** `AudioRoutingCoordinator.swift` (740 lines)

The coordinator handles too many responsibilities:
- Device selection
- Pipeline lifecycle
- Sample rate sync
- Driver name management
- System default observation
- Volume sync setup

**Recommendation:** Extract driver name management into a separate `DriverNameCoordinator`.

---

## 2. Audio Engine & DSP Logic

### ✅ Strengths

**Dual HAL Architecture**: Correct use of separate HAL units for input and output with a ring buffer for clock drift handling:

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

**Real-Time Safe Callbacks**: Audio callbacks in `RenderPipeline.swift:477-616` are properly designed:
- Static functions to avoid actor isolation
- `nonisolated(unsafe)` for audio thread state
- No allocations in render path
- Pre-allocated buffers in `RenderCallbackContext`

**Lock-Free Ring Buffer**: `AudioRingBuffer.swift` uses atomic operations for thread-safe SPSC communication:

```swift
@inline(__always)
func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    // ... lock-free write
}
```

**Correct Sample Rate Handling**: Driver sample rate syncs to output device:

```swift
// AudioRoutingCoordinator.swift:494-511
private func syncDriverSampleRate(to outputDeviceID: AudioDeviceID) {
    let outputRate = sampleRateService.getActualSampleRate(deviceID: outputDeviceID)
        ?? sampleRateService.getNominalSampleRate(deviceID: outputDeviceID)
    guard let targetRate = outputRate else { ... }
    guard let setRate = DriverManager.shared.setDriverSampleRate(matching: targetRate) else { ... }
}
```

### ⚠️ Issues

#### Issue 2.1: Gain Race Condition (High)

**Location:** `RenderCallbackContext.swift:56-81`

```swift
nonisolated(unsafe) var inputGainLinear: Float = 1.0
nonisolated(unsafe) var targetInputGainLinear: Float = 1.0
nonisolated(unsafe) var outputGainLinear: Float = 1.0
nonisolated(unsafe) var targetOutputGainLinear: Float = 1.0
nonisolated(unsafe) var boostGainLinear: Float = 1.0
nonisolated(unsafe) var targetBoostGainLinear: Float = 1.0
```

While comments state "single-writer/single-reader", the gain ramping in `applyGain()` (lines 244-271) writes to `currentGain` while it's being read. This is technically a race condition, though benign in practice since floats are atomic on x86/ARM.

**Recommendation:** Use proper atomic operations:

```swift
// Option 1: Use OSAtomicCompareAndSwap for target gains
private var targetInputGainLinear: Atomic<Float> = Atomic(1.0)

// Option 2: Use a simple lock-free queue for gain updates
```

#### Issue 2.2: Deprecated Atomic APIs (Medium)

**Location:** `AudioRingBuffer.swift:103-104`

```swift
let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
```

`OSAtomicAdd64Barrier` is deprecated. Modern Swift should use `os_unfair_lock`, `DispatchQueue`, or the Swift Atomics package.

**Recommendation:**

```swift
import Atomics

// Or use ManagedAtomic from Swift Atomics package
private let writeIndex = ManagedAtomic<Int>(0)
```

#### Issue 2.3: Hardcoded Ring Buffer Size (Low)

**Location:** `RenderPipeline.swift:65`

```swift
private let ringBufferCapacity: Int = 8192
```

Capacity is hardcoded to 8192 samples (~85ms at 96kHz). Should be configurable for different latency requirements.

---

## 3. Swift Code Quality

### ✅ Strengths

**Swift 6 Concurrency**: Excellent use of modern concurrency:

| Pattern | Usage |
|---------|-------|
| `@MainActor` | UI-bound classes (coordinators, view models) |
| `actor` | `ParameterSmoother` for thread-safe state |
| `nonisolated(unsafe)` | Audio thread state access |
| `Sendable` | Domain types for cross-thread safety |

**Proper Value Types**: Domain models use `struct` or `enum` with `Codable`:

```swift
struct AudioDevice: Identifiable, Equatable { ... }
struct EQBandConfiguration: Codable, Sendable { ... }
enum DeviceChangeEvent: Sendable { ... }
```

**Error Handling**: Extensive use of `Result<Success, Error>`:

```swift
// HALIOManager.swift
func configure(deviceID: AudioDeviceID) -> Result<Void, HALIOError>
func start() -> Result<Void, HALIOError>
```

**Naming Conventions**: Follows project guidelines consistently:
- Types/Protocols: `UpperCamelCase` (`AudioDevice`, `VolumeControlling`)
- Functions/Methods: `lowerCamelCase` (`refreshDevices()`, `start()`)
- Enum cases: `lowerCamelCase` (`.parametric`, `.bypass`)
- British English: "equaliser", "behaviour", "optimised"

### ⚠️ Issues

#### Issue 3.1: Redundant Change Notification (Low)

**Location:** `EQConfiguration.swift:229`

```swift
func updateBandGain(index: Int, gain: Float) {
    guard isValidIndex(index) else { return }
    bands[index].gain = gain
    objectWillChange.send()  // Redundant - @Published already does this
}
```

Since `bands` is `@Published`, SwiftUI already observes changes. The manual `objectWillChange.send()` is redundant.

#### Issue 3.2: Manual Codable Implementation (Low)

**Location:** `EQBandConfiguration.swift:23-40`

Manual `Codable` implementation could use synthesized conformance since Swift 5.5:

```swift
// Current: Manual implementation
init(from decoder: Decoder) throws { ... }
func encode(to encoder: Encoder) throws { ... }

// Could be simplified to:
struct EQBandConfiguration: Codable, Sendable {
    var frequency: Float
    var bandwidth: Float
    var gain: Float
    var filterType: AVAudioUnitEQFilterType
    var bypass: Bool
}
```

---

## 4. Concurrency & Threading

### ✅ Strengths

**Proper Main Thread Isolation**: All `@MainActor` classes properly annotate their methods:

```swift
@MainActor
final class AudioRoutingCoordinator: ObservableObject {
    func reconfigureRouting() { ... }  // Implicitly @MainActor
}
```

**Weak Self Captures**: All callbacks use `[weak self]`:

```swift
// AudioRoutingCoordinator.swift:64-66
systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
    self?.handleSystemDefaultChanged(device)
}
```

**Unowned View Models**: View models correctly use `unowned` since they have the same lifetime as the store:

```swift
// EQViewModel.swift:12
private unowned let store: EqualiserStore
```

**Combine Integration**: Device changes use Combine publishers properly:

```swift
// DeviceEnumerationService.swift:137-143
deviceEnumerator.$changeEvent
    .compactMap { $0 }
    .receive(on: DispatchQueue.main)
    .sink { [weak self] event in ... }
```

### ⚠️ Issues

#### Issue 4.1: CoreAudio Callback Dispatch (Medium)

**Location:** `DeviceEnumerationService.swift:75-78`

```swift
let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
    Task { @MainActor in
        self?.refreshDevices()
    }
}
```

If `self` is deallocated between the CoreAudio callback and the `Task` execution, `refreshDevices()` never runs. This is acceptable behavior, but the pattern should be documented.

#### Issue 4.2: DispatchQueue vs Task (Medium)

**Location:** `AudioRoutingCoordinator.swift:535-538`

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
    self?.reconfigureRouting()
}
```

Should use `Task` for consistency with Swift concurrency:

```swift
Task { @MainActor [weak self] in
    try? await Task.sleep(nanoseconds: 100_000_000)
    self?.reconfigureRouting()
}
```

#### Issue 4.3: Main Thread Meter Processing (Low)

**Location:** `MeterStore.swift:139-143`

```swift
meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        self?.refreshMeterSnapshot()
    }
```

Meter calculations run on main thread at 30 FPS. Consider background processing:

```swift
private let processingQueue = DispatchQueue(
    label: "net.knage.equaliser.meter.processing",
    qos: .userInteractive
)
```

---

## 5. Memory Management

### ✅ Strengths

**Weak References in Callbacks**: All closures correctly capture `self` weakly:

```swift
// AudioRoutingCoordinator.swift
volumeManager?.onBoostGainChanged = { [weak self] boostGain in
    self?.renderPipeline?.updateBoostGain(linear: boostGain)
}
```

**Proper Buffer Cleanup**: `RenderCallbackContext` deinitializes all allocated buffers:

```swift
deinit {
    for buffer in inputBuffers {
        buffer.deinitialize(count: framesPerBuffer)
        buffer.deallocate()
    }
    // ... cleanup for all buffers
}
```

**Unowned for View Models**: View models use `unowned` references to avoid retain cycles:

```swift
@MainActor
@Observable
final class EQViewModel {
    private unowned let store: EqualiserStore
}
```

### ⚠️ Issues

#### Issue 5.1: Unnecessary Weak Capture (Low)

**Location:** `ManualRenderingEngine.swift:181`

```swift
return AVAudioSourceNode(format: format) { [weak context] _, _, frameCount, audioBufferList -> OSStatus in
    guard let ctx = context else {
        zeroFillBufferList(audioBufferList, frameCount: frameCount)
        return noErr
    }
    // ...
}
```

The `context` is owned by `RenderPipeline` which also owns the engine, so the weak reference is unnecessary (though harmless).

#### Issue 5.2: Potential Buffer Overrun (Medium)

**Location:** `RenderCallbackContext.swift:348-385`

```swift
private func updateMeterStorage(...) {
    for channel in 0..<meterChannelCount {
        guard !channels.isEmpty else { ... }
        let sourceIndex = min(channel, channels.count - 1)  // Good bounds check
        let buffer = channels[sourceIndex]
        // ... but frame access assumes frameCount <= framesPerBuffer
        while frame < frameCount {
            let sample = abs(buffer[frame])  // No bounds check
            // ...
        }
    }
}
```

If `frameCount` ever exceeds `framesPerBuffer`, this could cause buffer overrun. Should add assertion or bounds check.

---

## 6. Performance

### ✅ Strengths

**Pre-Allocation**: Audio buffers are allocated once during initialization:

```swift
// RenderCallbackContext init
for _ in 0..<channelCount {
    let buffer = UnsafeMutablePointer<Float>.allocate(capacity: framesPerBuffer)
    buffer.initialize(repeating: 0, count: framesPerBuffer)
    inputBufs.append(buffer)
}
```

**No Locks in Audio Path**: Ring buffer uses lock-free atomics, no mutex in render callbacks.

**Efficient Meter Calculation**: Peak/RMS in single pass:

```swift
var peak: Float = 0
var sumSquares: Float = 0
while frame < frameCount {
    let sample = abs(buffer[frame])
    peak = max(peak, sample)
    sumSquares += sample * sample
    frame += 1
}
```

**Observer Pattern for Meters**: `MeterStore` uses weak observer pattern to avoid SwiftUI redraws:

```swift
func addObserver(_ observer: MeterObserver, for type: MeterType) {
    observerQueue.sync {
        observers[type]?.append(WeakMeterObserver(observer: observer))
    }
}
```

### ⚠️ Issues

#### Issue 6.1: Main Thread Meter Processing (Medium)

Same as Issue 4.3 - meter processing happens on main thread at 30 FPS.

#### Issue 6.2: Array Allocation on Device Change (Low)

**Location:** `DeviceEnumerationService.refreshDevices()`

```swift
var inputs: [AudioDevice] = []
var outputs: [AudioDevice] = []
for deviceID in deviceIDs {
    if let device = makeDevice(from: deviceID) { ... }
}
```

New arrays allocated on every device change. Consider caching and using delta updates.

---

## 7. UI / UX Code

### ✅ Strengths

**SwiftUI Best Practices**: Views use `@Observable` macro, proper `@EnvironmentObject`:

```swift
// EQWindowView.swift
@EnvironmentObject var store: EqualiserStore
@State private var showCompareHelp = false
@State private var metersEnabledUI = false
```

**Window Lifecycle Management**: Proper handling of window visibility:

```swift
.onAppear { store.meterStore.windowBecameVisible() }
.onDisappear { store.meterStore.windowBecameHidden() }
```

**Efficient Meter Rendering**: Custom `NSView` with `CALayer` for meters avoids SwiftUI redraw overhead.

### ⚠️ Issues

#### Issue 7.1: View Model Recreation (Low)

**Location:** `EQWindowView.swift:11-18`

```swift
private var routingViewModel: RoutingViewModel {
    RoutingViewModel(store: store)  // Creates new instance each access
}
private var eqViewModel: EQViewModel {
    EQViewModel(store: store)
}
```

Should cache view models:

```swift
@State private var routingViewModel: RoutingViewModel?
@State private var eqViewModel: EQViewModel?

var body: some View {
    let routingVM = routingViewModel ?? RoutingViewModel(store: store)
    // ...
}
```

#### Issue 7.2: WindowAccessor Pattern (Low)

The `WindowAccessor` pattern for setting window reference is awkward. Consider using `NSViewRepresentable` with proper lifecycle or a coordinator pattern.

---

## 8. Testability & Test Coverage

### ✅ Strengths

**Protocol-Based DI**: Enables mock implementations:

```swift
protocol VolumeControlling: AnyObject {
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
}
```

**Pure Function Testing**: Domain logic is trivially testable:

```swift
// EqualiserStoreTests.swift
func testDetermineAutomaticOutputDevice_preservesValidSelection() {
    let result = OutputDeviceSelection.determine(
        currentSelected: "airpods",
        macDefault: DRIVER_DEVICE_UID,
        availableDevices: devices
    )
    XCTAssertEqual(result, .preserveCurrent("airpods"))
}
```

**Test Organization**: Tests mirror source structure:
- `tests/domain/` - Domain type tests
- `tests/services/` - Service layer tests
- `tests/store/` - Coordinator tests
- `tests/viewmodels/` - View model tests
- `tests/mocks/` - Mock implementations

### ⚠️ Issues

#### Issue 8.1: Missing Audio Pipeline Tests (High)

**Location:** `tests/services/audio/`

The critical audio path has minimal test coverage:
- `RenderPipeline` - No tests
- `HALIOManager` - No tests
- `ManualRenderingEngine` - No tests

Only `AudioRingBufferTests.swift` exists.

**Recommendation:** Add tests for:

```swift
// Recommended tests
func testRingBufferWriteReadRoundTrip()
func testRingBufferUnderrunReturnsZero()
func testRingBufferOverflowDropsSamples()
func testRenderPipelineFormatValidation()
func testHALIOManagerInputOnlyMode()
func testHALIOManagerOutputOnlyMode()
```

#### Issue 8.2: Minimal Mock Implementations (Medium)

**Location:** `tests/mocks/`

Only `MockCompareModeTimer` and `MockSystemDefaultObserver` exist. Missing mocks for:
- `MockDeviceEnumerationService`
- `MockVolumeService`
- `MockDriverManager`

#### Issue 8.3: No Integration Tests (Medium)

No tests verify the full audio pipeline works end-to-end. Even a simple "start/stop pipeline without crash" test would be valuable.

---

## 9. Security & Best Practices

### ✅ Strengths

**No Hardcoded Secrets**: No API keys, passwords, or credentials in code.

**Proper Entitlements**: Only requests necessary entitlements:
- `com.apple.security.device.audio-input` (audio routing)
- `com.apple.security.files.user-selected.read-write` (presets)

**Input Validation**: Gain clamping prevents extreme values:

```swift
// EqualiserStore.swift:568-570
static func clampGain(_ gain: Float) -> Float {
    min(max(gain, gainRange.lowerBound), gainRange.upperBound)
}
```

**Safe CoreAudio Patterns**: All CoreAudio status codes checked:

```swift
guard AudioObjectGetPropertyData(...) == noErr else {
    return .failure(.formatQueryFailed(status))
}
```

### ⚠️ Issues

#### Issue 9.1: No Preset Import Validation (Low)

**Location:** `EasyEffectsImporter.swift`

Malformed JSON could crash the app:

```swift
guard let bands = try? decoder.decode([EQBandConfiguration].self, from: data) else { ... }
// Should also validate:
// - Band count within limits
// - Frequency within valid range
// - Bandwidth within valid range
// - Gain within valid range
```

#### Issue 9.2: UserDefaults for State (Low)

**Location:** `AppStatePersistence.swift`

State persisted to `UserDefaults` without encryption. For sensitive settings, consider `Keychain`.

---

## 10. Summary & Prioritized Recommendations

### Critical (P0) - Fix Immediately

| Issue | Location | Impact |
|-------|----------|--------|
| Gain race condition | `RenderCallbackContext.swift:56-81` | Audio artifacts, potential crashes |

### High Priority (P1) - Fix Soon

| Issue | Location | Impact |
|-------|----------|--------|
| Missing audio pipeline tests | `tests/services/audio/` | Regression risk, hard to refactor |
| Singleton dependency | `AudioRoutingCoordinator.swift:155` | Testing difficulty |

### Medium Priority (P2) - Fix When Possible

| Issue | Location | Impact |
|-------|----------|--------|
| Deprecated atomic APIs | `AudioRingBuffer.swift` | Future compatibility |
| Large coordinator class | `AudioRoutingCoordinator.swift` | Maintainability |
| Main thread meter processing | `MeterStore.swift` | UI responsiveness |
| View model recreation | `EQWindowView.swift` | Minor performance |
| Buffer overrun potential | `RenderCallbackContext.swift` | Edge case safety |

### Low Priority (P3) - Nice to Have

| Issue | Location | Impact |
|-------|----------|--------|
| Hardcoded ring buffer size | `RenderPipeline.swift:65` | Flexibility |
| Manual Codable implementation | `EQBandConfiguration.swift` | Code reduction |
| Device enumeration allocation | `DeviceEnumerationService.swift` | Minor performance |
| Preset import validation | `EasyEffectsImporter.swift` | Edge case robustness |

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
    // Use ManagedAtomic for thread-safe target values
    let targetInputGainLinear: ManagedAtomic<Float> = ManagedAtomic(1.0)
    nonisolated(unsafe) var inputGainLinear: Float = 1.0  // Only audio thread writes

    func updateTargetInputGain(_ value: Float) {
        targetInputGainLinear.store(value, ordering: .relaxed)
    }

    // In applyGain, read target atomically:
    // let targetGain = targetInputGainLinear.load(ordering: .relaxed)
}
```

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

### 3. Inject DriverManager Dependency (P1)

**File:** `AudioRoutingCoordinator.swift`

```swift
// Add protocol to src/services/driver/protocols/DriverAccessing.swift
protocol DriverAccessing {
    var isReady: Bool { get }
    var deviceID: AudioDeviceID? { get }
    func setDeviceName(_ name: String) -> Bool
    func setDriverSampleRate(matching rate: Float64) -> Float64?
    static var shared: DriverAccessing { get }
}

// In AudioRoutingCoordinator init:
init(
    driverManager: DriverAccessing = DriverManager.shared,
    // ...
) {
    self.driverManager = driverManager
    // ...
}

// Update all DriverManager.shared calls to use the injected instance
```

### 4. Cache View Models (P2)

**File:** `EQWindowView.swift`

```swift
struct EQWindowView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var showCompareHelp = false
    @State private var metersEnabledUI = false

    // Cache view models
    @State private var routingViewModel: RoutingViewModel?
    @State private var eqViewModel: EQViewModel?

    private func getRoutingViewModel() -> RoutingViewModel {
        if let vm = routingViewModel { return vm }
        let vm = RoutingViewModel(store: store)
        routingViewModel = vm
        return vm
    }

    private func getEQViewModel() -> EQViewModel {
        if let vm = eqViewModel { return vm }
        let vm = EQViewModel(store: store)
        eqViewModel = vm
        return vm
    }

    var body: some View {
        // Use getRoutingViewModel() and getEQViewModel()
    }
}
```

### 5. Background Meter Processing (P2)

**File:** `MeterStore.swift`

```swift
@MainActor
final class MeterStore: ObservableObject {
    private let processingQueue = DispatchQueue(
        label: "net.knage.equaliser.meter.processing",
        qos: .userInteractive
    )

    private func refreshMeterSnapshot() {
        guard metersEnabled else { ... }
        guard let pipeline = renderPipeline else { return }

        // Calculate on background queue
        processingQueue.async { [weak self] in
            let snapshot = pipeline.currentMeters()

            // Update UI on main thread
            DispatchQueue.main.async { [weak self] in
                self?.processMeterSnapshot(snapshot)
            }
        }
    }
}
```

---

## Conclusion

This codebase demonstrates professional-grade Swift audio programming with:

- **Excellent architecture** with clean separation of concerns
- **Proper real-time audio thread safety** patterns
- **Swift 6 concurrency** adoption
- **Protocol-based dependency injection** for testability
- **Pure function domain logic** for complex business rules

The main areas requiring attention are:

1. **Gain race condition** - theoretical but should be fixed
2. **Audio pipeline test coverage** - critical path lacks tests
3. **Singleton dependencies** - should be injected for testability

Overall, this is a well-maintained, production-quality codebase that demonstrates strong software engineering practices.

---

*Review generated by Claude (Opus 4.6) on 2026-03-21*
