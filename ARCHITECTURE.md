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
| `src/services/audio/capture/` | Driver capture (shared memory, HAL input) |
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
| `src/domain/eq/FilterType.swift` | 11 filter types (parametric, shelves, etc.) |
| `src/domain/eq/BiquadCoefficients.swift` | Biquad coefficient value type (Equatable, Sendable) |
| `src/domain/eq/BiquadMath.swift` | RBJ Cookbook coefficient calculation (pure functions) |
| `src/domain/eq/ChannelEQState.swift` | Per-channel EQ state (layers, bands) |
| `src/domain/eq/ChannelMode.swift` | Linked vs stereo mode enum |
| `src/domain/device/DeviceChangeDetector.swift` | Built-in device diff detection (pure) |
| `src/domain/device/DeviceChangeEvent.swift` | Device change event types (pure) |
| `src/domain/device/HeadphoneSwitchPolicy.swift` | Headphone switch decision logic (pure) |
| `src/domain/device/OutputDeviceHistory.swift` | Output device history for reconnection |
| `src/services/audio/AudioConstants.swift` | Centralized audio/EQ constants and validation |
| `src/services/audio/DriverNameManager.swift` | Driver naming with CoreAudio refresh workaround |
| `src/services/audio/rendering/RenderPipeline.swift` | Dual HAL + EQ processing |
| `src/services/audio/dsp/BiquadFilter.swift` | vDSP biquad wrapper with delay elements |
| `src/services/audio/dsp/EQChain.swift` | Per-channel filter chain with lock-free updates |
| `src/domain/capture/CaptureMode.swift` | Capture mode enum (halInput, sharedMemory) |
| `src/services/audio/capture/DriverCapture.swift` | Shared memory capture from driver |
| `src/services/audio/capture/SharedMemoryCapture.swift` | Lock-free ring buffer reader |
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

## DSP Architecture

The app uses a **custom biquad DSP engine** instead of `AVAudioUnitEQ`. This provides low-latency, real-time safe EQ processing with up to 64 bands per channel.

### Layered Design

```
┌─────────────────────────────────────────────────────────────────┐
│  Main Thread (UI / Configuration)                               │
│                                                                 │
│  EQConfiguration ──▶ AudioRoutingCoordinator                    │
│                              │                                  │
│                              ▼                                  │
│                    BiquadMath.calculateCoefficients()           │
│                              │                                  │
│                              ▼                                  │
│                    RenderPipeline.updateBandCoefficients()      │
│                              │                                  │
│                              ▼                                  │
│                    EQChain.stageBandUpdate()                    │
│                              │                                  │
│                    ManagedAtomic<Bool> (hasPendingUpdate)       │
└──────────────────────────────┬──────────────────────────────────┘
                               │ .releasing
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Audio Thread (Real-Time)                                           │
│                                                                     │
│  RenderCallbackContext.processEQ()                                  │
│        │                                                            │
│        ▼                                                            │
│  EQChain.applyPendingUpdates()                                      │
│        │ - hasPendingUpdate.exchange(false, .acquiringAndReleasing) │
│        │ - Only rebuild filters whose coefficients changed          │
│        │ - resetState: false for slider drags                       │
│        ▼                                                            │
│  EQChain.process(buffer:)                                           │
│        │ - Iterate active bands                                     │
│        │ - Skip bypassed bands                                      │
│        ▼                                                            │
│  BiquadFilter.process() ──▶ vDSP_biquad                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Responsibility | Thread |
|-----------|----------------|--------|
| `BiquadMath` | Calculate biquad coefficients (RBJ Cookbook) | Main thread |
| `BiquadCoefficients` | Value type for b0/b1/b2/a1/a2 | Shared (Sendable) |
| `BiquadFilter` | vDSP wrapper, owns delay elements | Audio thread only |
| `EQChain` | Per-channel filter chain with lock-free updates | Shared via atomics |
| `EQChannelTarget` | Routes updates to left/right/both channels | Main thread |

### Real-Time Safety

1. **No allocation**: All biquad setups and delay elements pre-allocated at init
2. **No locks**: Coefficient updates via `ManagedAtomic<Bool>` flag
3. **Dirty-tracking**: Only changed coefficients trigger vDSP setup rebuild
4. **State preservation**: `resetState: false` preserves filter memory on slider drags

### Coefficient Flow

```
[UI: Gain Slider Drag]
        │
        ▼
BiquadMath.calculateCoefficients(type, freq, q, gain)
        │ Returns Double-precision coefficients
        ▼
AudioRoutingCoordinator.stageBandCoefficients(index, config)
        │ Determines channel target (.left/.right/.both)
        ▼
RenderPipeline.updateBandCoefficients(channel, bandIndex, coefficients, bypass)
        │
        ▼
EQChain.stageBandUpdate(index, coefficients, bypass)
        │ Writes to pendingCoefficients[index]
        │ Sets hasPendingUpdate.store(true, .releasing)
        ▼
[Audio Thread: Next Render Cycle]
        │
        ▼
EQChain.applyPendingUpdates()
        │ Compares pending[i] != active[i] (Equatable)
        │ Only rebuilds changed filters
        ▼
EQChain.process(buffer:)
```

## Audio Pipeline

The app supports two capture modes for the Equaliser driver:

### Standard Capture (HAL Input)

Uses HAL input stream. Triggers macOS microphone indicator.

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

### Shared Memory Capture (Default)

Uses lock-free shared memory. No TCC permission required.

```
┌──────────────┐     ┌────────────────────────────────────┐
│ Equaliser    │ ──▶ │ Driver WriteMix                    │
│ Driver       │     │ (audio stored in shared memory)    │
└──────────────┘     └────────────────────────────────────┘
                                    │
                                    ▼ (mmap, lock-free)
                           ┌────────────────────┐
                           │ DriverCapture      │
                           │ pollIntoBuffers()  │
                           └────────────────────┘
                                    │
                                    ▼
                           ┌──────────────┐
                           │  Ring Buffer │
                           └──────────────┘
                                    │
                                    ▼
┌──────────────┐     ┌──────────────┐     ┌────────────────────┐
│ Output Device│ ◀── │  Output HAL  │ ◀── │ Output Callback    │
└──────────────┘     └──────────────┘     │ + EQ (64 bands)    │
                                           └────────────────────┘
```

| Component | Purpose |
|-----------|---------|
| `HALIOManager` | Single HAL unit (input or output mode) |
| `RenderPipeline` | Orchestrates HAL units + EQ |
| `AudioRingBuffer` | Lock-free SPSC buffer for clock drift |
| `DriverCapture` | Polls driver shared memory for audio |
| `SharedMemoryCapture` | Lock-free ring buffer reader (mmap) |

## Routing Modes

| Mode | Input | Output | Use Case |
|------|-------|--------|----------|
| Automatic | Equaliser driver | macOS default | Recommended |
| Manual | User-selected | User-selected | Advanced |

### Capture Modes

| Capture Mode | Method | TCC Permission | Use Case |
|-------------|--------|----------------|----------|
| sharedMemory | Driver mmap (lock-free) | NOT required | Default, recommended |
| halInput | HAL input stream | Required | Legacy, fallback |

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
