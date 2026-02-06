# Equalizer App Roadmap

A sequential plan so we can ship the menu-bar equalizer step by step.

## 1. Bootstrap the Project
- [x] Create a new SwiftUI macOS app targeting macOS 15+ on Apple Silicon.
- [x] Configure signing, hardened runtime, and microphone/audio entitlements.
- [x] Add basic README notes on installing BlackHole 2ch for loopback use.

## 2. Core Application Shell
- [x] Implement the menu-bar status item with a SwiftUI popover host view.
- [x] Set up a shared `EqualizerStore` (ObservableObject) for global state.
- [x] Persist minimal preferences (selected devices, bypass state) via UserDefaults.

## 3. Audio Engine Foundation
- [x] Build `AudioEngineManager` around `AVAudioEngine` with input/output nodes.
- [x] Insert two `AUNBandEQ` units (bands 1–16 and 17–32) plus optional limiter node.
- [x] Add smooth parameter ramping utilities to avoid zipper noise.

## 4. Device Selection Flow
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
- [x] Update `EqualizerStore` to own `RenderPipeline`, persist selected device UIDs, and trigger rebuilds on change.
- [x] Surface routing status/errors to the menu UI (e.g., "BlackHole 2ch → Built-in Output" or warning on failure).
- [x] Add Start/Stop routing buttons with proper state management.
- [ ] Add optional level meter or debug log toggle so we can verify signal presence without leaving the app.
- [ ] Add device hot-swap handling (listener for device changes).

### Testing & validation
- [x] Scenario: macOS output → BlackHole, app input=BlackHole, output=Built-in Output; verified audio through speakers.
- [ ] Scenario: hot-swap output (e.g., to headphones) mid-stream and confirm seamless switch.
- [ ] Scenario: device removed or mic permission denied; ensure graceful fallback messaging.

## 6. Window Architecture (Completed)
- [x] Refactor app to use `MenuBarExtra` + `Window` instead of `WindowGroup` + `AppDelegate` popover.
- [x] Hide dock icon permanently (`NSApp.setActivationPolicy(.accessory)`).
- [x] Add "Open EQ Settings" button in menu bar popover to show main window.
- [x] Create placeholder `EQWindowView` for the main EQ window.
- [x] Move mic permission request from `AppDelegate` to app initialization.
- [x] Remove `AppDelegate` (no longer needed with `MenuBarExtra`).
- [ ] Main window should hide (not close) when user clicks close button.

### Window Roles

| Window | Purpose |
|--------|---------|
| Menu Bar Popover | Quick access: device selection, routing, bypass, preset picker, open EQ settings |
| Main EQ Window | Detailed 32-band EQ controls, preset management, advanced settings |

## 7. Equalizer Controls UI (Completed)
- [x] Design compact 32-band controls in the main EQ window (horizontal scrolling sliders).
- [x] Add gain/frequency readouts for each band.
- [x] Add "Flatten" button to reset all bands to 0 dB.
- [x] Double-tap on any band slider to reset it to 0 dB.
- [ ] Add fine-adjust increment buttons and keyboard nudging for focused bands (optional).
- [ ] Display real-time level meters or band activity indicators (optional stretch goal).

## 8. Presets & Profiles
- [ ] Create preset model (name + 32 band settings + metadata).
- [ ] Add preset dropdown/list to menu bar popover for quick switching.
- [ ] Support save, rename, delete presets in main EQ window.
- [ ] Provide a default "Flat" preset and optionally ship a few sample curves.

## 8. Onboarding & Settings
- [ ] Offer a lightweight settings window for startup behavior and BlackHole instructions.
- [ ] Include a global bypass toggle and emergency reset-to-flat control.
- [ ] Add analytics/diagnostics hooks if needed (log gain changes, device switches).

## 9. Testing & Release Prep
- [ ] Add unit tests for band-mapping logic and preset serialization.
- [ ] Build an integration harness that feeds sample audio through both EQ units for verification.
- [ ] Prepare signed/notarized builds and optionally integrate Sparkle or TestFlight for updates.
