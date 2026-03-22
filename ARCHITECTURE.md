# Architecture Reference

Detailed architecture documentation for the Equaliser app. See [AGENTS.md](AGENTS.md) for coding guidelines.

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

## Layered Architecture

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

## State Management

| Component | Role | Persistence |
|-----------|------|-------------|
| `EqualiserStore` | Thin coordinator | No |
| `EQConfiguration` | Pure data model | No |
| `MeterStore` | Isolated 30 FPS meter state | No |
| `PresetManager` | Preset file management | Yes (JSON) |
| `AppStatePersistence` | Saves on app quit | Yes (UserDefaults) |

## Coordinator Pattern

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

## Protocol-Based Dependency Injection

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

## View Models

View models hold `unowned` store references and derive presentation state:

```swift
@Observable final class RoutingViewModel {
    private unowned let store: EqualiserStore
    var statusColor: Color { /* derive from store.routingStatus */ }
}
```

## Audio Pipeline

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

## Routing Modes

| Mode | Input | Output | Use Case |
|------|-------|--------|----------|
| Automatic | Equaliser driver | macOS default | Recommended |
| Manual | User-selected | User-selected | Advanced |

## Constants

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