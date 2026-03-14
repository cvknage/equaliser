# AGENTS.md - Equaliser

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

| Directory | File | Purpose |
|-----------|------|---------|
| **App/** | `EqualiserApp.swift` | @main entry, MenuBarExtra, Window definitions |
| | `AppStateSnapshot.swift` | Persistence model + AppStatePersistence class |
| | `Info.plist` | App metadata and configuration |
| **Core/** | `EqualiserStore.swift` | Central state coordinator, computed properties |
| | `EQConfiguration.swift` | EQ band data (storage-free, up to 64 bands) |
| | `MeterStore.swift` | Isolated 30 FPS meter state (observer pattern) |
| | `MeterObserver.swift` | MeterType enum, MeterObserver protocol for direct UI updates |
| | `RoutingStatus.swift` | Routing status enum (.idle, .starting, .active, .error) |
| **Audio/HAL/** | `HALIOManager.swift` | HAL audio unit (input/output modes) |
| | `HALIOError.swift` | HAL error types |
| **Audio/Rendering/** | `RenderPipeline.swift` | Orchestrates dual HAL + EQ processing |
| | `RenderCallbackContext.swift` | Pre-allocated callback buffers |
| | `AudioRenderContext.swift` | Wraps manualRenderingBlock |
| | `ManualRenderingEngine.swift` | AVAudioEngine manual rendering |
| **Audio/DSP/** | `AudioRingBuffer.swift` | Lock-free SPSC ring buffer |
| | `ParameterSmoother.swift` | Smooth parameter ramping (actor) |
| **Device/** | `DeviceManager.swift` | Core Audio device enumeration |
| **Driver/** | `DriverConstants.swift` | Bundle ID, UIDs, paths, custom property selectors |
| | `DriverManager.swift` | Driver lifecycle: install, uninstall, status |
| **Driver/** | `EqualiserDriver.patch` | Patch file for upstream updates |
| **Driver/src/** | `EqualiserDriver.c` | Kernel audio driver source |
| | `Info.plist` | Driver bundle metadata |
| **Presets/** | `PresetModel.swift` | Preset, PresetMetadata, PresetBand types |
| | `PresetManager.swift` | Load/save/delete presets |
| | `FactoryPresets.swift` | Built-in presets (Flat, Bass Boost, etc.) |
| | `EasyEffectsImporter.swift` | Import EasyEffects (Linux) presets |
| | `EasyEffectsExporter.swift` | Export to EasyEffects format |
| | `BandwidthConverter.swift` | Q ↔ bandwidth conversion + BandwidthDisplayMode |
| **Views/Main/** | `EQWindowView.swift` | Main EQ window content |
| | `MenuBarView.swift` | Menu bar popover content |
| | `SettingsView.swift` | Settings window (Cmd+,) |
| **Views/EQ/** | `EQBandGridView.swift` | Grid of EQ band sliders |
| | `EQBandSliderView.swift` | Individual band slider with controls |
| | `BandCountControl.swift` | Band count selector |
| | `GainStepperControl.swift` | Input/output gain controls |
| **Views/Meters/** | `LevelMetersView.swift` | Input/output level meters (SwiftUI wrapper) |
| | `PeakMeterLayer.swift` | GPU-accelerated peak meter (CALayer) |
| | `PeakMeterNSView.swift` | SwiftUI wrapper for PeakMeterLayer |
| | `RMSMeterLayer.swift` | GPU-accelerated RMS meter (CALayer) |
| | `RMSMeterNSView.swift` | SwiftUI wrapper for RMSMeterLayer |
| | `MeterScaleView.swift` | Meter scale visualization + MeterConstants |
| **Views/Presets/** | `PresetViews.swift` | Preset management UI |
| **Views/Device/** | `DevicePickerView.swift` | Device selection UI |
| | `RoutingStatusView.swift` | Routing status display |
| **Views/Driver/** | `DriverInstallationView.swift` | Driver installation UI |
| **Views/Shared/** | `StepperButton.swift` | Reusable stepper button |
| | `ToggleWithHelp.swift` | Toggle with help text |
| | `InlineEditableValue.swift` | Inline editable value field |
| | `WindowAccessor.swift` | NSWindow access for SwiftUI |
| | `ViewExtensions.swift` | SwiftUI view extensions |
| | `AVAudioUnitEQFilterTypeExtension.swift` | Filter type display names |

### Tests

| File | Purpose |
|------|---------|
| `AudioRingBufferTests.swift` | Ring buffer tests |
| `BandwidthConverterTests.swift` | Q/bandwidth conversion tests |
| `DeviceManagerTests.swift` | Device enumeration and transport type tests |
| `EasyEffectsImportExportTests.swift` | Import/export tests |
| `EQConfigurationTests.swift` | EQ configuration tests |
| `EqualiserStoreTests.swift` | Device selection logic tests |
| `MeterCalculationTests.swift` | Meter math tests |
| `MeterStoreTests.swift` | Meter state management tests |
| `PresetCodableTests.swift` | Preset serialization tests |

## Architecture

### State Management

| Component | Role | Persistence |
|-----------|------|-------------|
| `EqualiserStore` | Coordinator: routing, presets, computed properties | No (delegates to EQConfiguration) |
| `EQConfiguration` | Pure data model: bands, gains, bypass | No (storage-free) |
| `MeterStore` | Isolated 30 FPS meter state | No (storage-free) |
| `DriverManager` | Driver lifecycle: install, uninstall, status | No (queries system) |
| `AppStatePersistence` | Saves on app quit | Yes (single JSON blob) |

**Key pattern:** Models are storage-free. Persistence happens at app quit via `AppStateSnapshot`:

```
┌──────────────────────────────────────────────────────────────┐
│                     App Lifecycle                            │
│  Launch: Load snapshot → Initialize components               │
│  Quit:   Collect snapshot → Save to UserDefaults             │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    EqualiserStore                            │
│  - Coordinates EQConfiguration, MeterStore, PresetManager    │
│  - Provides computed properties (isBypassed, bandCount, etc) │
│  - currentSnapshot: AppStateSnapshot (computed property)     │
└──────────────────────────────────────────────────────────────┘
         │ owns                    │ owns                    │ owns
         ▼                         ▼                         ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│ EQConfiguration │      │   MeterStore    │      │  PresetManager  │
│ (pure data)     │      │ (runtime state) │      │ (file-based)    │
│ - bands, gains  │      │ - meter levels  │      │ - presets dir   │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

### Audio Pipeline

The app routes audio from an input device (e.g., BlackHole) through an EQ chain to an output device (e.g., speakers). This requires **two separate HAL audio units** because a single HAL unit can only connect to one physical device.

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
| `HALIOManager` | Manages a single HAL audio unit in `.inputOnly` or `.outputOnly` mode |
| `RenderPipeline` | Orchestrates two HAL managers + AVAudioEngine |
| `AudioRingBuffer` | Lock-free SPSC buffer for inter-callback audio transfer, handles clock drift |
| `ManualRenderingEngine` | AVAudioEngine configured for offline/manual rendering |

### Compare Mode

Compare Mode (EQ vs Flat) uses an auto-revert timer to protect users from accidentally leaving Flat mode:

- Segmented control in UI: `[EQ | Flat]`
- Auto-reverts to EQ after 5 minutes
- Works independently of System EQ toggle
- Processing modes: 0=System EQ OFF, 1=Normal EQ, 2=Flat mode

### Routing Modes

Two routing modes are supported:

| Mode | Input | Output | Use Case |
|------|-------|--------|----------|
| Automatic | Equaliser driver | macOS default (excludes virtual/aggregate) | Recommended |
| Manual | User-selected | User-selected | Advanced setups |

In Automatic mode, input is always the Equaliser driver. Output device selection uses `determineAutomaticOutputDevice()` — a pure function that preserves the user's previous output if valid, falls back to macOS default if not the driver, and finally selects the first non-virtual, non-aggregate device.

The `RoutingStatus` enum includes `.driverNotInstalled` for automatic mode when the driver is missing.

### Device Detection

`AudioDevice` queries CoreAudio transport type once at creation:

```swift
struct AudioDevice {
    let transportType: UInt32  // From kAudioDevicePropertyTransportType
    
    var isVirtual: Bool {
        if transportType == kAudioDeviceTransportTypeVirtual { return true }
        return uid.hasPrefix("Equaliser") || uid.hasPrefix("BlackHole")
    }
    
    var isAggregate: Bool {
        transportType == kAudioDeviceTransportTypeAggregate
    }
}
```

Virtual detection has UID prefix fallback for drivers that don't set transport type. Aggregate detection trusts CoreAudio only.

### Driver Integration

The custom kernel driver (EqualiserDriver) captures system-wide audio:

```
┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│ System Audio │ ──▶ │ Equaliser    │ ──▶ │ App (EQ)      │
│ (any source) │     │ Driver       │     │ Process + EQ  │
└──────────────┘     └──────────────┘     └───────┬───────┘
                                                  │
                                                  ▼
                                          ┌──────────────┐
                                          │ Output Device│
                                          │ (speakers)   │
                                          └──────────────┘
```

| Component | Role |
|-----------|------|
| `DriverManager` | Singleton: install, uninstall, status, device name |
| `DriverConstants` | Bundle ID, UIDs, paths, custom property selectors |
| `DriverInstallationView` | SwiftUI flow for driver setup |

Key constants:
- `DRIVER_BUNDLE_ID = "net.knage.equaliser.driver"`
- `DRIVER_DEVICE_UID = "Equaliser_UID"`
- `DRIVER_INSTALL_PATH = "/Library/Audio/Plug-Ins/HAL"`

Custom properties allow runtime configuration:
- `'eqnm'` — device name (read/write)
- `'eqlt'` — output latency (read/write)

### Audio Thread Safety

`RenderPipeline` is `@MainActor` isolated, but audio callbacks run on the audio thread. Use `nonisolated(unsafe)` for shared state:

```swift
@MainActor
final class RenderPipeline {
    private nonisolated(unsafe) var isRunning: Bool = false
    private nonisolated(unsafe) var callbackContext: RenderCallbackContext?
    
    // Required to pass AudioUnit to callback context
    var unsafeAudioUnit: AudioUnit? { audioUnit }
}
```

**HAL Cleanup** must be synchronous in deinit:

```swift
deinit {
    if let unit = audioUnit {
        if isRunning { AudioOutputUnitStop(unit) }
        if isInitialized { AudioUnitUninitialize(unit) }
        AudioComponentInstanceDispose(unit)
    }
}
```

## Critical Learnings

### NSApp Timing

`NSApp` is **nil** during the `@main` struct's `init()`. Defer NSApp access:

```swift
// WRONG - crashes
init() {
    NSApp.setActivationPolicy(.accessory)  // NSApp is nil!
}

// CORRECT - defer to next run loop
init() {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### HAL Audio Unit Scopes

```
                ┌─────────────────────────────────────┐
                │         HAL Audio Unit              │
                │                                     │
[Hardware] ────▶│ Element 1 (Input)                   │
                │   - Input Scope: hardware format    │
                │   - Output Scope: client format ────┼──▶ [Your Callback]
                │                                     │
[Callback] ────▶│ Element 0 (Output)                  │
                │   - Input Scope: client format      │
                │   - Output Scope: hardware format ──┼──▶ [Hardware]
                └─────────────────────────────────────┘
```

- **Element 1** = Input path (microphone/capture)
- **Element 0** = Output path (speakers/playback)
- For input-only: enable Element 1, disable Element 0
- For output-only: enable Element 0 (default), Element 1 stays disabled
- Set client format on the "opposite" scope (Output scope of Element 1 for input, Input scope of Element 0 for output)

### What Works / What Doesn't

| Pattern | Status | Notes |
|---------|--------|-------|
| Dual HAL units | ✓ Works | Separate `HALIOManager` instances for input and output |
| Ring buffer | ✓ Works | Decouples input/output device clocks safely |
| Input callback | ✓ Works | Register via `kAudioOutputUnitProperty_SetInputCallback` |
| Non-interleaved format | ✓ Works | `kAudioFormatFlagIsNonInterleaved` Float32 |
| Manual rendering | ✓ Works | `AVAudioEngine.enableManualRenderingMode()` |
| Single HAL for I/O | ✗ Fails | Device property is global; setting input overwrites output (-10851) |
| AudioUnitRender on input HAL | ✗ Fails | Input HAL captures asynchronously; cannot be pulled (-10863) |
| Synchronous cross-device pull | ✗ Fails | Different clocks cause drift and glitches |

### Error Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `noErr` | Success |
| -50 | `paramErr` | Buffer format mismatch or invalid parameter |
| -10851 | `kAudioUnitErr_InvalidPropertyValue` | Device/property not valid for this scope |
| -10863 | `kAudioUnitErr_NoConnection` | No input connected to pull from |

## Code Guidelines

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Types/Protocols | UpperCamelCase | `AudioDevice`, `EqualiserStore` |
| Functions/Methods | lowerCamelCase | `refreshDevices()`, `start()` |
| Variables | lowerCamelCase | `isRunning`, `inputDevices` |
| Constants | lowerCamelCase | `let smoothingInterval` |
| Enum cases | lowerCamelCase | `.parametric`, `.bypass` |
| Private members | No underscore prefix | `private var task` |
| User-initiated updates | `update*` prefix | `updateBandGain()`, `updateInputGain()` |

### Spelling

Use British English spelling throughout the codebase and documentation:

| American | British |
|----------|---------|
| color | colour |
| center | centre |
| optimized | optimised |
| behavior | behaviour |
| equalize | equalise |
| equalizer | equaliser |
| equalization | equalisation |

**Note:** In this codebase, "meter" refers to audio level meters (peak/RMS displays), not the length unit. Use "meter" (not "metre") to match the audio industry convention.

### Concurrency

- **@MainActor**: UI-bound classes (`EqualiserStore`, `EQConfiguration`, `MeterStore`, `DeviceManager`, `PresetManager`, `RenderPipeline`, `HALIOManager`, `ManualRenderingEngine`, `AppStatePersistence`)
- **actor**: Thread-safe isolated state (`ParameterSmoother`)
- **nonisolated(unsafe)**: Audio thread access from `@MainActor` classes

### Testing

- Test through **public API only** - never expose internals
- Create **real instances** - no mocking
- Use `@MainActor` on test classes for UI-bound code
- Models are storage-free: `EQConfiguration()` instead of `EQConfiguration(storage: ...))`
- Test naming: `test<MethodName>_<scenario>_<expectedResult>()`

## Common Tasks

### Modifying EQ Settings

Update settings via `EqualiserStore` methods (marks presets as modified):

**Per-Band Updates:**
```swift
store.updateBandGain(index: 0, gain: 6.0)
store.updateBandFrequency(index: 0, frequency: 1000)
store.updateBandBandwidth(index: 0, bandwidth: 1.0)
store.updateBandFilterType(index: 0, filterType: .parametric)
store.updateBandBypass(index: 0, bypass: false)
```

**Global Updates:**
```swift
store.updateBandCount(15)
store.updateInputGain(6.0)
store.updateOutputGain(-2.0)
```

**Direct property access** (no preset modification):
```swift
store.isBypassed = true
store.bandCount = 10
store.inputGain = 0
```

### Working with the Driver

Check and manage driver status:
```swift
DriverManager.shared.isReady                  // true if installed and valid
DriverManager.shared.status                   // .notInstalled, .installed, .needsUpdate, .error
DriverManager.shared.setDeviceName("My EQ")  // Set custom device name
```

Installation requires admin privileges and restarts CoreAudio:
```swift
try await DriverManager.shared.installDriver()
```

The driver is bundled with the app via `bundle.sh` and installed to `/Library/Audio/Plug-Ins/HAL/Equaliser.driver`.

### Adding Files

**Source file:**
1. Create `.swift` file in `Sources/` or subdirectory
2. SPM auto-discovers (no `Package.swift` edit)

**Test file:**
1. Create test class in `Tests/`
2. Import: `@testable import Equaliser`
3. Run: `swift test --filter YourTestClass`

## Entitlements

- `com.apple.security.device.audio-input` (microphone/audio routing)
- `com.apple.security.files.user-selected.read-write` (preset import/export)

**Note:** The app is not sandboxed. This is required for driver installation, which needs admin privileges and writes to `/Library/Audio/Plug-Ins/HAL`.
