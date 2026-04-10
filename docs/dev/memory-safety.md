# Swift Memory Safety

ARC, retain cycles, and lifetime management patterns for this project.

## ARC Fundamentals

Swift uses Automatic Reference Counting (ARC). Key rules:

- **Strong references** (default): Increment reference count, keep object alive
- **Weak references** (`weak`): Don't increment count, become `nil` when deallocated
- **Unowned references** (`unowned`): Don't increment count, crash if accessed after deallocation
- Value types (`struct`, `enum`) are not reference-counted — they're copied

## Common Retain Cycle Patterns

### Closures Capturing `self`

The most common source of retain cycles in this codebase:

```swift
// WRONG: Strong reference cycle — closure captures self strongly
volumeForwardQueue.async {
    self.forwardVolumeToOutput(newVolume, outputID: outputID)
}

// CORRECT: Break the cycle with [weak self]
volumeForwardQueue.async { [weak self] in
    self?.forwardVolumeToOutput(newVolume, outputID: outputID)
}
```

Rules:
- Always use `[weak self]` in GCD closures
- Always use `[weak self]` in delegate callbacks
- Use `[unowned self]` only when the closure's lifetime is strictly bounded by `self`'s lifetime (rare)

### Delegates

Delegate properties must be `weak` to prevent parent-child cycles:

```swift
// Protocol conformance
protocol SomeDelegateing: AnyObject {
    func didReceiveUpdate(_ value: Float)
}

// Weak delegate reference
weak var delegate: SomeDelegateing?
```

Rules:
- Delegate protocols should conform to `AnyObject` (enables `weak`)
- Always declare delegate properties as `weak`
- This codebase uses protocols with `-ing` suffix for service protocols (`Enumerating`, `VolumeControlling`, `SampleRateObserving`)

### Coordinator Pattern

Coordinators in this project are `@MainActor` and manage lifecycle of their dependencies:

```swift
@MainActor final class AudioRoutingCoordinator {
    private let deviceProvider: DeviceProviding    // Protocol reference — owned
    private var volumeManager: VolumeControlling?   // Created lazily, owned
}
```

No retain cycle here because:
- Coordinator owns its dependencies (strong references)
- Dependencies don't hold references back to the coordinator
- If bidirectional references exist, one must be `weak`

## View Model Lifetime

View models use `unowned` store references:

```swift
@Observable final class RoutingViewModel {
    private unowned let store: EqualiserStore
}
```

This is safe because:
- View models are created by views on the main actor
- Store outlives all view models
- View models don't retain the store

**When to use `unowned` vs `weak`:**
- Use `unowned` when: The owner always outlives the reference, and you want zero-overhead access
- Use `weak` when: The referenced object might be deallocated independently, and you need to handle `nil`

## GCD and Lifetime

### Dispatching to Main Queue

```swift
DispatchQueue.main.async { [weak self] in
    self?.updateUI()
}
```

- Always use `[weak self]` when dispatching from a background context
- The object might be deallocated between dispatch and execution

### Dispatching to Serial Queue

```swift
private let volumeForwardQueue = DispatchQueue(label: "com.equaliser.volume")

volumeForwardQueue.async { [weak self] in
    self?.forwardVolumeToOutput(newVolume, outputID: outputID)
}
```

- Serial queues ensure ordering but don't prevent retain cycles
- Use `[weak self]` for any closure that might outlive the current scope

## Swift/ObjC Interop

This project uses CoreAudio (C API) and AVFoundation (ObjC framework):

### AudioObject Property Callbacks

```swift
var propertyAddress = AudioObjectPropertyAddress(...)
AudioObjectAddPropertyDataBlock(deviceID, &propertyAddress, 0, nil) { [weak self] _, _ in
    DispatchQueue.main.async {
        self?.handleDeviceChange()
    }
}
```

Rules:
- CoreAudio callbacks run on arbitrary threads — never assume main thread
- Always dispatch to main queue for UI updates
- Use `[weak self]` in all CoreAudio callbacks
- AudioObject property listeners are `nonisolated` — they don't belong to any actor

### Bridging Types

- `AudioDeviceID` is a `UInt32` typedef — passed by value, no lifetime issues
- `AudioObjectID` is a `UInt32` typedef — same
- `CFString` bridging: Use `as String` for conversions, ensure lifetime with explicit `Unmanaged<CFString>` when needed

## Audio Thread Memory Rules

The audio render thread has additional constraints:

- **No allocation**: ARC can trigger allocation — avoid any operation that might allocate
- **No reference counting transitions**: Avoid passing objects across the audio thread boundary that would trigger retain/release
- **Use `nonisolated(unsafe)`**: For properties accessed from audio thread, bypass Swift 6 checking but document the safety proof
- **Pre-allocate everything**: All buffers, setups, and state must be allocated at init time, never during render callbacks

```swift
// SAFE: Pre-allocated at init, only read during render
nonisolated(unsafe) var callbackContext: RenderCallbackContext?

// UNSAFE: Could allocate during render
var processedSamples: [Float] = []  // Array might reallocate!
```

## Testing and Memory

- Use `@testable import Equaliser` for access to internal types
- Test `deinit` is called by using `addTeardownBlock` or weak reference checks
- Leaks in tests usually indicate missing `[weak self]` in closures