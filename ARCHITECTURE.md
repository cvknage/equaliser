# Architecture Reference

Detailed architecture documentation for the Equaliser app. See [AGENTS.md](AGENTS.md) for coding guidelines.

## Project Structure

### Feature-Based Architecture

| Directory | Purpose |
|-----------|---------|
| `src/app/` | App entry point, state coordinator, and persistence |
| `src/routing/` | Audio routing orchestration, mode strategy, and driver naming |
| `src/dsp/` | EQ signal processing (biquad filters, chains, configuration, coefficient staging) |
| `src/dsp/biquad/` | Core biquad filter math and DSP |
| `src/dsp/chain/` | EQ chain processing and state |
| `src/dsp/config/` | EQ configuration (bands, channels, filter types, bandwidth conversion) |
| `src/pipeline/` | Audio capture, rendering, and shared infrastructure |
| `src/pipeline/capture/` | Audio capture from driver (shared memory, HAL input) |
| `src/pipeline/hal/` | CoreAudio HAL I/O |
| `src/driver/` | Driver lifecycle management |
| `src/driver/protocols/` | Driver protocols (`-ing` suffix) |
| `src/device/` | CoreAudio device enumeration and control |
| `src/device/enumeration/` | Device discovery and listing |
| `src/device/enumeration/protocols/` | Enumeration protocols |
| `src/device/volume/` | Volume control, observation, and sync |
| `src/device/volume/protocols/` | Volume protocol |
| `src/device/change/` | Device change detection, policies, and coordination |
| `src/meters/` | Level metering (state and calculations) |
| `src/presets/` | Preset file management and import/export |
| `src/ui/` | SwiftUI views and view models |
| `src/ui/views/` | SwiftUI view components |

### Key Files

| File | Purpose |
|------|---------|
| `src/app/EqualiserStore.swift` | App state coordinator (delegates to feature modules) |
| `src/app/AppStateSnapshot.swift` | App state persistence |
| `src/app/EqualiserApp.swift` | App entry point |
| `src/routing/AudioRoutingCoordinator.swift` | Routing orchestration (delegates to PipelineManager, EQCoefficientStager, RoutingMode) |
| `src/routing/RoutingMode.swift` | Strategy protocol for mode-specific device resolution |
| `src/routing/AutomaticRoutingMode.swift` | Automatic routing: driver + macOS default |
| `src/routing/ManualRoutingMode.swift` | Manual routing: user-selected devices |
| `src/routing/RoutingStatus.swift` | Routing state enum (idle, starting, active, error) |
| `src/routing/DriverNameManager.swift` | Driver naming with CoreAudio refresh workaround |
| `src/pipeline/PipelineManager.swift` | Render pipeline lifecycle (create, configure, start, stop) |
| `src/dsp/config/EQConfiguration.swift` | EQ band data (storage-free) |
| `src/dsp/config/FilterType.swift` | Filter types (parametric, shelves, etc.) |
| `src/dsp/config/CompareMode.swift` | EQ vs Flat comparison mode enum |
| `src/dsp/config/CompareModeTimer.swift` | Auto-revert timer for compare mode |
| `src/dsp/config/CompareModeTimerControlling.swift` | Protocol for compare mode timer |
| `src/dsp/config/EQLayerConstants.swift` | EQ layer count and indexing constants |
| `src/dsp/config/BandwidthConverter.swift` | Q factor ↔ bandwidth (octaves) conversion and display |
| `src/dsp/biquad/BiquadCoefficients.swift` | Biquad coefficient value type (Equatable, Sendable) |
| `src/dsp/biquad/BiquadMath.swift` | RBJ Cookbook coefficient calculation (pure functions) |
| `src/dsp/chain/ChannelEQState.swift` | Per-channel EQ state (layers, bands) |
| `src/dsp/config/ChannelMode.swift` | Linked vs stereo mode enum |
| `src/device/change/DeviceChangeDetector.swift` | Built-in device diff detection (pure) |
| `src/device/change/DeviceChangeEvent.swift` | Device change event types (pure) |
| `src/device/change/HeadphoneSwitchPolicy.swift` | Headphone switch decision logic (pure) |
| `src/device/change/OutputDeviceHistory.swift` | Output device history for reconnection |
| `src/device/change/DeviceChangeCoordinator.swift` | Device change event coordination and headphone detection |
| `src/device/OutputDeviceSelection.swift` | Pure output device selection logic (preserve/default/fallback) |
| `src/device/volume/DeviceVolumeService.swift` | CoreAudio volume control |
| `src/device/volume/VolumeManager.swift` | Volume sync between driver and output device |
| `src/device/SystemDefaultObserver.swift` | macOS default output device observer |
| `src/pipeline/AudioConstants.swift` | Centralized audio/EQ constants and validation |
| `src/pipeline/AudioMath.swift` | Pure audio math utilities (dB/linear conversion) |
| `src/pipeline/AudioRingBuffer.swift` | Lock-free SPSC ring buffer for audio callbacks |
| `src/pipeline/RenderPipeline.swift` | Dual HAL + EQ processing |
| `src/dsp/biquad/BiquadFilter.swift` | vDSP biquad wrapper with delay elements |
| `src/dsp/chain/EQChain.swift` | Per-channel filter chain with lock-free updates |
| `src/pipeline/capture/CaptureMode.swift` | Capture mode enum (halInput, sharedMemory) |
| `src/pipeline/capture/DriverCapture.swift` | Shared memory capture from driver |
| `src/pipeline/capture/SharedMemoryCapture.swift` | Lock-free ring buffer reader |
| `src/driver/protocols/DriverAccessing.swift` | Protocol for driver lifecycle access |
| `src/meters/MeterStore.swift` | Meter state management |
| `src/device/enumeration/DeviceEnumerationService.swift` | Device enumeration and change events |
| `src/device/enumeration/DeviceManager.swift` | Device model and selection logic |

### TCC Permission Considerations

The audio pipeline triggers macOS microphone permission due to the AudioUnit type used for output:

| Component | AudioUnit Type | TCC Impact |
|-----------|----------------|------------|
| `HALIOManager` | `kAudioUnitSubType_HALOutput` | Triggers TCC at instantiation |
| `DriverCapture` | None (shared memory) | No TCC impact |

The `HALIOManager` uses `kAudioUnitSubType_HALOutput` because it supports device selection for both input and output. However, this AudioUnit type is flagged by macOS as potentially accessing audio input, triggering TCC permission when instantiated — even when only used for output.

**Current architecture:**
```
RenderPipeline.configure()
  → HALIOManager(outputOnly)
    → AudioComponentInstanceNew(kAudioUnitSubType_HALOutput)
      → TCC permission check triggered
```

**See** `docs/dev/TCC-Permission-Architecture.md` **for potential solutions under investigation.**

### Views Structure

| Directory | Purpose |
|-----------|---------|
| `src/ui/views/main/` | Main EQ window, menu bar, settings |
| `src/ui/views/eq/` | EQ band controls |
| `src/ui/views/meters/` | Level meters |
| `src/ui/views/presets/` | Preset management |
| `src/ui/views/device/` | Device selection |
| `src/ui/views/driver/` | Driver installation |
| `src/ui/views/shared/` | Reusable components |

### Tests

| Directory | Purpose |
|-----------|---------|
| `tests/app/` | App state tests |
| `tests/dsp/biquad/` | Biquad math and filter tests |
| `tests/dsp/chain/` | EQ chain tests |
| `tests/dsp/config/` | EQ configuration, filter type, and bandwidth conversion tests |
| `tests/pipeline/` | Audio math, ring buffer, and render pipeline tests |
| `tests/pipeline/capture/` | Capture mode policy tests |
| `tests/device/change/` | Device change, history, and headphone switch policy tests |
| `tests/device/enumeration/` | Device manager tests |
| `tests/meters/` | Meter calculation and store tests |
| `tests/presets/` | Preset import/export, codable, and migration tests |
| `tests/ui/` | View model tests |

### Other Directories

| Directory | Purpose |
|-----------|---------|
| `driver/` | Kernel driver source code |
| `driver/src/` | Driver C source files |
| `resources/` | App icon and assets |
| `docs/user/` | User documentation |
| `docs/dev/` | Developer documentation |

## Feature-Based Organization

Each feature group is self-contained — it owns its domain types, services, protocols, and coordination logic. The `app/` layer orchestrates feature modules together.

```
┌─────────────────────────────────────────────────────────────┐
│  App Layer (State + UX)                                     │
│  - EqualiserStore: app state, delegates to features         │
└─────────────────────────────────────────────────────────────┘
              │               │               │
              ▼               ▼               ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│  routing/     │ │  dsp/         │ │  pipeline/    │
│  Mode strategy│ │  Biquad DSP   │ │  HAL, capture │
│  Device naming│ │  EQ chains    │ │  rendering    │
├───────────────┤ ├───────────────┤ ├───────────────┤
│  driver/      │ │  meters/      │ │  device/      │
│  Lifecycle    │ │  Level meters │ │  Enum, volume │
│  Properties   │ │               │ │  change detect│
└───────────────┘ └───────────────┘ └───────────────┘
                              │
                              ▼
              ┌───────────────────────────┐
              │  ui/                       │
              │  Views + ViewModels        │
              └───────────────────────────┘
```

## State Management

| Component | Role | Location | Persistence |
|-----------|------|----------|-------------|
| `EqualiserStore` | App state coordinator | `app/` | No |
| `EQConfiguration` | Pure data model | `dsp/config/` | No |
| `MeterStore` | Isolated 30 FPS meter state | `meters/` | No |
| `PresetManager` | Preset file management | `presets/` | Yes (JSON) |
| `AppStatePersistence` | Saves on app quit | `app/` | Yes (UserDefaults) |

## Coordinator Pattern

`EqualiserStore` (in `app/`) is a **thin coordinator** that delegates to feature modules:

```swift
EqualiserStore (app/)
├── AudioRoutingCoordinator (routing/) — routing orchestration
│   ├── PipelineManager (pipeline/) — render pipeline lifecycle
│   │   └── RenderPipeline (pipeline/)
│   ├── EQCoefficientStager (dsp/) — EQ coefficient calculation and staging
│   ├── RoutingMode (routing/) — strategy: AutomaticRoutingMode or ManualRoutingMode
│   ├── DeviceChangeCoordinator (device/change/) — device events, headphone detection
│   │   └── OutputDeviceHistory (device/change/)
│   ├── VolumeManager (device/volume/) — volume sync and drift detection
│   ├── SystemDefaultObserver (device/) — macOS default changes
│   └── DriverNameManager (routing/) — driver naming
├── CompareModeTimer (dsp/config/) — auto-revert
├── DeviceManager (device/enumeration/) — device enumeration, selection logic
│   └── DeviceEnumerationService (device/enumeration/)
├── EQConfiguration (dsp/config/) — band data
├── MeterStore (meters/) — meter updates
└── PresetManager (presets/) — preset files
```

**Key coordinators and managers:**

- `DeviceChangeCoordinator` (device/change/): Subscribes to `DeviceEnumerationService.$changeEvent`, manages `OutputDeviceHistory`, emits callbacks for headphone detection and missing devices
- `AudioRoutingCoordinator` (routing/): Routes device resolution to `RoutingMode` strategy, delegates pipeline lifecycle to `PipelineManager`, EQ staging to `EQCoefficientStager`, creates `VolumeManager` when routing starts
- `PipelineManager` (pipeline/): Creates, configures, starts, and stops `RenderPipeline`. Sets up `VolumeManager` and `EQCoefficientStager` when pipeline starts
- `EQCoefficientStager` (dsp/): Calculates biquad coefficients via `BiquadMath` and stages them to `RenderPipeline`. Owns `currentSampleRate` and all `updateBand*` methods
- `VolumeManager` (device/volume/): Owns volume sync state (gain, muted, device IDs), syncs volume between driver and output device, performs drift detection

**Service dependencies via protocols:**

- `VolumeManager` depends on `VolumeControlling` protocol
- `AudioRoutingCoordinator` depends on `DeviceProviding`, `PermissionRequesting`, `VolumeControlling`, and `SampleRateObserving` protocols
- `DriverNameManager` depends on `DeviceProviding` protocol

## Protocol-Based Dependency Injection

Services are accessed via protocols for testability:

```swift
// Device enumeration
protocol Enumerating: ObservableObject {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func device(forUID uid: String) -> AudioDevice?
}

// Device providing (composition of lookup, enumeration, and fallback)
protocol DeviceProviding: AnyObject {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func device(forUID uid: String) -> AudioDevice?
    func deviceID(forUID uid: String) -> AudioDeviceID?
    func enumerateInputDevices()
    func refreshDevices()
    func findBuiltInAudioDevice() -> AudioDevice?
    func selectFallbackOutputDevice(excluding excludeUID: String?) -> AudioDevice?
}

// Volume control
protocol VolumeControlling: AnyObject {
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
}

// Permission requesting
protocol PermissionRequesting {
    var isMicPermissionGranted: Bool { get }
    func requestMicPermission() async -> Bool
}

// Routing mode (strategy pattern)
@MainActor
protocol RoutingMode {
    var isManual: Bool { get }
    var requiresDriverVisibility: Bool { get }
    var requiresSampleRateSync: Bool { get }
    var handlesSystemDefaultChanges: Bool { get }
    var handlesBuiltInDeviceChanges: Bool { get }
    var needsMicPermission: Bool { get }
    func resolveDevices(...) -> DeviceResolution
}

// Driver lifecycle
protocol DriverLifecycleManaging: ObservableObject {
    var status: DriverStatus { get }
    var isReady: Bool { get }
    func installDriver() async throws
}
```

**Naming pattern:**
- Service protocols: Pure capability names with `-ing` suffix (`Enumerating`, `VolumeControlling`, `SampleRateObserving`, `DeviceProviding`, `PermissionRequesting`)
- Strategy protocols: Domain name with no suffix (`RoutingMode`)
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
│  EQConfiguration ──▶ EQCoefficientStager                        │
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
EQCoefficientStager.stageBandCoefficients(index, config)
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

Uses lock-free shared memory. No TCC permission required. Audio goes directly from shared memory to EQ processing — no intermediate ring buffer needed since both poll and render run on the same output thread.

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
                                    ▼ (direct, same thread)
┌──────────────┐     ┌──────────────┐     ┌────────────────────┐
│ Output Device│ ◀── │  Output HAL  │ ◀── │ Output Callback    │
└──────────────┘     └──────────────┘     │ + EQ (64 bands)    │
                                          └────────────────────┘
```

| Component | Purpose |
|-----------|---------|
| `HALIOManager` | Single HAL unit (input or output mode) |
| `RenderPipeline` | Orchestrates HAL units + EQ |
| `AudioRingBuffer` | Lock-free SPSC buffer for clock drift (HAL input mode only) |
| `DriverCapture` | Polls driver shared memory for audio |
| `SharedMemoryCapture` | Lock-free shared memory ring buffer reader (mmap) |

## Routing Modes

Routing mode is implemented via the Strategy pattern (`RoutingMode` protocol). `AudioRoutingCoordinator` delegates device resolution to the current mode:

| Mode | Strategy | Input | Output | Use Case |
|------|----------|-------|--------|----------|
| Automatic | `AutomaticRoutingMode` | Equaliser driver | macOS default | Recommended |
| Manual | `ManualRoutingMode` | User-selected | User-selected | Advanced |

Mode-specific behaviour is defined by `RoutingMode` protocol properties: `requiresDriverVisibility`, `requiresSampleRateSync`, `handlesSystemDefaultChanges`, `handlesBuiltInDeviceChanges`, `needsMicPermission`.

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

`AudioConstants` (in `src/pipeline/`) provides centralized constants for audio pipeline configuration:

- `maxFrameCount` (16384): Maximum frames per render callback (supports up to 768kHz)
- `ringBufferCapacity` (32768): Ring buffer samples per channel (clock drift absorption)
- `minEQFrequency` / `maxEQFrequency` (1–22000 Hz): EQ frequency range (audible spectrum)
- `minGain` / `maxGain` (-36...+36 dB): UI slider range
- `clampGain()`, `clampFrequency()`, `clampBandwidth()`: Validation helpers

All preset imports and UI sliders use these constants for consistent validation.