# AI Guidelines - Equaliser

Guidelines for AI coding agents working in this repository.

**IMPORTANT:** Read this entire document before making any changes. It contains critical architecture details, coding conventions, and context necessary for successful modifications.

## Project Overview

A macOS menu bar equalizer application built with Swift 6 and SwiftUI.

| Aspect       | Details                                           |
|--------------|---------------------------------------------------|
| Language     | Swift 6 (strict concurrency)                      |
| Framework    | SwiftUI + AVFoundation + Core Audio               |
| Platform     | macOS 15+ (Sequoia), Apple Silicon only           |
| Build System | Swift Package Manager                             |

## Build & Test

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run all tests
swift test --filter TestClassName
```

## Project Structure

### Core Architecture

| Directory | Purpose |
|-----------|---------|
| `src/app/` | App entry point and lifecycle |
| `src/domain/` | Pure data types (no dependencies) |
| `src/domain/device/` | Device types, history, policies (pure) |
| `src/domain/eq/` | EQ configuration types |
| `src/domain/presets/` | Preset model types |
| `src/domain/routing/` | Routing status types |
| `src/domain/driver/` | Driver status types |
| `src/services/` | Infrastructure layer |
| `src/services/audio/` | Audio processing (DSP, HAL, rendering) |
| `src/services/device/` | Device enumeration and control |
| `src/services/driver/` | Driver lifecycle management |
| `src/services/presets/` | Preset file management |
| `src/services/meters/` | Meter state and calculations |
| `src/store/` | Application state (managers, coordinators) |
| `src/store/coordinators/` | Coordinators (orchestrate multiple components) |
| `src/store/protocols/` | Coordinator protocols |
| `src/viewmodels/` | Presentation layer view models |
| `src/views/` | SwiftUI views |

### Key Files

| File | Purpose |
|------|---------|
| `src/store/EqualiserStore.swift` | Thin coordinator delegating to coordinators |
| `src/domain/eq/EQConfiguration.swift` | EQ band data (storage-free) |
| `src/domain/device/DeviceChangeDetector.swift` | Built-in device diff detection (pure) |
| `src/domain/device/DeviceChangeEvent.swift` | Device change event types (pure) |
| `src/domain/device/HeadphoneSwitchPolicy.swift` | Headphone switch decision logic (pure) |
| `src/domain/device/OutputDeviceHistory.swift` | Output device history for reconnection |
| `src/services/audio/AudioConstants.swift` | Centralized audio/EQ constants and validation |
| `src/services/audio/DriverNameManager.swift` | Driver naming with CoreAudio refresh workaround |
| `src/services/audio/rendering/RenderPipeline.swift` | Dual HAL + EQ processing |
| `src/services/driver/protocols/DriverAccessing.swift` | Protocol for driver lifecycle access |
| `src/services/meters/MeterStore.swift` | Meter state management |
| `src/store/coordinators/AudioRoutingCoordinator.swift` | Device selection and pipeline management |
| `src/store/coordinators/DeviceChangeCoordinator.swift` | Device change events, headphone detection |
| `src/store/VolumeManager.swift` | Volume sync between driver and output device |
| `src/store/CompareModeTimer.swift` | Auto-revert timer for compare mode |
| `src/services/device/DeviceEnumerationService.swift` | Device enumeration and change events |
| `src/services/device/DeviceManager.swift` | Device model and selection logic |

### Views Structure

| Directory | Purpose |
|-----------|---------|
| `src/views/main/` | Main EQ window, menu bar, settings |
| `src/views/eq/` | EQ band controls |
| `src/views/meters/` | Level meters |
| `src/views/presets/` | Preset management |
| `src/views/device/` | Device selection |
| `src/views/driver/` | Driver installation |
| `src/views/shared/` | Reusable components |

### Tests

| Directory | Purpose |
|-----------|---------|
| `tests/mocks/` | Mock implementations for testing |
| `tests/domain/` | Domain type tests |
| `tests/domain/device/` | Device change, history, and headphone switch policy tests |
| `tests/services/` | Service layer tests |
| `tests/store/` | Store and coordinator tests |
| `tests/viewmodels/` | View model tests |

### Other Directories

| Directory | Purpose |
|-----------|---------|
| `driver/` | Kernel driver source code |
| `driver/src/` | Driver C source files |
| `resources/` | App icon and assets |
| `docs/user/` | User documentation |
| `docs/dev/` | Developer documentation |

## Architecture

### Layered Architecture

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
│  - SystemDefaultObserver: macOS default changes             │
│  - VolumeManager: driver ↔ output volume sync               │
│  - CompareModeTimer: auto-revert timer                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Service Layer (via Protocols)                              │
│  - DeviceEnumerationService: device enumeration, events     │
│  - DeviceVolumeService: volume control                      │
│  - DeviceSampleRateService: sample rate queries             │
│  - DeviceManager: device model, selection logic             │
│  - DriverManager: driver lifecycle (DriverLifecycleManaging)│
│  - PresetManager: preset file management                    │
│  - MeterStore: 30 FPS meter updates                         │
└─────────────────────────────────────────────────────────────┘
```

### State Management

| Component | Role | Persistence |
|-----------|------|-------------|
| `EqualiserStore` | Thin coordinator | No |
| `EQConfiguration` | Pure data model | No |
| `MeterStore` | Isolated 30 FPS meter state | No |
| `PresetManager` | Preset file management | Yes (JSON) |
| `AppStatePersistence` | Saves on app quit | Yes (UserDefaults) |

### Coordinator Pattern

`EqualiserStore` is a **thin coordinator** that delegates to specialized coordinators:

```swift
EqualiserStore
├── DeviceChangeCoordinator (device change events, history, headphone detection)
│   └── OutputDeviceHistory
├── AudioRoutingCoordinator (device selection, pipeline lifecycle)
│   ├── SystemDefaultObserver (macOS default changes)
│   ├── VolumeManager (volume sync, created lazily)
│   └── DriverNameManager (driver naming)
├── CompareModeTimer (auto-revert)
├── DeviceManager (device enumeration, selection logic)
│   └── DeviceEnumerationService
├── EQConfiguration (band data)
├── MeterStore (meter updates)
└── PresetManager (preset files)
```

**Key coordinators and managers:**

- `DeviceChangeCoordinator`: Subscribes to `DeviceEnumerationService.$changeEvent`, manages `OutputDeviceHistory`, emits callbacks for headphone detection and missing devices
- `AudioRoutingCoordinator`: Handles pipeline lifecycle, delegates device change handling to `DeviceChangeCoordinator`, creates `VolumeManager` when routing starts
- `VolumeManager`: Owns volume sync state (gain, muted, device IDs), syncs volume between driver and output device

**Service dependencies via protocols:**

- `VolumeManager` depends on `VolumeControlling` protocol
- `AudioRoutingCoordinator` depends on `VolumeControlling` and `SampleRateObserving` protocols

### Protocol-Based DI

Services are accessed via protocols for testability:

```swift
// Device enumeration
protocol Enumerating: ObservableObject {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func device(forUID uid: String) -> AudioDevice?
}

// Volume control
protocol VolumeControlling: AnyObject {
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
}

// Driver lifecycle
protocol DriverLifecycleManaging: ObservableObject {
    var status: DriverStatus { get }
    var isReady: Bool { get }
    func installDriver() async throws
}
```

**Naming pattern:**
- Protocols: Pure capability names with `-ing` suffix (`Enumerating`, `VolumeControlling`, `SampleRateObserving`)
- Concrete types: Domain prefix + service suffix (`DeviceEnumerationService`, `DeviceVolumeService`, `DeviceSampleRateService`)

### View Models

View models hold `unowned` store references and derive presentation state:

```swift
@Observable final class RoutingViewModel {
    private unowned let store: EqualiserStore
    var statusColor: Color { /* derive from store.routingStatus */ }
}
```

### Meter Constants

- `MeterConstants`: silence threshold (-90 dB), range (-36...0), gamma (0.5), normalizedPosition()
- `MeterMath`: linearToDB, dbToLinear, calculatePeak

### Audio Constants

`AudioConstants` provides centralized constants for audio pipeline configuration:

- `maxFrameCount` (4096): Maximum frames per render callback
- `ringBufferCapacity` (8192): Ring buffer samples per channel
- `minGain` / `maxGain` (-36...+36 dB): UI slider range
- `clampGain()`, `clampFrequency()`, `clampBandwidth()`: Validation helpers

All preset imports and UI sliders use these constants for consistent validation.

### Audio Pipeline

The app routes audio through two HAL units:

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

| Component | Purpose |
|-----------|---------|
| `HALIOManager` | Single HAL unit (input or output mode) |
| `RenderPipeline` | Orchestrates dual HAL + EQ |
| `AudioRingBuffer` | Lock-free SPSC buffer for clock drift |

### Routing Modes

| Mode | Input | Output | Use Case |
|------|-------|--------|----------|
| Automatic | Equaliser driver | macOS default | Recommended |
| Manual | User-selected | User-selected | Advanced |

## Critical Learnings

### NSApp Timing

`NSApp` is **nil** during `@main` init. Defer access:

```swift
init() {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### HAL Audio Unit Scopes

```
[Hardware] ────▶│ Element 1 (Input)  │──▶ [Your Callback]
[Callback] ────▶│ Element 0 (Output) │──▶ [Hardware]
```

- Set client format on opposite scope
- Input-only: enable Element 1, disable Element 0

### Boost Gain Always Applied

Boost gain (for driver volume compensation) must **always** be applied, even in bypass mode. Input/output gains are skipped in bypass.

```swift
// Boost is ALWAYS applied (not inside bypass check)
context.applyGain(to: context.inputSampleBuffers, ...)

// Input gain is skipped in bypass mode
if context.processingMode != 0 {
    context.applyGain(to: context.inputSampleBuffers, ...)
}
```

### Driver Name Refresh Pattern

When changing the driver's device name, the device list must be refreshed afterward:

```swift
// 1. Set the name
let success = DriverManager.shared.setDeviceName("Speakers (Equaliser)")

// 2. Toggle default output to trigger CoreAudio notifications
systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)

// 3. After delay, set driver back as default and refresh
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    systemDefaultObserver.setDriverAsDefault()
    deviceManager.refreshDevices()  // Critical: updates cached device list
}
```

**Why this matters**: CoreAudio caches device names. Without `refreshDevices()`, the UI shows stale driver names after renaming.

**If driver names aren't updating in UI**: Check that `refreshDevices()` is called after `setDeviceName()`.

### DriverNameManager Call Site Responsibility

`DriverNameManager.updateDriverName()` is **synchronous** and returns immediately. The caller is responsible for calling `setDriverAsDefault()` synchronously before starting the audio pipeline:

```swift
// CORRECT: Caller sets driver as default before starting pipeline
let success = driverNameManager.updateDriverName(...)
if success {
    systemDefaultObserver.setDriverAsDefault()  // Synchronous, before pipeline
}
renderPipeline.start()

// WRONG: Delayed setDriverAsDefault causes audio through wrong output
// The fire-and-forget GCD inside updateDriverName() is for UI refresh only
```

### Fire-and-Forget Scheduled Work

For scheduled work on the main thread that doesn't need to block the caller, use `DispatchQueue.main.asyncAfter`, not `Task.sleep`:

```swift
// CORRECT: Returns immediately, schedules work asynchronously
func updateDriverName() -> Bool {
    driverAccess.setDeviceName(name)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.setDriverAsDefault()  // Fire-and-forget
    }
    return true  // Caller proceeds immediately
}

// WRONG: Blocks caller, causes audio to play through wrong device
func updateDriverName() async -> Bool {
    driverAccess.setDeviceName(name)
    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms delay!
    return true
}
```

### Headphone Auto-Switch

The app automatically switches output to headphones when plugged in, matching macOS behaviour.

**Platform Detection:**

| Platform | Detection Method |
|----------|------------------|
| Apple Silicon | Built-in device count change (`+1` = headphones) |
| Intel Mac | `kAudioDevicePropertyJackIsConnected` property |

**Implementation:**
- `DeviceEnumerator` tracks `previousBuiltInDeviceUIDs` and emits `DeviceChangeEvent.builtInDeviceAdded` when `+1` built-in device detected
- `DeviceEnumerator.setupJackConnectionListener()` handles Intel Mac jack detection, emitting events directly
- `AudioRoutingCoordinator.handleBuiltInDeviceAdded()` only switches if current output is built-in

**Key behaviour:**
- Only switches when current output is built-in (never steals from USB/Bluetooth/HDMI)
- Saves current device to history before switching
- Works in automatic mode only (respects manual mode)

### Device Selection Logic

Unified device selection via `OutputDeviceSelection.determine()`:

```swift
// Pure function - no side effects, testable
let selection = OutputDeviceSelection.determine(
    currentSelected: savedOutputUID,
    macDefault: systemDefaultUID,
    availableDevices: deviceManager.outputDevices
)

switch selection {
case .preserveCurrent(let uid):  // Current is valid, keep it
case .useMacDefault(let uid):    // Use macOS default
case .useFallback:               // Need fallback device
}
```

**Device properties:**
- `isValidForSelection`: Trusts everything except driver (user choices respected)
- `isRealDevice`: Excludes driver, virtual, aggregate (fallback only)

### CoreAudio Safety with Stale UIDs

Never call `deviceManager.device(forUID:)` with potentially-stale UIDs from history. CoreAudio may have deallocated the device, causing use-after-free crashes.

```swift
// WRONG: Calls CoreAudio with stale UID
if let device = deviceManager.device(forUID: uid) { ... }

// CORRECT: Use cached device list
let devices = deviceManager.outputDevices
if let device = devices.first(where: { $0.uid == uid }) { ... }
```

`OutputDeviceHistory.findReplacementDevice()` uses the cached list to avoid this crash.

## Code Guidelines

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Types/Protocols | UpperCamelCase | `AudioDevice`, `DeviceEnumerating` |
| Functions/Methods | lowerCamelCase | `refreshDevices()`, `start()` |
| Variables | lowerCamelCase | `isRunning`, `inputDevices` |
| Constants | lowerCamelCase | `let smoothingInterval` |
| Enum cases | lowerCamelCase | `.parametric`, `.bypass` |
| Private members | No underscore prefix | `private var task` |
| User-initiated updates | `update*` prefix | `updateBandGain()` |

### Spelling

Use British English throughout:

| American | British |
|----------|---------|
| equalizer | equaliser |
| behavior | behaviour |
| optimized | optimised |

**Note:** "meter" = audio level meters (not length unit)

### Concurrency

- **@MainActor**: UI-bound classes and coordinators
- **actor**: Thread-safe isolated state (`ParameterSmoother`)
- **nonisolated(unsafe)**: Audio thread access
- **@Observable**: View models for SwiftUI binding

### Testing

- Test through **public API only**
- Use **real instances** for integration tests
- Mock implementations removed when they only tested mocks (not real code)
- Protocols enable focused test implementations when needed

**Pure Function Testing Pattern:**

For complex logic without dependencies, extract to pure functions in `enum` types (`OutputDeviceSelection`, `DeviceChangeDetector`, `HeadphoneSwitchPolicy`, `AudioMath`, `MeterMath`).

```swift
enum HeadphoneSwitchPolicy {
    static func shouldSwitch(...) -> Bool { ... }
}
// Test directly without mocking
XCTAssertTrue(HeadphoneSwitchPolicy.shouldSwitch(...))
```

## Common Tasks

### Modifying EQ Settings
```swift
store.updateBandGain(index: 0, gain: 6.0)  // marks preset as modified
eqViewModel.updateBandGain(index: 0, gain: 6.0)
```

### Working with View Models
```swift
let routingVM = RoutingViewModel(store: store)
let color = routingVM.statusColor
routingVM.toggleRouting()
```

### Working with Coordinators
```swift
store.routingStatus  // .idle, .starting, .active, .error
store.selectedInputDeviceID = "device-uid"
store.selectedOutputDeviceID = "device-uid"
```

### Working with the Driver
```swift
DriverManager.shared.isReady  // true if installed
DriverManager.shared.status   // .notInstalled, .installed, .needsUpdate
DriverManager.shared.setDeviceName("My EQ")
```

## Entitlements

- `com.apple.security.device.audio-input` (audio routing)
- `com.apple.security.files.user-selected.read-write` (presets)

**Note:** App is not sandboxed (required for driver installation).
