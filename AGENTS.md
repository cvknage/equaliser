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
| Package Root | `EqualizerApp/` (contains `Package.swift`)        |

## Build Commands

All commands must be run from the `EqualizerApp/` directory:

```bash
cd EqualizerApp

# Build (debug)
swift build

# Build (release)
swift build -c release

# Run the app
swift run

# Clean build artifacts
swift package clean
```

Or open `EqualizerApp/Package.swift` directly in Xcode 16+ (File > Open Package).

## Test Commands

```bash
cd EqualizerApp

# Run all tests
swift test

# Run a single test class
swift test --filter EqualizerAppTests

# Run a single test method
swift test --filter EqualizerAppTests.testExample

# Run tests with verbose output
swift test --verbose
```

Test files are located in `EqualizerApp/Tests/EqualizerAppTests/`.

## Project Structure

```
equalizer/
├── AGENTS.md                 # This file
├── ToDo.md                   # Project roadmap
└── EqualizerApp/
    ├── Package.swift         # SPM manifest
    ├── EqualizerApp.entitlements
    ├── Sources/EqualizerApp/
    │   ├── EqualizerAppApp.swift      # @main entry point
    │   ├── AppDelegate.swift          # NSApplicationDelegate, menu bar
    │   ├── EqualizerStore.swift       # Global state (ObservableObject)
    │   ├── AudioEngineManager.swift   # AVAudioEngine + EQ units
    │   ├── DeviceManager.swift        # Core Audio device enumeration
    │   ├── DevicePickerView.swift     # Device selection UI
    │   └── ParameterSmoother.swift    # Smooth parameter ramping (actor)
    └── Tests/EqualizerAppTests/
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

- **Main Actor**: Use `@MainActor` on UI-bound classes (`AppDelegate`, `EqualizerStore`, `AudioEngineManager`, `DeviceManager`)
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
- Owns reference to `AudioEngineManager`

### Audio Pipeline

- Dual `AUNBandEQ` units (16 bands each = 32 total)
- Connected via `AVAudioEngine` graph
- Parameter smoothing via `ParameterSmoother` actor

### Menu Bar App

- `AppDelegate` manages `NSStatusItem` and `NSPopover`
- SwiftUI views hosted via `NSHostingController`

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

1. Create `.swift` file in `EqualizerApp/Sources/EqualizerApp/`
2. No need to modify `Package.swift` (auto-discovered)

### Adding a Test

1. Create test class in `EqualizerApp/Tests/EqualizerAppTests/`
2. Import with `@testable import EqualizerApp`
3. Run with `swift test --filter YourTestClass`

### Modifying EQ Bands

Update `AudioEngineManager.configureBands()` for frequency/bandwidth changes.
Use `updateBandGain(index:gain:)` for runtime adjustments.
