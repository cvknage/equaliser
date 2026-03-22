# AI Guidelines - Equaliser

Guidelines for AI coding agents working in this repository.

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

## Pre-Submit Checklist

Before submitting code, verify:

- [ ] **Single Responsibility**: Does each type have one clear reason to change?
- [ ] **Protocol Dependencies**: Are dependencies on protocols, not concrete types?
- [ ] **No Duplication**: Is each constant/piece of logic in one place?
- [ ] **Pure Domain Logic**: Does new domain code avoid I/O and dependencies?

## Code Quality Patterns

This codebase follows SOLID and DRY principles. Key patterns:

### Single Responsibility
- `src/domain/` contains pure types with no dependencies
- Services do one thing: `DeviceEnumerationService`, `DeviceVolumeService`
- Coordinators orchestrate, delegates do the work

### Protocol Segregation
- Protocols use `-ing` suffix: `Enumerating`, `VolumeControlling`, `SampleRateObserving`
- Small, focused protocols — inject these, not concrete types
- Pattern: `class FooService: FooControlling { ... }`

### No Duplication
- Constants centralized: `AudioConstants`, `MeterConstants`
- Pure utilities extracted: `AudioMath`, `MeterMath`
- Device policies: `HeadphoneSwitchPolicy`, `DeviceChangeDetector`, `OutputDeviceSelection`

### Domain Purity
- `src/domain/` types have zero dependencies
- Test business logic by importing domain types only
- If it has side effects, it belongs in `src/services/` or `src/store/`

For detailed architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Critical Learnings

Project-specific knowledge from hard-won debugging sessions. **Read carefully.**

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

### Headphone Auto-Switch

The app automatically switches output to headphones when plugged in, matching macOS behaviour.

| Platform | Detection Method |
|----------|------------------|
| Apple Silicon | Built-in device count change (`+1` = headphones) |
| Intel Mac | `kAudioDevicePropertyJackIsConnected` property |

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
- **actor**: Thread-safe isolated state (`ParameterSmoother`)
- **nonisolated(unsafe)**: Audio thread access
- **@Observable**: View models for SwiftUI binding

## Testing

- Test through **public API only**
- Use **real instances** for integration tests
- Domain types in `src/domain/` are pure and easily unit-tested
- Protocols enable focused test implementations when needed

For complex logic without dependencies, extract to pure functions:

```swift
// In domain/
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