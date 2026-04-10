# Real-Time Audio Safety

Rules and patterns for code that runs on the audio render thread.

## The Golden Rules

Code running on the audio render thread (inside `RenderCallbackContext.processEQ()` or any function called from the audio unit render callback) MUST:

1. **Never allocate memory** — no `malloc`, no Swift class instantiation, no Array/String operations that copy
2. **Never acquire locks** — no `os_unfair_lock`, no `DispatchSemaphore`, no `NSLock`
3. **Never block** — no file I/O, no network calls, no `Task.sleep`, no `DispatchQueue.sync`
4. **Never call Objective-C runtime** — no message sends, no `objc_msgSend`
5. **Never call non-real-time-safe APIs** — no `print()`, no logging frameworks, no CoreAnimation

## Lock-Free Patterns

### ManagedAtomic Flag for Coefficient Updates

The primary pattern for communicating from main thread to audio thread:

```swift
// Main thread: stage update
pendingCoefficients[index] = newCoefficients
hasPendingUpdate.store(true, .releasing)

// Audio thread: consume update
if hasPendingUpdate.exchange(false, .acquiringAndReleasing) {
    // Copy from pendingCoefficients to activeCoefficients
}
```

- Uses `swift-atomics` package (`ManagedAtomic<Bool>`)
- `.releasing` on write ensures main thread writes are visible to audio thread
- `.acquiringAndReleasing` on read ensures audio thread sees latest values
- No locks, no allocation, safe for real-time

### AudioRingBuffer for Cross-Thread Communication

Used in HAL input mode where producer (input callback) and consumer (output callback) run on different threads:

```
[Input Callback] ──▶ [AudioRingBuffer] ──▶ [Output Callback]
      (producer)        (lock-free)          (consumer)
```

- Single-producer single-consumer (SPSC) design
- No locks — uses atomic read/write pointers
- Absorbs clock drift between input and output devices

### SharedMemoryCapture for Driver Communication

In shared memory mode, no ring buffer is needed because both poll and render run on the same output thread:

```swift
// Called synchronously from output audio thread — real-time safe
SharedMemoryCapture.readFramesIntoBuffers()  // Uses atomic reads, no locks
DriverCapture.pollIntoBuffers()               // @inline(__always) for performance
```

- Overflow detection resets read position to prevent corrupted audio
- `@inline(__always)` attribute ensures no function call overhead

## Custom DSP Implementation

### Architecture: Main Thread → Audio Thread

```
[Main Thread]                              [Audio Thread]
     │                                           │
     ▼                                           │
BiquadMath.calculateCoefficients()               │
     │                                           │
     ▼                                           │
EQChain.stageBandUpdate()                        │
     │                                           │
     │    ┌──────────────────────────────────────┤
     │    │         ManagedAtomic<Bool>          │
     │    │      (hasPendingUpdate flag)         │
     │    └──────────────────────────────────────┤
     │                     │                     │
     ▼                     │ release             │ acquire
pendingCoefficients[i]     ▼                     ▼
                     ┌─────────────────────────────────────┐
                     │         EQChain.applyPendingUpdates │
                     │    (called once per render cycle)   │
                     └─────────────────────────────────────┘
                                        │
                                        ▼
                            Only rebuild changed bands
                            (dirty tracked via Equatable)
```

### Key Files

| File | Purpose |
|------|---------|
| `BiquadMath.swift` | Pure coefficient calculation (RBJ Cookbook), Double precision |
| `BiquadCoefficients.swift` | Value type for b0/b1/b2/a1/a2, `Equatable`, `Sendable` |
| `BiquadFilter.swift` | vDSP biquad wrapper, owns delay elements and setup |
| `EQChain.swift` | Per-channel-per-layer chain of 64 biquads, lock-free coefficient updates |
| `EQChannelTarget.swift` | `.left` / `.right` / `.both` for stereo routing |
| `FilterType.swift` | Filter types (parametric, shelves, band-pass, notch) with legacy migration |

### Real-Time Safety Guarantees

1. **Dirty-tracking**: `EQChain.applyPendingUpdates()` only rebuilds filters whose coefficients actually changed (using `Equatable` comparison). A single-band slider drag rebuilds **1 filter** instead of 64.

2. **No allocation on audio thread**: All biquad setups and delay elements are pre-allocated at init. vDSP setup objects are only destroyed and recreated when coefficients change.

3. **Lock-free updates**: Main thread writes to `pendingCoefficients`, sets `hasPendingUpdate.store(true, .releasing)`. Audio thread calls `hasPendingUpdate.exchange(false, .acquiringAndReleasing)` and copies to `activeCoefficients`.

4. **State preservation for slider drags**: `BiquadFilter.setCoefficients(_, resetState: false)` preserves delay elements during incremental coefficient changes (slider drags), avoiding audible clicks. `resetState: true` is only used for preset loads and sample rate changes.

### Coefficient Calculation (Main Thread Only)

```swift
// Main thread (not real-time)
let coeffs = BiquadMath.calculateCoefficients(
    type: .parametric,      // FilterType enum
    sampleRate: 48000.0,
    frequency: 1000.0,
    q: 1.41,                // ~1 octave bandwidth
    gain: 6.0               // dB
)

// Staged to audio thread
chain.stageBandUpdate(index: 0, coefficients: coeffs, bypass: false)
```

### Forbidden Operations on Audio Thread

- Call `BiquadMath.calculateCoefficients()` — it allocates
- Call `vDSP_biquad_CreateSetup` or `vDSP_biquad_DestroySetup` directly — use `BiquadFilter.setCoefficients()`
- Allocate memory or acquire locks in `RenderCallbackContext.processEQ()`
- Call `print()`, use logging frameworks, or perform any I/O

## Boost Gain Always Applied

Boost gain (for driver volume compensation) must **always** be applied, even in bypass mode. Input/output gains are skipped in bypass:

```swift
// Boost is ALWAYS applied (not inside bypass check)
context.applyGain(to: context.inputSampleBuffers, ...)

// Input gain is skipped in bypass mode
if context.processingMode != 0 {
    context.applyGain(to: context.inputSampleBuffers, ...)
}
```

## Fire-and-Forget Scheduled Work

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

## nonisolated(unsafe) for Audio Thread Access

Properties accessed from the audio render thread use `nonisolated(unsafe)` to bypass Swift 6 concurrency checking:

```swift
nonisolated(unsafe) var callbackContext: RenderCallbackContext?
nonisolated(unsafe) var isRunning: Bool = false
```

This is safe when:
- The property is set once during initialization and never mutated from two threads simultaneously
- All writes happen-before reads (ensured by the audio pipeline start sequence)
- The property is only read from the audio thread after the pipeline is started

## vDSP Best Practices

- Pre-allocate `vDSP_biquad_Setup` objects at init time
- Only destroy and recreate setups when coefficients change (dirty-tracking)
- Use `BiquadFilter.setCoefficients()` as the safe wrapper — never call vDSP setup/teardown directly
- Preserve filter state (`resetState: false`) during slider drags to avoid clicks
- Reset state (`resetState: true`) only on preset loads and sample rate changes