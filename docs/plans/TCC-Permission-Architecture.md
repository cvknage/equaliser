# TCC Permission Architecture

## Problem Statement

The Equaliser app shows a microphone permission dialog at launch in all capture modes, including shared memory mode which doesn't require microphone access.

## Root Cause Analysis

### The Trigger

The TCC dialog appears when `AudioComponentInstanceNew()` is called with `kAudioUnitSubType_HALOutput`:

```
RenderPipeline.configure()
  → HALIOManager(mode: .outputOnly)
    → createAudioUnit()
      → AudioComponentInstanceNew(kAudioUnitSubType_HALOutput)
        → 🚨 TCC permission check triggered
```

This happens in `src/services/audio/hal/HALIOManager.swift` at line 136.

### Why HALOutput Triggers TCC

The `kAudioUnitSubType_HALOutput` AudioUnit is a **dual-purpose** unit:
- Can be configured for **output-only** (element 0)
- Can be configured for **input-only** (element 1)
- Can be configured for **full-duplex** (both elements)

macOS checks microphone permission when this AudioUnit type is instantiated, even if:
- Only output element is enabled
- No input stream will ever be opened
- The app is using shared memory capture

This is a privacy-first design by Apple — the AudioUnit type itself is flagged as "potentially accessing microphone."

### Timeline from Investigation

From user testing and log analysis:

1. App initializes, UI shows "Audio Routing Stopped" (`.idle`)
2. `reconfigureRouting()` is called
3. `HALIOManager.configure()` creates `HALOutput` AudioUnit
4. `AudioComponentInstanceNew()` triggers TCC permission check
5. TCC dialog appears, blocking main thread until user responds
6. After user grants/denies permission, routing starts

## Potential Solutions

### Option 1: AVAudioEngine with Output Node

Use `AVAudioEngine` for output-only routing instead of raw `HALOutput` AudioUnit.

**Pros:**
- Higher-level API, potentially TCC-avoids for output-only
- Automatic format conversion
- Built-in connection management

**Cons:**
- May still trigger TCC (internal implementation uses HAL units)
- Less control over buffer timing
- Higher latency potential
- Requires significant refactoring

**Investigation needed:**
- Test if `AVAudioEngine` + `AVAudioOutputNode` avoids TCC for output-only
- Benchmark latency comparison with current HAL implementation

### Option 2: AudioDeviceIOProc Direct Callbacks

Use `AudioDeviceCreateIOProcID()` to create output callbacks directly on the device, bypassing AudioUnit entirely for output.

**Pros:**
- Direct device I/O, no AudioUnit intermediate
- Potentially no TCC trigger for output-only
- Lower latency than AudioUnit
- Already familiar pattern (used in shared memory capture)

**Cons:**
- No format conversion (must match device format exactly)
- More complex buffer management
- Need separate input path for HAL mode
- Requires device ID management

**Investigation needed:**
- Verify `AudioDeviceIOProc` doesn't trigger TCC for output-only
- Test format handling for various output devices

### Option 3: Conditional AudioUnit Creation

Create `HALOutput` AudioUnit only when actually needed for HAL input mode. Use `AudioDeviceIOProc` for output in shared memory mode.

**Architecture:**
```
Shared Memory Mode:
  RenderPipeline
    └── AudioDeviceIOProc (output device)
        └── DriverCapture (shared memory read)
            └── EQ processing
            └── Output callback

HAL Input Mode:
  RenderPipeline
    ├── HALIOManager (input device)
    │   └── AudioUnit (input element)
    └── HALIOManager (output device)
        └── AudioUnit (output element)
```

**Pros:**
- Shared memory mode avoids TCC entirely
- HAL input mode already requires permission
- Clean separation of concerns
- Minimal code duplication

**Cons:**
- Two code paths for output
- More complex pipeline management
- Need careful testing of both paths

**Investigation needed:**
- Refactor `RenderPipeline` to support two output backends
- Ensure format handling works for both paths
- Test timing synchronization

### Option 4: kAudioUnitSubType_DefaultOutput

Use `kAudioUnitSubType_DefaultOutput` for shared memory mode output.

**Pros:**
- Simpler than HALOutput
- May avoid TCC

**Cons:**
- No device selection (always outputs to system default)
- Doesn't support named device routing
- Breaks the core functionality of device selection
- Still may trigger TCC (unverified)

**Verdict:** Not viable for Equaliser's requirements.

## Recommended Investigation Order

1. **Test AudioDeviceIOProc** — Create minimal test app to verify TCC behavior for output-only
2. **Test AVAudioEngine** — Verify if output-only engine avoids TCC
3. **Prototype conditional creation** — If AudioDeviceIOProc works, prototype Option 3

## Test Matrix

| Backend | Capture Mode | TCC Expected | Device Selection | Status |
|---------|--------------|--------------|------------------|--------|
| AudioUnit (current) | HAL Input | Yes | ✓ | Production |
| AudioUnit (current) | Shared Memory | Yes | ✓ | Production |
| Direct (AudioDeviceIOProc) | Shared Memory | Unknown | ✓ | Needs test |
| AVAudioEngine | Shared Memory | Unknown | Limited | Needs test |

## Questions for Investigation

1. Does `AudioDeviceCreateIOProcID()` for output-only avoid TCC?
2. Does `AVAudioEngine` for output-only avoid TCC?
3. What is the latency impact of `AudioDeviceIOProc` vs HAL unit?
4. Does `kAudioUnitSubType_DefaultOutput` avoid TCC?

## References

- [Apple: AudioUnit Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioUnitProgrammingGuide/)
- [Apple: Audio Hardware Services](https://developer.apple.com/documentation/coreaudio/audio_hardware_services)
- [Apple: AudioDeviceIOProc](https://developer.apple.com/documentation/coreaudio/1443902-audiodevicesetioProcCallback)