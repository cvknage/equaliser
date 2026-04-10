# CoreAudio Expertise

Deep knowledge of CoreAudio, HAL, AudioUnits, and macOS audio device management.

## HAL Audio Unit Scopes

```
[Hardware] ────▶│ Element 1 (Input)  │──▶ [Your Callback]
[Callback] ────▶│ Element 0 (Output) │──▶ [Hardware]
```

- Set client format on opposite scope
- Input-only: enable Element 1, disable Element 0
- The app uses `kAudioUnitSubType_HALOutput` for device routing because it supports both input and output configuration

## HALIOManager

`HALIOManager` wraps a single `kAudioUnitSubType_HALOutput` AudioUnit. It can operate in:
- **Output-only mode**: For the output device (standard mode)
- **Input mode**: For HAL input capture (legacy mode)

Key implementation details:
- Uses `AudioComponentInstanceNew` to create the AudioUnit
- Configures element enable/disable based on mode
- Sets client format on the opposite scope (output scope for input, input scope for output)
- `kAudioUnitSubType_HALOutput` triggers TCC permission at instantiation regardless of actual usage

## Audio Pipeline Architecture

### Standard Capture (HAL Input)

Uses HAL input stream. Triggers macOS microphone indicator.

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

### Shared Memory Capture (Default)

Uses lock-free shared memory via mmap. No TCC permission required. Audio goes directly from shared memory to EQ processing — no intermediate ring buffer needed since both poll and render run on the same output thread.

```
┌──────────────┐     ┌────────────────────────────────────┐
│ Equaliser    │ ──▶ │ Driver WriteMix                    │
│ Driver       │     │ (audio stored in shared memory)    │
└──────────────┘     └────────────────────────────────────┘
                                    │
                                    ▼ (mmap, lock-free)
                           ┌────────────────────┐
                           │ DriverCapture      │
                           │ pollIntoBuffers()  │
                           └────────────────────┘
                                    │
                                    ▼ (direct, same thread)
┌──────────────┐     ┌──────────────┐     ┌────────────────────┐
│ Output Device│ ◀── │  Output HAL  │ ◀── │ Output Callback    │
└──────────────┘     └──────────────┘     │ + EQ (64 bands)    │
                                          └────────────────────┘
```

### Capture Mode Comparison

| Mode | Method | TCC Permission | Use Case |
|------|--------|----------------|----------|
| `sharedMemory` (default) | Lock-free ring buffer via mmap | NOT required | Default, recommended |
| `halInput` | HAL input stream (AudioUnitRender) | Required | Legacy, fallback |

- Default mode uses shared memory, no orange microphone indicator in Control Center
- HAL input mode is fallback for users who want/already have mic permission
- Capture mode is persisted and restored across launches
- Manual mode always uses HAL input (regardless of preference)

## Routing Modes

| Mode | Input | Output | Use Case |
|------|-------|--------|----------|
| Automatic | Equaliser driver | macOS default | Recommended |
| Manual | User-selected | User-selected | Advanced |

## Device Management

### Device Enumeration

- `DeviceEnumerationService` conforms to `Enumerating` protocol
- Publishes `inputDevices` and `outputDevices` via `@Published`
- Caches device lists — `device(forUID:)` and `deviceID(forUID:)` search cached lists only, not CoreAudio directly
- For the driver special case, `driverAccess?.deviceID` provides direct CoreAudio lookup without requiring input device enumeration (TCC avoidance)

### Device Selection

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

### Headphone Auto-Switch

The app automatically switches output to headphones when plugged in, matching macOS behaviour.

| Platform | Detection Method |
|----------|------------------|
| Apple Silicon | Built-in device count change (`+1` = headphones) |
| Intel Mac | `kAudioDevicePropertyJackIsConnected` property |

Key behaviour:
- Only switches when current output is built-in (never steals from USB/Bluetooth/HDMI)
- Saves current device to history before switching
- Works in automatic mode only (respects manual mode)

## TCC Permission Architecture

The audio pipeline uses `kAudioUnitSubType_HALOutput` for device routing. This AudioUnit type triggers macOS microphone permission at instantiation, regardless of actual usage. However, the app only instantiates the pipeline when routing is active, and only checks/request permission based on the current `RoutingMode`:

1. `AutomaticRoutingMode` + shared memory capture: no permission needed (default)
2. `AutomaticRoutingMode` + HAL input: permission checked before starting
3. `ManualRoutingMode`: always requires permission (uses HAL input)

The `PermissionRequesting` protocol abstracts permission checking so the coordinator doesn't depend on `AVAudioApplication` directly.

```
RenderPipeline.configure()
  → HALIOManager(outputOnly)
    → AudioComponentInstanceNew(kAudioUnitSubType_HALOutput)
      → TCC permission check triggered
```

### Permission Handling Implementation

The app does **NOT** request microphone permission on launch. Permission is only requested when needed, determined by the current `RoutingMode`:

| Mode | When Permission Required |
|------|-------------------------|
| Automatic + Shared Memory | NEVER (default) |
| Automatic + HAL Input | When user switches capture mode in Settings |
| Manual | When user switches to manual mode |

Permission logic is checked via `RoutingMode.needsMicPermission`:
- `AutomaticRoutingMode.needsMicPermission` returns `true` only for HAL input capture mode
- `ManualRoutingMode.needsMicPermission` returns `true` (manual mode always uses HAL input)

```swift
// Permission check via RoutingMode protocol
if routingMode.needsMicPermission {
    guard permissionService.isMicPermissionGranted else {
        // Show permission prompt or error
        return
    }
}

// Permission requested via PermissionRequesting protocol
let granted = await permissionService.requestMicPermission()
```

Key points:
- Shared memory capture is the default (no TCC permission)
- User must explicitly opt in to HAL input capture
- Permission check is sync (`recordPermission`), request is async
- Error shown in UI if permission denied while attempting to start routing

See `docs/dev/TCC-Permission-Architecture.md` for root cause analysis and potential solutions.

## nonisolated CoreAudio Calls

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

**Why this matters**: CoreAudio caches device names. Without `refreshDevices()`, the UI shows stale driver names after renaming.

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