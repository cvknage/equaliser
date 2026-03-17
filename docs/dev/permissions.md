# macOS Audio Permissions and Microphone Indicator

## Overview

macOS displays an orange microphone indicator when applications access audio input streams. To avoid this indicator and the microphone permission requirement, the audio architecture must be redesigned to avoid input stream usage entirely.

## What Triggers the Indicator

macOS monitors for input stream activation. The following operations trigger the microphone indicator:

| Operation | Triggers Indicator |
|-----------|-------------------|
| `AVAudioEngine.inputNode` | Yes |
| `AudioDeviceStart` on input scope | Yes |
| HAL input stream (`kAudioUnitScope_Input`) | Yes |
| Custom property read (`AudioObjectGetPropertyData`) | No |

**Key rule:** Any user-space process that opens an input audio stream will trigger the indicator, regardless of whether the device is virtual or physical.

**Exception:** Reading audio data via custom driver properties does NOT trigger the indicator, because it's not classified as input stream usage.

## Proposed Architecture

To avoid the microphone indicator while still capturing system audio for processing, the driver exposes two separate audio devices with distinct purposes.

### Device 1: Output Device (Capture Device)

**Purpose:** Receives system audio as the default output device.

**Streams:**
- Output stream: Yes — system plays audio here
- Input stream: No — not exposed

**Visibility:** Hidden until app connects via `AddDeviceClient`, then shown in macOS **Output devices only** (not in Input devices).

**Driver behavior:**
- `WriteMix` operation: Audio from system is stored in shared buffer, silence is returned
- No `ReadInput` operation — there is no input stream

**Why output-only:** Not shown in macOS Input devices. Captures system audio without exposing an input stream that could trigger TCC.

### Device 2: Export Device (Access Device)

**Purpose:** Provides captured audio data to the application.

**Streams:**
- Input stream: Yes — available as fallback (triggers TCC if used)
- Output stream: No

**Custom property:**

```c
#define kEqualiserPropertyAudioBuffer 'eqab'

struct AudioBufferData {
    Float64 sampleRate;     // Current capture rate (e.g., 48000.0)
    UInt32 frameCount;      // Actual frames returned (may be less than requested)
    UInt32 channelCount;    // Always 2 (stereo)
    Float32 samples[];      // Interleaved L/R, frameCount * channelCount frames
};
```

- App requests max frames (its render callback size, e.g., 512)
- Driver returns `min(available, requested)` frames
- `frameCount` tells app how much is valid (pad with silence if less)
- `sampleRate` included so app can detect rate changes

**Visibility:** Hidden by default. Shown/hidden together with Device 1 (same visibility control).

**Naming:** Derived from driver name with "Mirror" or "Export" suffix (configurable).

### Sample Rate

The driver already matches the physical output device's sample rate. The `sampleRate` field in `AudioBufferData` allows the app to:
- Detect when the sample rate has changed
- Handle the uncommon case where rates differ between capture and output

No sample rate conversion (SRC) is typically needed since the driver matches the system rate.

### Meter Calculation

Meters are calculated in the app using existing `MeterMath` utilities — no additional driver property needed:

```swift
// After reading AudioBufferData:
let peakL = MeterMath.calculatePeak(buffer: samples, frameCount: frameCount)
let peakR = MeterMath.calculatePeak(buffer: samples + frameCount, frameCount: frameCount)
let rmsL = MeterMath.calculateRMS(buffer: samples, frameCount: frameCount)
let rmsR = MeterMath.calculateRMS(buffer: samples + frameCount, frameCount: frameCount)

// Feed into existing MeterStore for UI
```

This reuses the current meter implementation — same code path for both property-based capture and inputNode fallback.

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     System Audio                            │
│            (Spotify, Safari, Music, etc.)                   │
│                        ↓ plays to                           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   Device 1: Output                          │
│                                                             │
│  Output Stream ← receives all system audio                  │
│  Input Stream: NONE (not exposed)                           │
│  NOT shown in macOS Input devices                           │
│                                                             │
│  WriteMix: stores audio in shared buffer, returns silence   │
└─────────────────────────────────────────────────────────────┘
                              ↓ (audio stored in shared buffer)
┌─────────────────────────────────────────────────────────────┐
│                   Shared Ring Buffer                        │
│                                                             │
│  Accessible by both devices internally                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   Device 2: Export                          │
│                                                             │
│  Input Stream: Available (triggers TCC if used)             │
│  Custom Property: AudioBufferData (sampleRate, frames)      │
│                                                             │
│  Shown/hidden together with Device 1                        │
│  NOT shown in macOS Output devices                          │
└─────────────────────────────────────────────────────────────┘
                              ↓
                ┌─────────────┴─────────────┐
                │                           │
          Property Read              Input Stream
          (Primary, No TCC)         (Fallback, TCC)
                │                           │
                └─────────────┬─────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Application                            │
│                                                             │
│  Primary: Read buffer via custom property (no TCC)          │
│  Fallback: Read via inputNode if property fails (TCC)       │
│  Calculate meters using MeterMath (same for both paths)     │
│  Applies EQ processing                                      │
│  Sends to physical output device via HAL output             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  Physical Output Device                     │
│                   (Speakers / Headphones)                   │
└─────────────────────────────────────────────────────────────┘
```

### Primary Path (No TCC)

App reads audio via custom property on Device 2:

```swift
var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kEqualiserPropertyAudioBuffer,  // 'eqab'
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyData(exportDeviceID, &propertyAddress, ...)
```

- No input stream activation
- No microphone permission prompt
- No orange indicator

### Fallback Path (TCC Required)

If property read fails or is unavailable:

```swift
// Fall back to inputNode on Device 2
engine.setInputDevice(exportDeviceID)
// This triggers TCC microphone permission
```

- Input stream activation triggers TCC
- Always works as fallback
- Used when property-based access unavailable

### Fallback Detection Logic

```swift
func initializeAudioCapture() async throws {
    // Try property-based capture first
    if let bufferPropertySupported = try? checkAudioBufferProperty() {
        usePropertyBasedCapture()
        return
    }
    
    // Fall back to input stream (triggers TCC)
    try await useInputStreamCapture()
}
```

### Why This Avoids the Indicator

1. **Device 1 has no input stream** — Nothing for TCC to monitor on primary device
2. **App reads via custom property** — Property reads bypass input stream monitoring
3. **Device 2's input stream is unused (primary path)** — Never activated, no TCC trigger
4. **Fallback exists** — If property fails, input stream works (with TCC)

## The Entitlement

Once the architecture is implemented:

| Value | Behavior |
|-------|----------|
| `true` | App can access any input device (required for fallback) |
| `false` | App cannot access input devices (use after removing fallback) |

After implementation, the primary path works without any input stream activation.

## Existing Infrastructure

The Equaliser driver (`driver/src/EqualiserDriver.c`) already has infrastructure we can leverage:

| Component | Status | Location |
|-----------|--------|----------|
| Two-device architecture | ✅ Exists | `kObjectID_Device`, `kObjectID_Device2` |
| Shared ring buffer | ✅ Exists | `gRingBuffer` |
| Device stream config | ✅ Exists | `kDevice_HasInput`, `kDevice_HasOutput` defines |
| Device 2 hidden by default | ✅ Exists | `kDevice2_IsHidden = true` |
| Device visibility control | ✅ Exists | `kEqualiserPropertyName` ('eqnm') |
| IO operation handlers | ✅ Exists | `DoIOOperation` handles `ReadInput`/`WriteMix` |

## Implementation Roadmap

### Phase 1: Driver Modifications

**Objective:** Configure devices and add buffer property.

Tasks:
- [ ] Configure Device 1 as output-only:
  ```c
  #define kDevice_HasInput    false
  #define kDevice_HasOutput   true
  ```
- [ ] Keep Device 2 with input stream (for fallback):
  ```c
  #define kDevice2_HasInput   true
  #define kDevice2_HasOutput  false
  ```
- [ ] Add custom property for buffer access:
  ```c
  #define kEqualiserPropertyAudioBuffer 'eqab'
  
  struct AudioBufferData {
      Float64 sampleRate;
      UInt32 frameCount;
      UInt32 channelCount;
      Float32 samples[];
  };
  ```
- [ ] Implement property getter in device property handler
- [ ] Return `gRingBuffer` contents with sample rate and frame count
- [ ] Synchronize Device 2 visibility with Device 1

### Phase 2: Application Refactor

**Objective:** Use property-based capture with fallback.

Tasks:
- [ ] Add property detection: check if `kEqualiserPropertyAudioBuffer` exists
- [ ] Implement property-based buffer read using `AudioObjectGetPropertyData()`
- [ ] Create render callback to pull from buffer at output rate
- [ ] Handle `frameCount < requested` case (pad with silence for underrun)
- [ ] Calculate meters from buffer using existing `MeterMath` functions
- [ ] Feed meter data into existing `MeterStore` for UI
- [ ] Keep `inputNode` fallback for when property unavailable
- [ ] Continue using HAL output to physical device

### Phase 3: Remove Permission (Optional)

**Objective:** Eliminate microphone permission entirely.

Tasks:
- [ ] Remove `NSMicrophoneUsageDescription` from Info.plist
- [ ] Set `com.apple.security.device.audio-input` to `false` or remove
- [ ] Remove `AVAudioApplication.requestRecordPermission()` call
- [ ] Remove `inputNode` fallback code
- [ ] Verify app appears nowhere in System Settings → Privacy & Security → Microphone

## Technical Considerations

### Buffer Synchronization

- Use atomic operations or mutex for buffer read/write
- Handle wrap-around in ring buffer
- Driver writes at capture rate, app reads at output rate (should match)

### Latency

- Buffer read must match output rate to avoid drift
- Driver rate matches system rate, so no varispeed needed typically
- Latency = ring buffer position + property call overhead

### Sample Rate

- Driver matches Device 1 sample rate to physical output
- `AudioBufferData.sampleRate` reports current rate
- App can detect rate changes via this field

### Visibility Control

- Device 2 visibility mirrors Device 1 visibility
- Controlled via existing `kEqualiserPropertyName` property
- Both devices hidden until app client connects

### Meter Latency

- Meters calculated in app from buffer data
- No additional latency from driver property calls
- Same 30 FPS update rate as current implementation

## Summary

| Aspect | Current | Proposed |
|--------|---------|----------|
| Devices | 1 (input + output) | 2 (output-only + export) |
| App reads via | `inputNode` (TCC) | Property (no TCC), inputNode fallback |
| Meter calculation | Render callback | Same `MeterMath` from buffer |
| Microphone permission | Required | Not required (primary path) |
| Orange indicator | Yes | No (primary path) |
| Driver modifications | — | Output-only Device 1, buffer property on Device 2 |
| App modifications | — | Property read with inputNode fallback |
