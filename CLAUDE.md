# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

All commands run from `EqualizerApp/` directory:

```bash
swift build                              # Debug build
swift build -c release                   # Release build
swift run                                # Run the app
swift test                               # Run all tests
swift test --filter TestClass.testMethod # Run single test
```

Or use `--package-path /path/to/equalizer/EqualizerApp` from any directory.

## Architecture

macOS menu bar equalizer routing audio from input device → 32-band EQ → output device.

### Dual HAL Architecture

A single HAL audio unit can only connect to one device. Routing between two different devices requires **two HAL units** with a ring buffer:

```
[Input Device] → [Input HAL] → [Ring Buffer] → [Output HAL] → [Output Device]
                     ↓                              ↑
              Input Callback                  Output Callback
              (writes samples)                (reads + EQ renders)
```

**Why this matters:** You cannot pull audio from an input HAL unit in the output callback. Input captures asynchronously via its own IOProc. The ring buffer decouples the two independent device clocks.

### Key Components

| Component | Purpose |
|-----------|---------|
| `EqualizerStore` | Central @MainActor ObservableObject - owns RenderPipeline, persists to UserDefaults |
| `RenderPipeline` | Orchestrates dual HAL units + AVAudioEngine manual rendering |
| `HALIOManager` | Manages single HAL unit in `.inputOnly` or `.outputOnly` mode |
| `AudioRingBuffer` | Lock-free SPSC buffer (atomic indices only, real-time safe) |
| `ManualRenderingEngine` | AVAudioEngine in manual mode with 2× AUNBandEQ (16 bands each) |
| `RenderCallbackContext` | Pre-allocated buffers for audio callbacks |

### Concurrency Model (Swift 6 Strict)

- **@MainActor**: `EqualizerStore`, `EQConfiguration`, `DeviceManager`, `HALIOManager`, `RenderPipeline`
- **actor**: `ParameterSmoother` (smooth parameter ramping)
- **@unchecked Sendable**: `AudioRingBuffer`, `RenderCallbackContext` (audio thread access)
- **nonisolated(unsafe)**: Mutable state accessed from audio callbacks

### UI Architecture

- Pure SwiftUI with `@main` struct (no AppDelegate)
- `MenuBarExtra` for menu bar popover
- `Window(id:)` for EQ settings window
- Dock icon hidden via `NSApp.setActivationPolicy(.accessory)`

## Audio Thread Safety

Callbacks must never block. The codebase uses:
- Pre-allocated buffers in `RenderCallbackContext`
- Atomic operations only in ring buffer (no locks)
- Gain state as `nonisolated(unsafe)` variables

## Additional Documentation

See `AGENTS.md` for detailed code style guidelines, naming conventions, Core Audio learnings, and architecture diagrams.
