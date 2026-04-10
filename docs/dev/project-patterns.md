# Project Patterns

SOLID, DRY, and architectural conventions used in this codebase.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  App Layer (Coordination)                                   │
│  - EqualiserStore: app state, delegates to features         │
│  - AudioRoutingCoordinator: pipeline + device orchestration  │
└─────────────────────────────────────────────────────────────┘
              │               │               │
              ▼               ▼               ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│  dsp/         │ │  pipeline/    │ │  device/      │
│  Biquad DSP   │ │  HAL, capture │ │  Enum, volume │
│  EQ chains    │ │  rendering    │ │  change detect│
├───────────────┤ ├───────────────┤ ├───────────────┤
│  driver/      │ │  meters/      │ │  presets/     │
│  Lifecycle    │ │  Level meters │ │  File I/O     │
│  Properties   │ │               │ │               │
└───────────────┘ └───────────────┘ └───────────────┘
                              │
                              ▼
              ┌───────────────────────────┐
              │  ui/                       │
              │  Views + ViewModels        │
              └───────────────────────────┘
```

## Single Responsibility Principle

- Each feature group is self-contained: owns its types, services, protocols, and coordination logic
- Services do one thing: `DeviceEnumerationService`, `DeviceVolumeService`
- `app/` is the orchestration layer — `EqualiserStore` and `AudioRoutingCoordinator` tie features together
- Coordinators delegate to focused types: `EQCoefficientStager` (DSP staging), `PipelineManager` (pipeline lifecycle), `RoutingMode` (device resolution strategy)
- Each view model derives presentation state from exactly one store

## Protocol Segregation

Service protocols use `-ing` suffix: `Enumerating`, `VolumeControlling`, `SampleRateObserving`

Strategy protocols use domain name without suffix: `RoutingMode`

Small, focused protocols — inject these, not concrete types:

```swift
protocol Enumerating: ObservableObject {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func device(forUID uid: String) -> AudioDevice?
}

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

protocol VolumeControlling: AnyObject {
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
}

protocol PermissionRequesting {
    var isMicPermissionGranted: Bool { get }
    func requestMicPermission() async -> Bool
}

protocol DriverLifecycleManaging: ObservableObject {
    var status: DriverStatus { get }
    var isReady: Bool { get }
    func installDriver() async throws
}
```

Naming pattern:
- Service protocols: `Enumerating`, `VolumeControlling`, `SampleRateObserving`, `DeviceProviding`, `PermissionRequesting`, `DriverAccessing`, `DriverDeviceDiscovering`, `DriverLifecycleManaging`, `DriverPropertyAccessing`, `CompareModeTimerControlling`, `SystemDefaultObserving`
- Strategy protocols: `RoutingMode` (no suffix — represents a mode, not a capability)
- Concrete types: `DeviceEnumerationService`, `DeviceVolumeService`, `DeviceSampleRateService`, `AudioPermissionService`

## No Duplication (DRY)

- Constants centralized: `AudioConstants`, `MeterConstants`
- Pure utilities extracted: `AudioMath`, `MeterMath`
- Device policies: `HeadphoneSwitchPolicy`, `DeviceChangeDetector`, `OutputDeviceSelection`

## Domain Purity

- Pure types (no I/O, no dependencies) live alongside their services in each feature group
- Test business logic by importing pure types directly
- If it has side effects, it belongs in a service within its feature group

For complex logic without dependencies, extract to pure functions:

```swift
// In device/change/
enum HeadphoneSwitchPolicy {
    static func shouldSwitch(...) -> Bool { ... }
}

// Test directly without mocking
XCTAssertTrue(HeadphoneSwitchPolicy.shouldSwitch(...))
```

## Coordinator Pattern

`EqualiserStore` is a **thin coordinator** that delegates to specialized coordinators:

```swift
EqualiserStore (app/)
├── AudioRoutingCoordinator (app/) — routing orchestration
│   ├── PipelineManager (pipeline/) — render pipeline lifecycle
│   │   └── RenderPipeline (pipeline/)
│   ├── EQCoefficientStager (dsp/) — EQ coefficient calculation and staging
│   ├── RoutingMode (device/routing/) — strategy: AutomaticRoutingMode or ManualRoutingMode
│   ├── DeviceChangeCoordinator (device/change/) — device events, headphone detection
│   │   └── OutputDeviceHistory (device/change/)
│   ├── VolumeManager (device/volume/) — volume sync and drift detection
│   ├── SystemDefaultObserver (device/) — macOS default changes
│   └── DriverNameManager (pipeline/) — driver naming
├── CompareModeTimer (dsp/) — auto-revert
├── DeviceManager (device/enumeration/) — device enumeration, selection logic
│   └── DeviceEnumerationService (device/enumeration/)
├── EQConfiguration (dsp/config/) — band data
├── MeterStore (meters/) — meter updates
└── PresetManager (presets/) — preset files
```

Key coordinators:
- `DeviceChangeCoordinator` (device/change/): Subscribes to `DeviceEnumerationService.$changeEvent`, manages `OutputDeviceHistory`, emits callbacks for headphone detection and missing devices
- `AudioRoutingCoordinator` (app/): Routes device resolution to `RoutingMode` strategy, delegates pipeline lifecycle to `PipelineManager`, EQ staging to `EQCoefficientStager`, creates `VolumeManager` when routing starts
- `PipelineManager` (pipeline/): Creates, configures, starts, and stops `RenderPipeline`. Sets up `VolumeManager` and `EQCoefficientStager` when pipeline starts
- `EQCoefficientStager` (dsp/): Calculates biquad coefficients via `BiquadMath` and stages them to `RenderPipeline`. Owns `currentSampleRate` and all `updateBand*` methods
- `VolumeManager` (device/volume/): Owns volume sync state (gain, muted, device IDs), syncs volume between driver and output device, performs drift detection

## View Models

View models hold `unowned` store references and derive presentation state:

```swift
@Observable final class RoutingViewModel {
    private unowned let store: EqualiserStore
    var statusColor: Color { /* derive from store.routingStatus */ }
}
```

## EQ Chain Architecture

EQ settings can be linked (both channels) or independent (stereo):

| Mode | Behaviour |
|------|-----------|
| `.linked` | Both channels share the same EQ curve (default) |
| `.stereo` | Left and right channels have independent EQ curves |

Implementation:
- `EQConfiguration.channelMode` determines linked vs stereo
- `EQConfiguration.channelFocus` (`left` or `right`) determines which channel is being edited
- `EQChain` is instantiated per-channel-per-layer in `RenderCallbackContext`
- `EQChannelTarget` (`.left`, `.right`, `.both`) routes coefficient updates to the correct chain(s)

## Preset Backward Compatibility

`PresetSettings` uses a custom `Decodable` implementation for backward compatibility:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... required fields ...
    channelMode = try container.decodeIfPresent(String.self, forKey: .channelMode) ?? "linked"
    rightBands = try container.decodeIfPresent([PresetBand].self, forKey: .rightBands)
}
```

Key points:
- `decodeIfPresent` for new fields (`channelMode`, `rightBands`) with sensible defaults
- `FilterType` raw values match legacy `AVAudioUnitEQFilterType` values — no migration needed
- `PresetBand.filterType` validates raw values and falls back to `.parametric`

## Constants

### Meter Constants
- `MeterConstants`: silence threshold (-90 dB), range (-36...0), gamma (0.5), normalizedPosition()
- `MeterMath`: linearToDB, dbToLinear, calculatePeak

### Audio Constants
`AudioConstants` provides centralized constants:
- `maxFrameCount` (16384): Maximum frames per render callback (supports up to 768kHz)
- `ringBufferCapacity` (32768): Ring buffer samples per channel (clock drift absorption)
- `minEQFrequency` / `maxEQFrequency` (1–22000 Hz): EQ frequency range
- `minGain` / `maxGain` (-36...+36 dB): UI slider range
- `clampGain()`, `clampFrequency()`, `clampBandwidth()`: Validation helpers

All preset imports and UI sliders use these constants for consistent validation.