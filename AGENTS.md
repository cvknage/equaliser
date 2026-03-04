# AGENTS.md - Equalizer App

Guidelines for AI coding agents working in this repository.

## Project Overview

A macOS menu bar equalizer application built with Swift 6 and SwiftUI.

| Aspect       | Details                                           |
|--------------|---------------------------------------------------|
| Language     | Swift 6 (strict concurrency)                      |
| Framework    | SwiftUI + AVFoundation + Core Audio               |
| Platform     | macOS 15+ (Sequoia), Apple Silicon only           |
| Build System | Swift Package Manager                             |

## Build Commands

```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Run the app
swift run

# Clean build artifacts
swift package clean
```

Or open `Package.swift` directly in Xcode 16+ (File > Open Package).

## Test Commands

```bash
# Run all tests
swift test

# Run a single test class
swift test --filter EqualizerAppTests

# Run a single test method
swift test --filter EqualizerAppTests.testExample

# Run tests with verbose output
swift test --verbose
```

Test files are located in `Tests/`.

## Project Structure

```
equalizer/
├── Package.swift              # SPM manifest
├── EqualizerApp.entitlements
├── bundle.sh                  # Build app bundle
├── AGENTS.md                  # This file
├── ToDo.md                    # Project roadmap
├── Sources/
│   ├── EqualizerAppApp.swift      # @main entry, MenuBarExtra, Window, EQ UI
│   ├── EqualizerStore.swift       # Global state (ObservableObject)
│   │
│   │   # Audio Pipeline (HAL + AVAudioEngine)
│   ├── HALIOManager.swift         # HAL audio unit management (input/output modes)
│   ├── HALIOError.swift           # Error types for HAL operations
│   ├── RenderPipeline.swift       # Orchestrates dual HAL + EQ processing
│   ├── RenderCallbackContext.swift # Pre-allocated buffers for audio callbacks
│   ├── AudioRingBuffer.swift      # Lock-free SPSC ring buffer
│   ├── ManualRenderingEngine.swift # AVAudioEngine in manual rendering mode
│   ├── AudioRenderContext.swift   # Wraps AVAudioEngine's manualRenderingBlock
│   ├── EQConfiguration.swift      # EQ band settings storage (up to 64 bands)
│   ├── ParameterSmoother.swift    # Smooth parameter ramping (actor)
│   │
│   │   # Device Management
│   ├── DeviceManager.swift        # Core Audio device enumeration
│   │
│   │   # UI Components
│   ├── Views/
│   │   ├── DevicePickerView.swift     # Device selection pickers
│   │   ├── RoutingStatusView.swift    # Routing status display
│   │   ├── PresetViews.swift          # Preset management views
│   │   └── SettingsView.swift         # Settings window
│   │
│   └── Presets/
│       └── PresetManager.swift        # Preset loading/saving
│
└── Tests/
    └── EqualizerAppTests.swift
```

## Code Style Guidelines

### Formatting

- **Indentation**: 4 spaces (Swift standard)
- **Line length**: Keep reasonable (~120 chars soft limit)
- **Braces**: Opening brace on same line as declaration
- **Trailing commas**: Use in multi-line collections/enums

### Imports

Order imports alphabetically, system frameworks first:

```swift
import AVFoundation
import Combine
import CoreAudio
import Foundation
import SwiftUI
import os.log
```

### Naming Conventions

| Element           | Convention                    | Example                          |
|-------------------|-------------------------------|----------------------------------|
| Types/Protocols   | UpperCamelCase                | `AudioDevice`, `EqualizerStore`  |
| Functions/Methods | lowerCamelCase                | `refreshDevices()`, `start()`    |
| Variables         | lowerCamelCase                | `isRunning`, `inputDevices`      |
| Constants         | lowerCamelCase                | `let smoothingInterval`          |
| Enum cases        | lowerCamelCase                | `.parametric`, `.bypass`         |
| Private members   | No underscore prefix          | `private var task`               |
| UserDefaults keys | Nested enum with static props | `Keys.bypass`, `Keys.inputDevice`|

### Type Annotations

- Omit when type is obvious from initialization
- Include for public API and when clarity helps
- Use `@MainActor` on classes that touch UI or must be main-thread-bound

```swift
// Good
private let engine = AVAudioEngine()
@Published private(set) var inputDevices: [AudioDevice] = []

// When type matters
func bandMapping(for index: Int) -> (AVAudioUnitEQ, Int)
```

### Concurrency

This project uses Swift 6 strict concurrency:

- **Main Actor**: Use `@MainActor` on UI-bound classes (`EqualizerStore`, `DeviceManager`, `EQConfiguration`)
- **Actors**: Use `actor` for thread-safe isolated state (`ParameterSmoother`)
- **Sendable**: Ensure types crossing actor boundaries are `Sendable`
- **Task**: Use structured concurrency with `Task` and `async/await`

```swift
@MainActor
final class EqualizerStore: ObservableObject { ... }

actor ParameterSmoother { ... }
```

### Error Handling

- Use `do-catch` for recoverable errors with logging
- Use `guard` for early returns on precondition failures
- Log errors with `os.log` (`Logger`)

```swift
do {
    try engine.start()
    isRunning = true
    logger.info("Audio engine started")
} catch {
    logger.error("Failed to start engine: \(error.localizedDescription)")
}
```

### SwiftUI Patterns

- Use `@StateObject` for owned state in views
- Use `@EnvironmentObject` for shared dependency injection
- Use `@Published` in `ObservableObject` classes
- Prefer computed properties for derived state

```swift
@StateObject private var store = EqualizerStore()
@EnvironmentObject var store: EqualizerStore
```

### Core Audio Conventions

- Use `AudioObjectPropertyAddress` for property queries
- Always check `noErr` return status
- Use `defer` for cleanup of allocated buffers
- Wrap low-level APIs in descriptive helper methods

## Architecture Notes

### State Management

- `EqualizerStore`: Central `ObservableObject` for app state
- Persists preferences via `UserDefaults`
- Owns reference to `RenderPipeline`

### Audio Pipeline Architecture

The app routes audio from an input device (e.g., BlackHole) through an EQ chain to an output device (e.g., speakers). This requires **two separate HAL audio units** because a single HAL unit can only connect to one physical device.

```
[Input Device] → [Input HAL Unit] → [Input Callback] → [Ring Buffer]
                                                             ↓
[Output Callback] ← reads ← [Ring Buffer]
        ↓
[AVAudioEngine Manual Rendering]
        ↓
[AUNBandEQ chain (up to 64 bands across multiple units)]
        ↓
[Output HAL Unit] → [Output Device]
```

**Key Components:**

| Component | File | Purpose |
|-----------|------|---------|
| `HALIOManager` | `HALIOManager.swift` | Manages a single HAL audio unit in `.inputOnly` or `.outputOnly` mode |
| `RenderPipeline` | `RenderPipeline.swift` | Orchestrates two HAL managers + AVAudioEngine |
| `AudioRingBuffer` | `AudioRingBuffer.swift` | Lock-free SPSC buffer for inter-callback audio transfer |
| `ManualRenderingEngine` | `ManualRenderingEngine.swift` | AVAudioEngine configured for offline/manual rendering |
| `RenderCallbackContext` | `RenderCallbackContext.swift` | Pre-allocated buffers passed to audio callbacks |

### Menu Bar App

The app uses SwiftUI's native `MenuBarExtra` for the menu bar interface:

- **`MenuBarExtra`**: Provides the menu bar icon and popover window
- **`Window(id:)`**: Separate window for detailed EQ controls, opened on demand
- **No `AppDelegate`**: Pure SwiftUI app lifecycle with `@main` struct

```swift
@main
struct EqualizerAppMain: App {
    var body: some Scene {
        Window("Equalizer Settings", id: "eq-settings") { ... }
        MenuBarExtra("Equalizer", systemImage: "slider.horizontal.3") { ... }
            .menuBarExtraStyle(.window)
    }
}
```

## SwiftUI App Lifecycle Learnings

Critical knowledge for menu bar apps using SwiftUI's `@main` lifecycle.

### NSApp Availability

`NSApp` (aka `NSApplication.shared`) is **nil** during the `@main` struct's `init()`. Any code that accesses `NSApp` must be deferred:

```swift
// WRONG - crashes with nil unwrap
init() {
    NSApp.setActivationPolicy(.accessory)  // NSApp is nil here!
}

// CORRECT - defer to next run loop
init() {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.accessory)  // NSApp exists now
    }
}
```

### Hiding the Dock Icon

For a menu-bar-only app, use `.accessory` activation policy:

```swift
DispatchQueue.main.async {
    NSApp.setActivationPolicy(.accessory)
}
```

This hides the dock icon while keeping the menu bar extra visible.

### Opening Windows Programmatically

Use `@Environment(\.openWindow)` with a window ID:

```swift
@Environment(\.openWindow) private var openWindow

Button("Open Settings") {
    openWindow(id: "eq-settings")
    NSApp.activate(ignoringOtherApps: true)  // Bring to front
}
```

## Core Audio Learnings

Critical knowledge for working with HAL audio units in this codebase.

### What Works

| Pattern | Description |
|---------|-------------|
| Dual HAL units | Use separate `HALIOManager` instances for input and output devices |
| Ring buffer | `AudioRingBuffer` decouples input/output device clocks safely |
| Input callback | Register via `kAudioOutputUnitProperty_SetInputCallback` on input-only HAL |
| Non-interleaved format | Use `kAudioFormatFlagIsNonInterleaved` Float32 for AVAudioEngine compatibility |
| Manual rendering | `AVAudioEngine.enableManualRenderingMode()` for offline processing in callbacks |

### What Does NOT Work

| Approach | Problem | Error |
|----------|---------|-------|
| Single HAL for input+output | `kAudioOutputUnitProperty_CurrentDevice` is global; setting input device overwrites output | -10851 |
| AudioUnitRender on input-only HAL from output callback | Input HAL captures asynchronously via its own IOProc; cannot be pulled on-demand | -10863 |
| Synchronous cross-device pull | Different device clocks cause drift and glitches | Audio artifacts |

### Error Codes Reference

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `noErr` | Success |
| -50 | `paramErr` | Buffer format mismatch or invalid parameter |
| -10851 | `kAudioUnitErr_InvalidPropertyValue` | Device/property not valid for this scope |
| -10863 | `kAudioUnitErr_NoConnection` | No input connected to pull from (wrong architecture) |

### HAL Audio Unit Scopes and Elements

Understanding scopes and elements is critical for HAL configuration:

```
                    ┌─────────────────────────────────────┐
                    │         HAL Audio Unit              │
                    │                                     │
[Hardware Input] ──▶│ Element 1 (Input)                   │
                    │   - Input Scope: hardware format    │
                    │   - Output Scope: client format ────┼──▶ [Your Callback]
                    │                                     │
[Your Callback] ───▶│ Element 0 (Output)                  │
                    │   - Input Scope: client format      │
                    │   - Output Scope: hardware format ──┼──▶ [Hardware Output]
                    └─────────────────────────────────────┘
```

**Key Points:**
- **Element 1** = Input path (microphone/capture)
- **Element 0** = Output path (speakers/playback)
- For input-only: enable Element 1, disable Element 0
- For output-only: enable Element 0 (default), Element 1 stays disabled
- Set client format on the "opposite" scope (Output scope of Element 1 for input, Input scope of Element 0 for output)

## Entitlements

The app requires:
- `com.apple.security.app-sandbox` (enabled)
- `com.apple.security.device.audio-input` (microphone/audio routing)

## Development Notes

- **BlackHole 2ch**: Optional loopback driver for system audio routing
- **Roadmap**: See `ToDo.md` for current development phase (HAL-based routing)
- **Permissions**: App will prompt for microphone access on first launch

## Common Tasks

### Adding a New Source File

1. Create `.swift` file in `Sources/`
2. No need to modify `Package.swift` (auto-discovered)

### Adding a Test

1. Create test class in `Tests/`
2. Import with `@testable import EqualizerApp`
3. Run with `swift test --filter YourTestClass`

### Modifying EQ Bands

Update band settings via `EQConfiguration` methods:
- `updateBandGain(index:gain:)` - runtime gain adjustment
- `updateBandFrequency(index:frequency:)` - change center frequency
- `updateBandBandwidth(index:bandwidth:)` - change Q/bandwidth
- `updateBandFilterType(index:filterType:)` - change filter type

Call `ManualRenderingEngine.reapplyConfiguration()` to reapply all settings at once.
