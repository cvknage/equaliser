# Known Issues & Gotchas

Hard-won knowledge from debugging sessions. These are non-obvious behaviours that have caused bugs.

## NSApp Timing

`NSApp` is **nil** during `@main` init. Defer access:

```swift
init() {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

**Why**: The SwiftUI app lifecycle creates `NSApp` lazily. Accessing it during `@main` init returns `nil`, causing a crash or no-op. Deferring to the next run loop iteration ensures `NSApp` is available.

## Boost Gain Always Applied

Boost gain (for driver volume compensation) must **always** be applied, even in bypass mode. Input/output gains are skipped in bypass.

```swift
// Boost is ALWAYS applied (not inside bypass check)
context.applyGain(to: context.inputSampleBuffers, ...)

// Input gain is skipped in bypass mode
if context.processingMode != 0 {
    context.applyGain(to: context.inputSampleBuffers, ...)
}
```

**Why**: Boost gain compensates for driver volume attenuation. Without it, bypass mode would sound quieter than the original signal.

## Driver Name Refresh Pattern

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

**Why**: CoreAudio caches device names. Without `refreshDevices()`, the UI shows stale driver names after renaming.

## DriverNameManager Call Site Responsibility

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

**Why**: The fire-and-forget GCD dispatch inside `updateDriverName()` is only for UI refresh. The audio pipeline must start with the driver already set as the default output device.

## Fire-and-Forget vs Async

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

**Why**: `Task.sleep` is an async suspension point. When called from a context where the audio pipeline needs to start synchronously afterward, the suspension causes audio to route through the wrong device for the duration of the sleep.

## Device Lookup Safety

`device(forUID:)` and `deviceID(forUID:)` search cached device lists only — they don't call CoreAudio directly. This is safe to call with any UID.

For the driver special case, `driverAccess?.deviceID` provides direct CoreAudio lookup without requiring input device enumeration (TCC avoidance).

**Why**: Direct CoreAudio calls for device lookup would trigger TCC permission prompts. Cached lookups are sufficient for all UI and routing logic.

## Headphone Auto-Switch

The app automatically switches output to headphones when plugged in, matching macOS behaviour.

| Platform | Detection Method |
|----------|------------------|
| Apple Silicon | Built-in device count change (`+1` = headphones) |
| Intel Mac | `kAudioDevicePropertyJackIsConnected` property |

Key behaviour:
- Only switches when current output is built-in (never steals from USB/Bluetooth/HDMI)
- Saves current device to history before switching
- Works in automatic mode only (respects manual mode)

## TCC Permission and Capture Mode

Permission requirements depend on routing mode and capture mode:

| Mode | Capture | Permission Required |
|------|---------|-------------------|
| Automatic | Shared Memory (default) | NEVER |
| Automatic | HAL Input | Yes, on mode switch |
| Manual | Any | Yes, on mode switch |

The `RoutingMode.needsMicPermission` property determines whether permission is checked. `ManualRoutingMode` always requires mic permission (uses HAL input). `AutomaticRoutingMode` only requires it for HAL input capture mode.

## Preset Backward Compatibility

`PresetSettings` uses a custom `Decodable` implementation for backward compatibility with presets saved before the custom DSP migration:

- `decodeIfPresent` for new fields (`channelMode`, `rightBands`) with sensible defaults
- `FilterType` raw values match legacy `AVAudioUnitEQFilterType` values — no migration needed
- `PresetBand.filterType` validates raw values and falls back to `.parametric`

**Why**: Presets are user data files that must continue to work across app updates. Adding new fields without defaults would break existing presets.