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
swift test               # Run all tests (189 tests)
swift test --filter TestClassName
```

## Project Structure

### Core Architecture

| Directory | Purpose |
|-----------|---------|
| `src/app/` | App entry point and lifecycle |
| `src/domain/` | Pure data types (no dependencies) |
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
| `src/store/` | Application state coordinators |
| `src/store/coordinators/` | Audio routing, device changes, volume sync |
| `src/store/protocols/` | Coordinator protocols |
| `src/viewmodels/` | Presentation layer view models |
| `src/views/` | SwiftUI views |

### Key Files

| File | Purpose |
|------|---------|
| `src/store/EqualiserStore.swift` | Thin coordinator delegating to coordinators |
| `src/domain/eq/EQConfiguration.swift` | EQ band data (storage-free) |
| `src/services/meters/MeterStore.swift` | Meter state management |
| `src/store/coordinators/AudioRoutingCoordinator.swift` | Device selection and pipeline management |
| `src/services/audio/rendering/RenderPipeline.swift` | Dual HAL + EQ processing |

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

### Tests (189 tests)

| Directory | Purpose |
|-----------|---------|
| `tests/mocks/` | Mock implementations for testing |
| `tests/domain/` | Domain type tests |
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
│  - DeviceChangeHandler: connect/disconnect events           │
│  - SystemDefaultObserver: macOS default changes             │
│  - VolumeSyncCoordinator: driver ↔ output volume sync       │
│  - CompareModeTimer: auto-revert timer                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Service Layer (via Protocols)                              │
│  - DeviceManager: device enumeration (DeviceEnumerating)    │
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
├── AudioRoutingCoordinator (device selection, pipeline lifecycle)
│   ├── SystemDefaultObserver (macOS default changes)
│   ├── DeviceChangeHandler (connect/disconnect)
│   └── VolumeSyncCoordinator (volume sync)
├── CompareModeTimer (auto-revert)
├── DeviceManager (device enumeration)
├── EQConfiguration (band data)
├── MeterStore (meter updates)
└── PresetManager (preset files)
```

### Protocol-Based DI

Services are accessed via protocols for testability:

```swift
// Device enumeration
protocol DeviceEnumerating: ObservableObject {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func device(forUID uid: String) -> AudioDevice?
}

// Driver lifecycle
protocol DriverLifecycleManaging: ObservableObject {
    var status: DriverStatus { get }
    var isReady: Bool { get }
    func installDriver() async throws
}
```

### View Models

View models derive presentation state from the store:

```swift
@Observable
final class RoutingViewModel {
    private unowned let store: EqualiserStore
    
    var statusColor: Color {
        switch store.routingStatus {
        case .idle: return .gray
        case .active: return .green
        // ...
        }
    }
    
    func toggleRouting() {
        if store.routingStatus.isActive {
            store.stopRouting()
        } else {
            store.reconfigureRouting()
        }
    }
}
```

### Meter Constants

All meter calculations use shared constants:

```swift
enum MeterConstants {
    static let silenceDB: Float = -90
    static let meterRange: ClosedRange<Float> = -36...0
    static let gamma: Float = 0.5
    
    static func normalizedPosition(for db: Float) -> Float { ... }
}

enum MeterMath {
    static func linearToDB(_ linear: Float) -> Float { ... }
    static func dbToLinear(_ db: Float) -> Float { ... }
    static func calculatePeak(buffer: UnsafePointer<Float>, frameCount: Int) -> Float { ... }
}
```

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
- Use **real instances** (no mocking framework)
- Protocols enable **test implementations** (`MockCompareModeTimer`, etc.)
- View models are tested with real store

## Common Tasks

### Modifying EQ Settings

```swift
// Via store (marks preset as modified)
store.updateBandGain(index: 0, gain: 6.0)
store.updateBandFrequency(index: 0, frequency: 1000)

// Via view model
eqViewModel.updateBandGain(index: 0, gain: 6.0)
```

### Working with View Models

```swift
// Create view model
let routingVM = RoutingViewModel(store: store)

// Access derived state
let color = routingVM.statusColor
let text = routingVM.statusText

// Perform actions
routingVM.toggleRouting()
```

### Working with Coordinators

```swift
// Coordinators are owned by EqualiserStore
// Access via store.routingCoordinator or create view models

// Routing status
store.routingStatus  // .idle, .starting, .active, .error

// Device selection
store.selectedInputDeviceID = "device-uid"
store.selectedOutputDeviceID = "device-uid"
```

### Working with the Driver

```swift
DriverManager.shared.isReady                  // true if installed
DriverManager.shared.status                   // .notInstalled, .installed, .needsUpdate
DriverManager.shared.setDeviceName("My EQ")  // Set custom name
```

## Entitlements

- `com.apple.security.device.audio-input` (audio routing)
- `com.apple.security.files.user-selected.read-write` (presets)

**Note:** App is not sandboxed (required for driver installation).
