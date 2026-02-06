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

## 5. HAL-Based Routing (Current Focus)
### HALIOManager foundation
- [ ] Create `HALIOManager` owning a `kAudioUnitSubType_HALOutput` Audio Unit.
- [ ] Enable input/output scopes and expose `setInputDevice(id:)` / `setOutputDevice(id:)` helpers.
- [ ] Read device stream formats (ASBD) and apply them to the HAL unit for each scope.
- [ ] Add lifecycle controls (`initialize`, `start`, `stop`, `uninitialize`) with structured logging + error propagation.

### Manual render pipeline
- [ ] Register HAL input/output callbacks that pass audio buffers to/from the EQ pipeline.
- [ ] Run the dual `AUNBandEQ` chain via `AVAudioEngine` manual rendering (or equivalent AUGraph) and handle buffer/latency alignment.
- [ ] Guard against rate mismatches (resample or reject) and zero-fill if the EQ render returns insufficient data.

### Store & UI integration
- [ ] Update `EqualizerStore` to own `HALIOManager`, persist selected device UIDs, and trigger rebuilds on change/hot-swap.
- [ ] Surface routing status/errors to the menu UI (e.g., "Routing BlackHole ▶︎ Built-in Output" or warning on failure).
- [ ] Add optional level meter or debug log toggle so we can verify signal presence without leaving the app.

### Testing & validation
- [ ] Scenario: macOS output → BlackHole, app input=BlackHole, output=Built-in Output; verify audio through speakers.
- [ ] Scenario: hot-swap output (e.g., to headphones) mid-stream and confirm seamless switch.
- [ ] Scenario: device removed or mic permission denied; ensure graceful fallback messaging.

## 5. Equalizer Controls UI
- [ ] Design compact 32-band controls (group sliders or paged sections) with gain/Q/frequency readouts.
- [ ] Add fine-adjust increment buttons and keyboard nudging for focused bands.
- [ ] Display real-time level meters or band activity indicators (optional stretch goal).

## 6. Presets & Profiles
- [ ] Create preset model (name + 32 band settings + metadata).
- [ ] Support save, rename, delete, and quick-apply presets from the popover.
- [ ] Provide a default "Flat" preset and optionally ship a few sample curves.

## 7. Onboarding & Settings
- [ ] Offer a lightweight settings window for startup behavior and BlackHole instructions.
- [ ] Include a global bypass toggle and emergency reset-to-flat control.
- [ ] Add analytics/diagnostics hooks if needed (log gain changes, device switches).

## 8. Testing & Release Prep
- [ ] Add unit tests for band-mapping logic and preset serialization.
- [ ] Build an integration harness that feeds sample audio through both EQ units for verification.
- [ ] Prepare signed/notarized builds and optionally integrate Sparkle or TestFlight for updates.
