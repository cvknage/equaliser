# Phase 1: Critical Safety Fixes - Detailed Implementation Plan

**Priority:** P0 (Critical)  
**Estimated Effort:** 1-2 days  
**Risk Level:** Medium (audio pipeline changes)

---

## Goal

Address theoretical race conditions and replace deprecated atomic APIs to ensure thread safety in the real-time audio path.

---

## Problems Identified

### Problem 1.1: Gain Race Condition

**Location:** `src/services/audio/rendering/RenderCallbackContext.swift:58-75`

```swift
nonisolated(unsafe) var inputGainLinear: Float = 1.0
nonisolated(unsafe) var targetInputGainLinear: Float = 1.0
nonisolated(unsafe) var outputGainLinear: Float = 1.0
nonisolated(unsafe) var targetOutputGainLinear: Float = 1.0
nonisolated(unsafe) var boostGainLinear: Float = 1.0
nonisolated(unsafe) var targetBoostGainLinear: Float = 1.0
```

**Analysis:**
- Main thread writes to `target*GainLinear` properties via `updateInputGain()`, `updateOutputGain()`, `updateBoostGain()`
- Audio thread reads `target*GainLinear` and writes to `*GainLinear` during `applyGain()`
- Current pattern: single-writer/single-reader with comments stating safety
- Actual risk: benign (floats are atomic on x86/ARM) but violates Swift concurrency model

**Issue:** While floats are typically atomic on modern architectures, Swift's `nonisolated(unsafe)` provides no formal guarantees. The `applyGain()` function reads `targetGain` while ramping, and the main thread may write to it concurrently.

---

### Problem 1.2: Deprecated Atomic APIs

**Location:** `src/services/audio/dsp/AudioRingBuffer.swift:103-104, 136, 155-156, 195, 207-209, 217-219`

```swift
let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
```

**Analysis:**
- `OSAtomicAdd64Barrier` is deprecated since macOS 10.12
- Still compiles but generates warnings
- Should use modern Swift Atomics package for explicit memory ordering

---

### Problem 1.3: Potential Buffer Overrun

**Location:** `src/services/audio/rendering/RenderCallbackContext.swift:374`

```swift
while frame < frameCount {
    let sample = abs(buffer[frame])  // frame could exceed framesPerBuffer
    // ...
}
```

**Analysis:**
- `frameCount` comes from CoreAudio callbacks
- Should always equal or be less than `framesPerBuffer` but no explicit check
- Precondition would catch any edge cases during development/testing

---

## Architectural Approach

### Atomic Operations Strategy

We will use the **Swift Atomics** package from Apple:

```swift
import Atomics

// ManagedAtomic provides thread-safe atomic access
let targetInputGainLinear: ManagedAtomic<Float> = ManagedAtomic(1.0)
```

**Why Swift Atomics:**
1. Official Apple package with first-class Swift 6 support
2. Clear memory ordering semantics (`.relaxed`, `.acquiring`, `.releasing`, `.sequentiallyConsistent`)
3. Works on all Apple platforms
4. Better performance than locks for single-writer/single-reader patterns
5. No allocation in the atomic path (ManagedAtomic is a struct wrapper around atomic operations)

**Memory Ordering:**
- For the gain values, we use `.relaxed` ordering because:
  - We only need atomicity, not ordering guarantees
  - The audio thread tolerates slight staleness in gain values
  - Performance is critical on the audio thread

### Thread Safety Model After Changes

```
┌─────────────────────────────────────────────────────────────────┐
│                      Main Thread (@MainActor)                    │
│                                                                  │
│  updateInputGain(linear:)                                        │
│  └─► targetInputGainLinear.store(value, ordering: .relaxed)     │
│                                                                  │
│  updateBoostGain(linear:)                                        │
│  └─► targetBoostGainLinear.store(value, ordering: .relaxed)     │
│                                                                  │
│  updateOutputGain(linear:)                                       │
│  └─► targetOutputGainLinear.store(value, ordering: .relaxed)    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Relaxed atomic store
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Audio Thread (Real-Time)                    │
│                                                                  │
│  applyGain(currentGain: &inputGainLinear, target: ...)          │
│  └─► let targetGain = targetInputGainLinear.load(ordering: .relaxed)
│      while frame < frameCount:                                   │
│          // Use local copy of target, ramp currentGain           │
│      // Only audio thread writes to inputGainLinear              │
└─────────────────────────────────────────────────────────────────┘
```

**Key invariant:** Only the audio thread writes to `inputGainLinear`, `outputGainLinear`, `boostGainLinear`. The main thread only writes to `target*Linear` atomics.

---

## Files to Modify

| File | Changes |
|------|---------|
| `Package.swift` | Add Swift Atomics dependency |
| `src/services/audio/rendering/RenderCallbackContext.swift` | Convert target gains to atomic |
| `src/services/audio/dsp/AudioRingBuffer.swift` | Replace OSAtomic with ManagedAtomic |

---

## Step-by-Step Implementation

### Step 1: Add Swift Atomics Dependency

**File:** `Package.swift`

**Changes:**
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Equaliser",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Add Swift Atomics for thread-safe atomic operations
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Equaliser",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "src",
            exclude: ["app/Info.plist"]
        ),
        .testTarget(
            name: "EqualiserTests",
            dependencies: ["Equaliser"],
            path: "tests"
        )
    ]
)
```

**Verification:**
```bash
swift package resolve
swift build
```

---

### Step 2: Update RenderCallbackContext for Atomic Gains

**File:** `src/services/audio/rendering/RenderCallbackContext.swift`

#### 2.1 Add Import

Add at the top of the file:
```swift
import Atomics
```

#### 2.2 Replace Property Declarations

**Before (lines 57-75):**
```swift
/// Current linear gain applied to input samples before they enter the ring buffer.
nonisolated(unsafe) var inputGainLinear: Float = 1.0

/// Target linear gain applied to input samples before they enter the ring buffer.
nonisolated(unsafe) var targetInputGainLinear: Float = 1.0

/// Current linear gain applied to output samples after EQ rendering.
nonisolated(unsafe) var outputGainLinear: Float = 1.0

/// Target linear gain applied to output samples after EQ rendering.
nonisolated(unsafe) var targetOutputGainLinear: Float = 1.0

/// Current boost gain applied to input samples before input gain.
nonisolated(unsafe) var boostGainLinear: Float = 1.0

/// Target boost gain applied to input samples before input gain.
nonisolated(unsafe) var targetBoostGainLinear: Float = 1.0
```

**After:**
```swift
// MARK: - Atomic Target Gains
// Target gains are written by the main thread and read by the audio thread.
// We use ManagedAtomic for thread-safe access with relaxed memory ordering,
// which is sufficient for single-writer/single-reader scenarios where
// slight staleness is acceptable.

/// Target linear gain for input (written by main thread, read by audio thread).
private let targetInputGainAtomic: ManagedAtomic<Float> = ManagedAtomic(1.0)

/// Target linear gain for output (written by main thread, read by audio thread).
private let targetOutputGainAtomic: ManagedAtomic<Float> = ManagedAtomic(1.0)

/// Target boost gain (written by main thread, read by audio thread).
private let targetBoostGainAtomic: ManagedAtomic<Float> = ManagedAtomic(1.0)

// MARK: - Current Gains (Audio Thread Only)
// Current gains are ONLY written by the audio thread during gain ramping.
// They can be read atomically for diagnostics, but should not be written
// from any other thread.

/// Current linear gain for input (audio thread only).
nonisolated(unsafe) var inputGainLinear: Float = 1.0

/// Current linear gain for output (audio thread only).
nonisolated(unsafe) var outputGainLinear: Float = 1.0

/// Current boost gain (audio thread only).
nonisolated(unsafe) var boostGainLinear: Float = 1.0
```

#### 2.3 Add Public Setters for Main Thread

Add new methods after the property declarations:

```swift
// MARK: - Gain Update API (Main Thread)

/// Updates the target input gain (called from main thread).
/// - Parameter linear: Linear gain value (will be clamped to >= 0).
func setTargetInputGain(_ linear: Float) {
    targetInputGainAtomic.store(max(0, linear), ordering: .relaxed)
}

/// Updates the target output gain (called from main thread).
/// - Parameter linear: Linear gain value (will be clamped to >= 0).
func setTargetOutputGain(_ linear: Float) {
    targetOutputGainAtomic.store(max(0, linear), ordering: .relaxed)
}

/// Updates the target boost gain (called from main thread).
/// - Parameter linear: Linear gain value (will be clamped to >= 1).
func setTargetBoostGain(_ linear: Float) {
    targetBoostGainAtomic.store(max(1, linear), ordering: .relaxed)
}

// MARK: - Gain Read API (Audio Thread or Diagnostics)

/// Returns the current target input gain.
func getTargetInputGain() -> Float {
    targetInputGainAtomic.load(ordering: .relaxed)
}

/// Returns the current target output gain.
func getTargetOutputGain() -> Float {
    targetOutputGainAtomic.load(ordering: .relaxed)
}

/// Returns the current target boost gain.
func getTargetBoostGain() -> Float {
    targetBoostGainAtomic.load(ordering: .relaxed)
}
```

#### 2.4 Update applyGain Method

The `applyGain` method needs to use the atomic target values. Locate the method at line ~244:

**Before:**
```swift
@inline(__always)
func applyGain(
    to buffers: [UnsafeMutablePointer<Float>],
    frameCount: UInt32,
    currentGain: inout Float,
    targetGain: Float
) {
    let count = Int(frameCount)
    guard count > 0 else {
        currentGain = targetGain
        return
    }

    let gainDelta = targetGain - currentGain
    let gainStep = gainDelta / Float(count)
    var gain = currentGain
    var index = 0

    while index < count {
        for buffer in buffers {
            buffer[index] *= gain
        }
        gain += gainStep
        index += 1
    }

    currentGain = targetGain
}
```

**No changes needed to `applyGain` signature** - it still takes `targetGain: Float` as a parameter. The atomic load happens before calling this method.

#### 2.5 Update Input Callback

Locate the input callback in `RenderPipeline.swift` (around line 518):

**Before:**
```swift
// Apply boost gain before input gain (for volume > 100%)
context.applyGain(
    to: context.inputSampleBuffers,
    frameCount: frameCount,
    currentGain: &context.boostGainLinear,
    targetGain: context.targetBoostGainLinear
)

// Apply input gain before writing to ring buffers (skip in full bypass mode)
if context.processingMode != 0 {
    context.applyGain(
        to: context.inputSampleBuffers,
        frameCount: frameCount,
        currentGain: &context.inputGainLinear,
        targetGain: context.targetInputGainLinear
    )
}
```

**After:**
```swift
// Apply boost gain before input gain (for volume > 100%)
// Load target gain atomically (relaxed ordering is sufficient for audio)
let targetBoostGain = context.getTargetBoostGain()
context.applyGain(
    to: context.inputSampleBuffers,
    frameCount: frameCount,
    currentGain: &context.boostGainLinear,
    targetGain: targetBoostGain
)

// Apply input gain before writing to ring buffers (skip in full bypass mode)
if context.processingMode != 0 {
    // Load target gain atomically (relaxed ordering is sufficient for audio)
    let targetInputGain = context.getTargetInputGain()
    context.applyGain(
        to: context.inputSampleBuffers,
        frameCount: frameCount,
        currentGain: &context.inputGainLinear,
        targetGain: targetInputGain
    )
}
```

#### 2.6 Update Output Callback

Locate the output callback in `RenderPipeline.swift` (around line 603):

**Before:**
```swift
// 5. Apply output gain after EQ rendering (skip in full bypass mode)
if context.processingMode != 0 {
    context.applyGain(
        to: ioData,
        frameCount: frameCount,
        currentGain: &context.outputGainLinear,
        targetGain: context.targetOutputGainLinear
    )
}
```

**After:**
```swift
// 5. Apply output gain after EQ rendering (skip in full bypass mode)
if context.processingMode != 0 {
    // Load target gain atomically (relaxed ordering is sufficient for audio)
    let targetOutputGain = context.getTargetOutputGain()
    context.applyGain(
        to: ioData,
        frameCount: frameCount,
        currentGain: &context.outputGainLinear,
        targetGain: targetOutputGain
    )
}
```

#### 2.7 Update RenderPipeline Gain Update Methods

Locate the gain update methods in `RenderPipeline.swift` (lines 389-405):

**Before:**
```swift
func updateInputGain(linear: Float) {
    callbackContext?.targetInputGainLinear = max(0, linear)
}

func updateOutputGain(linear: Float) {
    callbackContext?.targetOutputGainLinear = max(0, linear)
}

func updateBoostGain(linear: Float) {
    let context = callbackContext
    logger.debug("updateBoostGain: linear=\(linear), callbackContext=\(context != nil ? "exists" : "nil")")
    context?.targetBoostGainLinear = max(1, linear)
}
```

**After:**
```swift
func updateInputGain(linear: Float) {
    callbackContext?.setTargetInputGain(linear)
}

func updateOutputGain(linear: Float) {
    callbackContext?.setTargetOutputGain(linear)
}

func updateBoostGain(linear: Float) {
    let context = callbackContext
    logger.debug("updateBoostGain: linear=\(linear), callbackContext=\(context != nil ? "exists" : "nil")")
    context?.setTargetBoostGain(linear)
}
```

#### 2.8 Update Initialization in RenderPipeline.start()

Locate the initial gain setting in `RenderPipeline.start()` (around line 238-244):

**Before:**
```swift
// Apply initial gains from EQConfiguration
let inputGainLinear = AudioMath.dbToLinear(eqConfiguration.inputGain)
let outputGainLinear = AudioMath.dbToLinear(eqConfiguration.outputGain)
context.targetInputGainLinear = inputGainLinear
context.targetOutputGainLinear = outputGainLinear
context.inputGainLinear = inputGainLinear
context.outputGainLinear = outputGainLinear
```

**After:**
```swift
// Apply initial gains from EQConfiguration
let inputGainLinear = AudioMath.dbToLinear(eqConfiguration.inputGain)
let outputGainLinear = AudioMath.dbToLinear(eqConfiguration.outputGain)
context.setTargetInputGain(inputGainLinear)
context.setTargetOutputGain(outputGainLinear)
// Initialize current gains (audio thread uses these as starting point)
context.inputGainLinear = inputGainLinear
context.outputGainLinear = outputGainLinear
```

---

### Step 3: Replace Deprecated Atomics in AudioRingBuffer

**File:** `src/services/audio/dsp/AudioRingBuffer.swift`

#### 3.1 Add Import

Add at the top of the file:
```swift
import Atomics
```

#### 3.2 Replace Index Storage

**Before (lines 29-33):**
```swift
/// Write position (only modified by producer).
/// Using UnsafeMutablePointer for atomic access.
private let writeIndex: UnsafeMutablePointer<Int>

/// Read position (only modified by consumer).
/// Using UnsafeMutablePointer for atomic access.
private let readIndex: UnsafeMutablePointer<Int>
```

**After:**
```swift
/// Write position (only modified by producer).
/// Uses ManagedAtomic for thread-safe access.
private let writeIndex: ManagedAtomic<Int> = ManagedAtomic(0)

/// Read position (only modified by consumer).
/// Uses ManagedAtomic for thread-safe access.
private let readIndex: ManagedAtomic<Int> = ManagedAtomic(0)
```

#### 3.3 Remove Index Allocation from init()

**Before (lines 66-72):**
```swift
// Allocate atomic indices
self.writeIndex = UnsafeMutablePointer<Int>.allocate(capacity: 1)
self.writeIndex.initialize(to: 0)

self.readIndex = UnsafeMutablePointer<Int>.allocate(capacity: 1)
self.readIndex.initialize(to: 0)
```

**After:**
```swift
// Indices are initialized to 0 via ManagedAtomic(0) above
// No additional allocation needed
```

#### 3.4 Remove Index Deallocation from deinit()

**Before (lines 82-86):**
```swift
writeIndex.deinitialize(count: 1)
writeIndex.deallocate()

readIndex.deinitialize(count: 1)
readIndex.deallocate()
```

**After:**
```swift
// ManagedAtomic handles its own memory - no manual deallocation needed
```

#### 3.5 Update write() Method

**Before (lines 100-139):**
```swift
@inline(__always)
func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
    // Load indices with memory barrier
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

    let write = Int(currentWrite)
    let read = Int(currentRead)
    // ... rest of method

    // Update write index with memory barrier (release semantics)
    OSAtomicAdd64Barrier(Int64(toWrite), writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

    return toWrite
}
```

**After:**
```swift
@inline(__always)
func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
    // Load indices atomically with acquire semantics
    let currentWrite = writeIndex.load(ordering: .acquiring)
    let currentRead = readIndex.load(ordering: .acquiring)

    let write = currentWrite
    let read = currentRead
    // ... rest of method (same logic)

    // Update write index atomically with release semantics
    writeIndex.store(write + toWrite, ordering: .releasing)

    return toWrite
}
```

#### 3.6 Update read() Method

**Before (lines 152-198):**
```swift
@inline(__always)
func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
    // Load indices with memory barrier
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

    let write = Int(currentWrite)
    let read = Int(currentRead)
    // ... rest of method

    // Update read index with memory barrier (release semantics)
    OSAtomicAdd64Barrier(Int64(toRead), readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

    return toRead
}
```

**After:**
```swift
@inline(__always)
func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
    // Load indices atomically with acquire semantics
    let currentWrite = writeIndex.load(ordering: .acquiring)
    let currentRead = readIndex.load(ordering: .acquiring)

    let write = currentWrite
    let read = currentRead
    // ... rest of method (same logic)

    // Update read index atomically with release semantics
    readIndex.store(read + toRead, ordering: .releasing)

    return toRead
}
```

#### 3.7 Update availableToRead() Method

**Before (lines 205-210):**
```swift
@inline(__always)
func availableToRead() -> Int {
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    return Int(currentWrite - currentRead)
}
```

**After:**
```swift
@inline(__always)
func availableToRead() -> Int {
    let currentWrite = writeIndex.load(ordering: .relaxed)
    let currentRead = readIndex.load(ordering: .relaxed)
    return currentWrite - currentRead
}
```

#### 3.8 Update availableToWrite() Method

**Before (lines 215-220):**
```swift
@inline(__always)
func availableToWrite() -> Int {
    let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
    return capacity - Int(currentWrite - currentRead)
}
```

**After:**
```swift
@inline(__always)
func availableToWrite() -> Int {
    let currentWrite = writeIndex.load(ordering: .relaxed)
    let currentRead = readIndex.load(ordering: .relaxed)
    return capacity - (currentWrite - currentRead)
}
```

#### 3.9 Update reset() Method

**Before (lines 224-231):**
```swift
func reset() {
    writeIndex.pointee = 0
    readIndex.pointee = 0
    buffer.initialize(repeating: 0.0, count: capacity)
    underrunCount = 0
    overflowCount = 0
}
```

**After:**
```swift
func reset() {
    writeIndex.store(0, ordering: .releasing)
    readIndex.store(0, ordering: .releasing)
    buffer.initialize(repeating: 0.0, count: capacity)
    underrunCount = 0
    overflowCount = 0
}
```

---

### Step 4: Add Buffer Bounds Assertion

**File:** `src/services/audio/rendering/RenderCallbackContext.swift`

#### 4.1 Add Precondition to updateMeterStorage()

Locate the `updateMeterStorage` method (around line 348). Add precondition at the start:

**Before:**
```swift
private func updateMeterStorage(
    storage: UnsafeMutablePointer<Float>,
    rmsStorage: UnsafeMutablePointer<Float>,
    with channels: [UnsafePointer<Float>],
    frameCount: Int
) {
    guard frameCount > 0 else {
        // ... rest
    }
    // ...
}
```

**After:**
```swift
private func updateMeterStorage(
    storage: UnsafeMutablePointer<Float>,
    rmsStorage: UnsafeMutablePointer<Float>,
    with channels: [UnsafePointer<Float>],
    frameCount: Int
) {
    // Assert that frameCount doesn't exceed pre-allocated buffer capacity
    // This should never happen in practice as CoreAudio guarantees frameCount <= maxFrameCount
    // but the precondition catches any edge cases during development
    precondition(
        frameCount <= framesPerBuffer,
        "frameCount (\(frameCount)) exceeds framesPerBuffer (\(framesPerBuffer))"
    )
    
    guard frameCount > 0 else {
        for index in 0..<meterChannelCount {
            storage[index] = Self.silenceDB
            rmsStorage[index] = Self.silenceDB
        }
        return
    }
    // ... rest of method unchanged
}
```

---

## Test Plan

### Unit Tests for AudioRingBuffer

No new tests needed for the API changes (same behavior). Existing tests should pass:

```bash
swift test --filter AudioRingBufferTests
```

### Integration Tests for Gain Updates

Create a new test file: `tests/services/audio/RenderCallbackContextAtomicTests.swift`

```swift
import XCTest
import Atomics
@testable import Equaliser

final class RenderCallbackContextAtomicTests: XCTestCase {
    
    /// Verify that gain values are stored and retrieved atomically
    func testAtomicGainStorage() {
        // Create a minimal context (without HAL units)
        let context = RenderCallbackContext(
            inputHALUnit: nil,
            renderContext: nil,
            channelCount: 2,
            maxFrameCount: 512
        )
        
        // Set target gains
        context.setTargetInputGain(0.5)
        context.setTargetOutputGain(0.75)
        context.setTargetBoostGain(1.5)
        
        // Verify they can be read back
        XCTAssertEqual(context.getTargetInputGain(), 0.5, accuracy: 0.001)
        XCTAssertEqual(context.getTargetOutputGain(), 0.75, accuracy: 0.001)
        XCTAssertEqual(context.getTargetBoostGain(), 1.5, accuracy: 0.001)
    }
    
    /// Verify that negative gains are clamped
    func testInputGainClamping() {
        let context = RenderCallbackContext(
            inputHALUnit: nil,
            renderContext: nil,
            channelCount: 2,
            maxFrameCount: 512
        )
        
        context.setTargetInputGain(-0.5)
        XCTAssertEqual(context.getTargetInputGain(), 0.0, accuracy: 0.001)
    }
    
    /// Verify that boost gain < 1 is clamped to 1
    func testBoostGainClamping() {
        let context = RenderCallbackContext(
            inputHALUnit: nil,
            renderContext: nil,
            channelCount: 2,
            maxFrameCount: 512
        )
        
        context.setTargetBoostGain(0.5)
        XCTAssertEqual(context.getTargetBoostGain(), 1.0, accuracy: 0.001)
        
        context.setTargetBoostGain(2.0)
        XCTAssertEqual(context.getTargetBoostGain(), 2.0, accuracy: 0.001)
    }
}
```

### Manual Testing

1. **Build and run the application:**
   ```bash
   swift build -c release
   open .build/release/Equaliser.app
   ```

2. **Test gain changes while playing audio:**
   - Start audio routing
   - Move input gain slider rapidly
   - Move output gain slider rapidly
   - Move boost gain (volume > 100%)
   - Verify no audio artifacts or clicks

3. **Test stress scenario:**
   - Run audio continuously
   - Use CPU profiler to verify no increased overhead from atomic operations

4. **Verify latency:**
   - Measure round-trip latency before and after changes
   - Atomic operations should not add measurable latency

---

## Rollback Strategy

If issues arise:

1. **Git revert:**
   ```bash
   git revert <commit-hash>
   ```

2. **Restore original Package.swift:**
   - Remove Swift Atomics dependency

3. **Restore original source files:**
   - `RenderCallbackContext.swift` - Restore `nonisolated(unsafe)` properties
   - `AudioRingBuffer.swift` - Restore `OSAtomicAdd64Barrier` calls

---

## Success Criteria

- [ ] All existing tests pass (`swift test`)
- [ ] Build succeeds in release mode (`swift build -c release`)
- [ ] No compiler warnings
- [ ] No audio artifacts during gain changes
- [ ] Atomic gain operations work correctly (unit tests pass)
- [ ] Ring buffer operations work correctly (existing tests pass)

---

## Notes

### Memory Ordering Explanation

| Operation | Ordering | Rationale |
|-----------|----------|-----------|
| `write()` load indices | `.acquiring` | Ensure we see latest data from other thread |
| `write()` store index | `.releasing` | Make new data visible to reader |
| `read()` load indices | `.acquiring` | See latest write position |
| `read()` store index | `.releasing` | Make read position visible to writer |
| `available()` | `.relaxed` | Just checking, no data dependency |
| Gain load/store | `.relaxed` | Audio tolerates slight staleness |

### Performance Considerations

- `ManagedAtomic` uses inline storage (no allocation)
- Relaxed ordering has minimal overhead on x86/ARM
- Acquire/release has cache coherency cost but necessary for ring buffer correctness
- No mutexes or locks in the audio path

---

*This plan should be followed step-by-step. Each step should be verified with builds and tests before proceeding to the next.*