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

### Shared Memory Capture Mode

The app supports two capture modes for the Equaliser driver:

| Mode | Method | TCC Permission |
|------|--------|----------------|
| `sharedMemory` (default) | Lock-free ring buffer via mmap | NOT required |
| `halInput` | HAL input stream (AudioUnitRender) | Required |

**Key behaviour:**
- Default mode uses shared memory, no orange microphone indicator in Control Center
- HAL input mode is fallback for users who want/already have mic permission
- Capture mode is persisted and restored across launches
- Manual mode always uses HAL input (regardless of preference)

**Shared memory architecture:**

```
[Driver] ─→ WriteMix ─→ [Shared Memory Ring Buffer]
                                    ↓ (mmap, lock-free)
[App Output Callback] ─→ pollIntoBuffers() ─→ [DriverCapture] ─→ [Ring Buffer] ─→ [EQ] ─→ [Output]
```

**Real-time safety:**
- `SharedMemoryCapture.readFramesIntoBuffers()` uses atomic reads, no locks
- Called synchronously from output audio thread
- `DriverCapture.pollIntoBuffers()` is `@inline(__always)` for performance

### Custom DSP Implementation

The app uses a **custom biquad DSP engine** instead of `AVAudioUnitEQ`. This provides low-latency, real-time safe EQ processing.

**Architecture:**

```
[Main Thread]                              [Audio Thread]
     │                                           │
     ▼                                           │
BiquadMath.calculateCoefficients()               │
     │                                           │
     ▼                                           │
EQChain.stageBandUpdate()                        │
     │                                           │
     │    ┌──────────────────────────────────────┤
     │    │         ManagedAtomic<Bool>          │
     │    │      (hasPendingUpdate flag)         │
     │    └──────────────────────────────────────┤
     │                     │                     │
     ▼                     │ release             │ acquire
pendingCoefficients[i]     ▼                     ▼
                     ┌─────────────────────────────────────┐
                     │         EQChain.applyPendingUpdates │
                     │    (called once per render cycle)   │
                     └─────────────────────────────────────┘
                                        │
                                        ▼
                            Only rebuild changed bands
                            (dirty tracked via Equatable)
```

**Key files:**

| File | Purpose |
|------|---------|
| `BiquadMath.swift` | Pure coefficient calculation (RBJ Cookbook), Double precision |
| `BiquadCoefficients.swift` | Value type for b0/b1/b2/a1/a2, `Equatable`, `Sendable` |
| `BiquadFilter.swift` | vDSP biquad wrapper, owns delay elements and setup |
| `EQChain.swift` | Per-channel-per-layer chain of 64 biquads, lock-free coefficient updates |
| `EQChannelTarget.swift` | `.left` / `.right` / `.both` for stereo routing |
| `FilterType.swift` | 11 filter types with raw values matching AVAudioUnitEQFilterType |

**Real-time safety:**

1. **Dirty-tracking**: `EQChain.applyPendingUpdates()` only rebuilds filters whose coefficients actually changed (using `Equatable` comparison). A single-band slider drag rebuilds **1 filter** instead of 64.

2. **No allocation on audio thread**: All biquad setups and delay elements are pre-allocated at init. vDSP setup objects are only destroyed and recreated when coefficients change.

3. **Lock-free updates**: Main thread writes to `pendingCoefficients`, sets `hasPendingUpdate.store(true, .releasing)`. Audio thread calls `hasPendingUpdate.exchange(false, .acquiringAndReleasing)` and copies to `activeCoefficients`.

4. **State preservation for slider drags**: `BiquadFilter.setCoefficients(_, resetState: false)` preserves delay elements during incremental coefficient changes (slider drags), avoiding audible clicks. `resetState: true` is only used for preset loads and sample rate changes.

**Coefficient calculation:**

```swift
// Main thread (not real-time)
let coeffs = BiquadMath.calculateCoefficients(
    type: .parametric,      // FilterType enum
    sampleRate: 48000.0,
    frequency: 1000.0,
    q: 1.41,                // ~1 octave bandwidth
    gain: 6.0               // dB
)

// Staged to audio thread
chain.stageBandUpdate(index: 0, coefficients: coeffs, bypass: false)
```

**Do NOT:**
- Call `BiquadMath.calculateCoefficients()` on the audio thread (it allocates)
- Call `vDSP_biquad_CreateSetup` or `vDSP_biquad_DestroySetup` directly — use `BiquadFilter.setCoefficients()`
- Allocate memory or acquire locks in `RenderCallbackContext.processEQ()`

### nonisolated CoreAudio Calls

Volume forwarding uses a serial dispatch queue to isolate CoreAudio calls from the main thread:

```swift
// VolumeManager dispatches to serial queue for output device sync
volumeForwardQueue.async { [weak self] in
    self?.forwardVolumeToOutput(newVolume, outputID: outputID)
}

// DeviceVolumeService.setDeviceVolumeScalar is nonisolated
nonisolated func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
```

This prevents `AudioObjectSetPropertyData` from blocking the UI thread.

### Microphone Permission Handling

The app does **NOT** request microphone permission on launch. Permission is only requested when needed:

| Mode | When Permission Required |
|------|-------------------------|
| Automatic + Shared Memory | NEVER (default) |
| Automatic + HAL Input | When user switches capture mode in Settings |
| Manual | When user switches to manual mode |

**Implementation pattern:**

```swift
// Check permission before starting HAL input capture
let needsPermission = manualModeEnabled || (!manualModeEnabled && captureMode == .halInput)
if needsPermission {
    let permission = AVAudioApplication.shared.recordPermission
    guard permission == .granted else {
        routingStatus = .error("Microphone permission required")
        return
    }
}

// Request permission when user explicitly enables HAL input
func requestMicPermissionAndSwitchToHALCapture() async -> Bool {
    let granted = await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
    if granted {
        captureMode = .halInput
    }
    return granted
}
```

**Key points:**
- Shared memory capture is the default (no TCC permission)
- User must explicitly opt in to HAL input capture
- Permission check is sync (`recordPermission`), request is async
- Error shown in UI if permission denied while attempting to start routing

### Preset Backward Compatibility

`PresetSettings` uses a custom `Decodable` implementation for backward compatibility with presets saved before the custom DSP migration:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... required fields ...
    // Legacy presets lack channelMode — default to "linked"
    channelMode = try container.decodeIfPresent(String.self, forKey: .channelMode) ?? "linked"
    rightBands = try container.decodeIfPresent([PresetBand].self, forKey: .rightBands)
}
```

**Key points:**
- `decodeIfPresent` for new fields (`channelMode`, `rightBands`) with sensible defaults
- `FilterType` raw values match legacy `AVAudioUnitEQFilterType` values — no migration needed
- `PresetBand.filterType` validates raw values and falls back to `.parametric`

### Per-Channel EQ (Stereo Mode)

EQ settings can be linked (both channels) or independent (stereo):

| Mode | Behaviour |
|------|-----------|
| `.linked` | Both channels share the same EQ curve (default) |
| `.stereo` | Left and right channels have independent EQ curves |

**Implementation:**
- `EQConfiguration.channelMode` determines linked vs stereo
- `EQConfiguration.channelFocus` (`left` or `right`) determines which channel is being edited
- `EQChain` is instantiated per-channel-per-layer in `RenderCallbackContext`
- `EQChannelTarget` (`.left`, `.right`, `.both`) routes coefficient updates to the correct chain(s)

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

- `com.apple.security.device.audio-input` (audio routing - required for HAL input capture mode)
- `com.apple.security.files.user-selected.read-write` (presets)

**Note:** 
- App is not sandboxed (required for driver installation).
- The `audio-input` entitlement is required for HAL input capture mode to work.
- Shared memory capture (default) does NOT trigger the TCC microphone dialog on its own.
- However, macOS proactively shows the microphone permission dialog at app launch when the entitlement + usage description are both present.
- This means new installs will see the permission dialog before using the app, even in shared memory mode.
