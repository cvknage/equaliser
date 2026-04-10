# Swift 6 Concurrency

Strict concurrency patterns and migration strategies for this project.

## Swift 6 Strict Concurrency Mode

This project compiles with Swift 6 strict concurrency enabled. All concurrency warnings are errors. Key implications:

- All `Sendable` conformance is checked — types crossing actor boundaries must be `Sendable`
- `@MainActor` isolation is enforced — UI-bound code must be explicitly marked
- `nonisolated` functions need explicit annotation when called across boundaries
- No implicit actor hopping — all cross-actor calls are async or explicitly unsafe

## @MainActor

UI-bound classes and coordinators are `@MainActor`:

```swift
@MainActor final class EqualiserStore: ObservableObject { ... }
@MainActor final class AudioRoutingCoordinator { ... }
@MainActor final class AudioRoutingCoordinator { ... }
@MainActor @Observable final class RoutingViewModel { ... }
```

Rules:
- All `@Observable` / `ObservableObject` types should be `@MainActor`
- `@Published` property changes must happen on the main actor
- SwiftUI views that bind to state assume main actor

## Actor Isolation

`MeterStore` uses `@MainActor` isolation for thread-safe meter state updates at 30 FPS:

```swift
@MainActor final class MeterStore: ObservableObject {
    // All access serialized on main actor
    // Meter observers receive callbacks on main thread
}
```

Rules:
- `MeterStore` is `@MainActor` — all mutations happen on main thread
- Meter observers (`PeakMeterLayer`, `RMSMeterLayer`) receive updates via `MeterObserver` protocol
- Audio thread writes to meter data via `nonisolated(unsafe)` properties, main thread reads for display

## nonisolated(unsafe)

Audio thread access uses `nonisolated(unsafe)` to bypass Swift 6 checking:

```swift
nonisolated(unsafe) var callbackContext: RenderCallbackContext?
nonisolated(unsafe) var isRunning: Bool = false
```

This is correct when:
- The property is set once during initialization
- All writes happen-before reads (guaranteed by pipeline start sequence)
- The property is only read from the audio thread after startup

**Do NOT use `nonisolated(unsafe)` as a shortcut** — only use it when you can prove the access pattern is safe (single-writer, happen-before relationship).

## Sendable Conformance

All types crossing actor boundaries must be `Sendable`:

```swift
struct BiquadCoefficients: Equatable, Sendable {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double
}
```

Rules:
- Value types (`struct`, `enum`) can be `Sendable` if all stored properties are `Sendable`
- Reference types need explicit conformance — only mark as `Sendable` if genuinely thread-safe
- Closures crossing actors must be `@Sendable`
- `@Published` properties in `@MainActor` types are fine — they're main-thread-only

## Async/Await vs GCD

This project uses both patterns intentionally:

### GCD (for fire-and-forget and timed work)
```swift
// Fire-and-forget work on main thread
DispatchQueue.main.async { ... }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ... }

// Serial queue for CoreAudio calls
volumeForwardQueue.async { [weak self] in ... }
```

### Async/Await (for user-initiated async operations)
```swift
// Permission request (user-initiated, needs result)
func requestMicPermissionAndSwitchToHALCapture() async -> Bool {
    let granted = await withCheckedContinuation { ... }
    ...
}
```

### When to use which:
- **GCD `async`**: Fire-and-forget work, timed delays, serial queue isolation
- **GCD `asyncAfter`**: Delayed work that must not block the caller (driver name refresh, UI updates)
- **`async/await`**: User-initiated operations that need a result, sequential async work
- **Never use `Task.sleep`**: When you need a delayed action on the main thread, use `DispatchQueue.main.asyncAfter`

## Concurrency Pitfalls in This Codebase

### NSApp Timing
`NSApp` is **nil** during `@main` init. Defer access:
```swift
init() {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### Weak References in Closures
Always use `[weak self]` in GCD dispatch closures to prevent retain cycles:
```swift
volumeForwardQueue.async { [weak self] in
    self?.forwardVolumeToOutput(newVolume, outputID: outputID)
}
```

### Sendable Closures
Closures passed across actor boundaries must be `@Sendable`. This means:
- Cannot capture mutable local state
- Cannot capture non-Sendable types
- Must be free of side effects that violate actor isolation

### @MainActor and View Models
View models hold `unowned` store references (not `weak`) because their lifecycle is bounded by the view:
```swift
@MainActor @Observable final class RoutingViewModel {
    private unowned let store: EqualiserStore
}
```

This is safe because:
- View models are created by views
- Views are owned by SwiftUI (main actor)
- Store outlives all views
- `unowned` avoids reference cycles without optional unwrapping