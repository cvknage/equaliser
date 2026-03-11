# Equaliser Roadmap

A sequential plan so we can ship the menu-bar equalizer step by step.

## 1. Bootstrap the Project (Completed)
- [x] Create a new SwiftUI macOS app targeting macOS 15+ on Apple Silicon.
- [x] Configure signing, hardened runtime, and microphone/audio entitlements.
- [x] Add basic README notes on installing BlackHole 2ch for loopback use.

## 2. Core Application Shell (Completed)
- [x] Implement the menu-bar status item with a SwiftUI popover host view.
- [x] Set up a shared `EqualiserStore` (ObservableObject) for global state.
- [x] Persist minimal preferences (selected devices, bypass state) via UserDefaults.

## 3. Audio Engine Foundation (Completed)
- [x] Build `AudioEngineManager` around `AVAudioEngine` with input/output nodes.
- [x] Insert two `AUNBandEQ` units (bands 1–16 and 17–32) plus optional limiter node.
- [x] Add smooth parameter ramping utilities to avoid zipper noise.

## 4. Device Selection Flow (Completed)
- [x] Implement `DeviceManager` to list Core Audio input/output devices (including BlackHole).
- [x] Allow users to pick input/output from the menu UI and reconfigure the engine safely.
- [x] Remember the last-used devices and auto-reconnect on launch.

## 5. HAL-Based Routing (Completed)
### HALIOManager foundation
- [x] Create `HALIOManager` owning a `kAudioUnitSubType_HALOutput` Audio Unit.
- [x] Enable input/output scopes and expose `setInputDevice(id:)` / `setOutputDevice(id:)` helpers.
- [x] Read device stream formats (ASBD) and apply them to the HAL unit for each scope.
- [x] Add lifecycle controls (`initialize`, `start`, `stop`, `uninitialize`) with structured logging + error propagation.

### Dual HAL Architecture
- [x] Refactor to use two separate HAL units (one input-only, one output-only) since a single HAL unit can only connect to one physical device.
- [x] Add `HALIOMode` enum (`.inputOnly`, `.outputOnly`) to configure each unit appropriately.
- [x] Implement ring buffer (`AudioRingBuffer.swift`) for lock-free audio transfer between input and output callbacks.
- [x] Register input callback on input HAL unit to capture audio and write to ring buffer.
- [x] Register output callback on output HAL unit to read from ring buffer and process through EQ.

### Manual render pipeline
- [x] Register HAL input/output callbacks that pass audio buffers to/from the EQ pipeline.
- [x] Run the dual `AUNBandEQ` chain via `AVAudioEngine` manual rendering and handle buffer/latency alignment.
- [x] Guard against rate mismatches (resample or reject) and zero-fill if the EQ render returns insufficient data.

### Store & UI integration
- [x] Update `EqualiserStore` to own `RenderPipeline`, persist selected device UIDs, and trigger rebuilds on change.
- [x] Surface routing status/errors to the menu UI (e.g., "BlackHole 2ch → Built-in Output" or warning on failure).
- [x] Add Start/Stop routing buttons with proper state management.
- [x] Add optional level meter or debug log toggle so we can verify signal presence without leaving the app.
- [x] Add device hot-swap handling (listener for device changes).

### Testing & validation
- [x] Scenario: macOS output → BlackHole, app input=BlackHole, output=Built-in Output; verified audio through speakers.
- [x] Scenario: hot-swap output (e.g., to headphones) mid-stream and confirm seamless switch.
- [ ] Scenario: device removed or mic permission denied; ensure graceful fallback messaging.

## 6. Window Architecture (Completed)
- [x] Refactor app to use `MenuBarExtra` + `Window` instead of `WindowGroup` + `AppDelegate` popover.
- [x] Hide dock icon permanently (`NSApp.setActivationPolicy(.accessory)`).
- [x] Add "Open EQ Settings" button in menu bar popover to show main window.
- [x] Create placeholder `EQWindowView` for the main EQ window.
- [x] Move mic permission request from `AppDelegate` to app initialization.
- [x] Remove `AppDelegate` (no longer needed with `MenuBarExtra`).
- [x] Main window should hide (not close) when user clicks close button.

### Window Roles

| Window | Purpose |
|--------|---------|
| Menu Bar Popover | Quick access: device selection, routing, bypass, preset picker, open EQ settings |
| Main EQ Window | Detailed 32-band EQ controls, preset management, advanced settings |

## 7. Equaliser Controls UI (Completed)
- [x] Design compact 32-band controls in the main EQ window (horizontal scrolling sliders).
- [x] Add gain/frequency readouts for each band.
- [x] Add "Flatten" button to reset all bands to 0 dB.
- [x] Double-tap on any band slider to reset it to 0 dB.
- [ ] Add fine-adjust increment buttons and keyboard nudging for focused bands (optional).
- [x] Display real-time level meters or band activity indicators (optional stretch goal).

## 8. Presets & Profiles (Completed)
- [x] Create preset model (name + band settings + metadata) in `PresetModel.swift`.
- [x] Add preset dropdown/list to menu bar popover for quick switching (`CompactPresetPicker`).
- [x] Support save, rename, delete presets in main EQ window (`PresetToolbar`, `SavePresetSheet`).
- [x] Presets stored in `.eqpreset` JSON files at `~/Library/Application Support/Equaliser/Presets/`.
- [x] Add EasyEffects import/export support with Q-to-bandwidth conversion.
- [x] Add user preference to display bandwidth as octaves or Q factor.
- [x] Include factory presets: Flat, Bass Boost, Treble Boost, Vocal Presence, Loudness, Acoustic.
- [x] Show "modified" indicator when current settings differ from loaded preset.

## 9. Testing & Release Prep
- [x] Add unit tests for band-mapping logic and preset serialization.
- [x] Add release script to bundle and package application as a .dmg.
- [ ] Prepare signed/notarized builds and optionally integrate Sparkle or TestFlight for updates.

## 10. Bypass & Compare Mode (Completed)

- [x] System EQ toggle (master bypass) — complete bypass of EQ and gains when OFF
- [x] Compare mode segmented control ([EQ|Flat]) — A/B comparison with gains still applied in Flat mode
- [x] Auto-revert timer (5 minutes) to switch back to EQ from Flat
- [x] Thread-safe bypass flag access using atomic operations
- [x] Help button (?) with popover explaining Compare Mode

## 11. GPU-Rendered Meters (Completed)
- [x] Replace SwiftUI shape-based meters with `NSView` + Core Animation (CALayer/CAGradientLayer)
- [x] Leverage GPU-accelerated rendering without Metal complexity
- [x] Target 30 FPS smooth animations with minimal CPU overhead
- [x] Use observer pattern for direct meter updates bypassing SwiftUI re-rendering

## 12. Built-in Virtual Audio Device
- [ ] Bundle a custom Core Audio kernel extension or AudioServerPlugIn
- [ ] Eliminate dependency on third-party tools like BlackHole or Loopback
- [ ] Provide one-click setup: app creates its own virtual input/output endpoints

## 13. Application-Specific Routing
- [ ] Allow users to select which applications route through the EQ (e.g., Spotify, Safari)
- [ ] Build app picker UI showing all audio-producing processes with icons
- [ ] Handle apps that launch/quit dynamically (add/remove from routing list)
- [ ] Support excluding specific apps from processing while others pass through

## 14. Multiple EQ Chains
- [ ] Support parallel or serial EQ configurations (e.g., one for music, one for voice)
- [ ] Allow chaining multiple EQ presets with different band counts
- [ ] Design UI for managing EQ chain slots (add/remove/reorder)
- [ ] Consider latency implications of serial processing

