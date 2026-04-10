# AI Guidelines - Equaliser

Guidelines for AI coding agents working in this repository.

## Project Overview

A macOS menu bar equaliser application built with Swift 6 and SwiftUI.

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

## Pre-Submit Checklist

Before submitting code, verify:

- [ ] **Single Responsibility**: Does each type have one clear reason to change?
- [ ] **Protocol Dependencies**: Are dependencies on protocols, not concrete types?
- [ ] **No Duplication**: Is each constant/piece of logic in one place?
- [ ] **Pure Domain Logic**: Does new pure-type code avoid I/O and dependencies?

## Code Quality Patterns

This codebase follows SOLID and DRY principles. Key patterns:

### Single Responsibility
- Each feature group is self-contained: owns its types, services, protocols, and coordination logic
- Services do one thing: `DeviceEnumerationService`, `DeviceVolumeService`
- Coordinators delegate to focused types: `EQCoefficientStager` (DSP staging), `PipelineManager` (pipeline lifecycle), `RoutingMode` (device resolution strategy)
- `app/` is the orchestration layer — `EqualiserStore` and `AudioRoutingCoordinator` tie features together

### Protocol Segregation
- Service protocols use `-ing` suffix: `Enumerating`, `VolumeControlling`, `SampleRateObserving`, `DeviceProviding`, `PermissionRequesting`
- Strategy protocols use domain name without suffix: `RoutingMode`
- Small, focused protocols — inject these, not concrete types
- Pattern: `class FooService: FooControlling { ... }`

### No Duplication
- Constants centralized: `AudioConstants`, `MeterConstants`
- Pure utilities extracted: `AudioMath`, `MeterMath`
- Device policies: `HeadphoneSwitchPolicy`, `DeviceChangeDetector`, `OutputDeviceSelection`

### Domain Purity
- Pure types (no I/O, no dependencies) live alongside their services in each feature group
- Test business logic by importing pure types directly
- If it has side effects, it belongs in a service within its feature group

For detailed architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Types/Protocols | UpperCamelCase | `AudioDevice`, `DeviceEnumerating` |
| Functions/Methods | lowerCamelCase | `refreshDevices()`, `start()` |
| Variables | lowerCamelCase | `isRunning`, `inputDevices` |
| Constants | lowerCamelCase | `let smoothingInterval` |
| Enum cases | lowerCamelCase | `.parametric`, `.bypass` |
| Private members | No underscore prefix | `private var task` |
| User-initiated updates | `update*` prefix | `updateBandGain()` |
| Protocols | `-ing` suffix | `Enumerating`, `VolumeControlling` |
| Concrete services | Domain + Service | `DeviceEnumerationService` |

## Spelling

Use British English throughout:

| American | British |
|----------|---------|
| equalizer | equaliser |
| behavior | behaviour |
| optimized | optimised |

**Note:** "meter" = audio level meters (not length unit)

## Concurrency

- **@MainActor**: UI-bound classes and coordinators
- **nonisolated(unsafe)**: Audio thread access
- **@Observable**: View models for SwiftUI binding

## Testing

- Test through **public API only**
- Use **real instances** for integration tests
- Pure types within each feature group are easily unit-tested
- Protocols enable focused test implementations when needed

For complex logic without dependencies, extract to pure functions:

```swift
// In device/change/
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

- `com.apple.security.device.audio-input` (audio routing - required for HAL input capture mode)
- `com.apple.security.files.user-selected.read-write` (presets)

**Note:** 
- App is not sandboxed (required for driver installation).
- The `audio-input` entitlement is required for HAL input capture mode to work.

## Knowledge Files

Detailed technical knowledge is split into focused files for contextual loading. Skills inject relevant files based on the task area.

| File | When to Load |
|------|-------------|
| `docs/dev/coreaudio.md` | Debugging audio issues, device routing, TCC permissions |
| `docs/dev/realtime-safety.md` | Working on DSP, audio pipeline, render callbacks |
| `docs/dev/swift-concurrency.md` | Concurrency issues, @MainActor, Sendable, actor isolation |
| `docs/dev/memory-safety.md` | Retain cycles, weak/unowned, ARC, lifetime management |
| `docs/dev/project-patterns.md` | Refactoring, SOLID/DRY analysis, architecture changes |
| `docs/dev/known-issues.md` | Debugging known gotchas, NSApp timing, boost gain, driver refresh |