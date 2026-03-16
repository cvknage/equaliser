# Phase 5: Protocol Abstractions

## Goal

Add protocol abstractions for coordinators and key services to enable test mocking and improve separation of concerns. This phase creates protocols for components that have business logic suitable for unit testing.

---

## Current State Analysis

### Existing Protocols (from Phases 1-2)

| Protocol | File | Purpose |
|----------|------|---------|
| `DeviceEnumerating` | `Device/Protocols/` | Device enumeration |
| `VolumeControlling` | `Device/Protocols/` | Volume/mute control |
| `SampleRateObserving` | `Device/Protocols/` | Sample rate observation |
| `DriverDeviceDiscovering` | `Driver/Protocols/` | Driver device discovery |
| `DriverPropertyAccessing` | `Driver/Protocols/` | Driver property access |
| `DriverLifecycleManaging` | `Driver/Protocols/` | Driver install/uninstall |

### Components Without Protocols

| Component | Lines | Testable Logic | SwiftUI Dependency |
|-----------|-------|----------------|-------------------|
| `CompareModeTimer` | 45 | Timer logic | None |
| `AudioRoutingCoordinator` | 601 | Device selection logic | `@Published` properties |
| `VolumeSyncCoordinator` | 48 | Thin wrapper | None |
| `SystemDefaultObserver` | 184 | Default device logic | Callbacks only |
| `DeviceChangeHandler` | 122 | History management | `@Published` |
| `EqualiserStore` | 473 | State coordination | `@Published` properties |
| `EQConfiguration` | - | Pure data model | `ObservableObject` |
| `PresetManager` | - | File I/O, preset logic | `@Published` |

### What's Worth Abstracting?

**High Value (business logic suitable for mocking):**
1. `CompareModeTimer` - Simple timer logic, easy to mock
2. `SystemDefaultObserver` - Default device detection logic

**Medium Value (complexity vs benefit tradeoff):**
3. `AudioRoutingCoordinator` - Device selection logic (`determineAutomaticOutputDevice`) is pure and testable

**Low Value (SwiftUI tightly coupled or thin wrappers):**
- `VolumeSyncCoordinator` - Thin wrapper around `VolumeManager`
- `DeviceChangeHandler` - Simple history management
- `EqualiserStore` - Most logic is SwiftUI property forwarding

---

## Architectural Considerations

### SwiftUI and Protocols

SwiftUI's `@Published` and `ObservableObject` don't compose well with protocols:
- A protocol can't have `@Published` properties
- Can't use `@ObservedObject` with a protocol type

**Solution**: Use protocols for the **imperative API** (methods), not reactive state:
```swift
// Protocol for actions
protocol CompareModeTimerControlling {
    func start()
    func cancel()
    var onRevert: (() -> Void)? { get set }
}

// Concrete type still handles SwiftUI state
final class CompareModeTimer: CompareModeTimerControlling, ObservableObject {
    @Published var isActive: Bool = false
    // ...
}
```

### Testing Strategy

For components with protocols:
1. Create mock implementations
2. Test business logic without CoreAudio/HAL dependencies
3. Verify callback invocations

---

## Target Architecture

```
Sources/Core/Protocols/
├── CompareModeTimerControlling.swift    ← Protocol for timer
├── SystemDefaultObserving.swift         ← Protocol for default device
└── (future protocols)

Tests/
├── Mocks/
│   ├── MockCompareModeTimer.swift
│   └── MockSystemDefaultObserver.swift
└── AudioRoutingCoordinatorTests.swift   ← Tests for device selection logic
```

---

## Step-by-Step Implementation Plan

### Step 1: Create CompareModeTimerControlling Protocol

**File**: `Sources/Core/Protocols/CompareModeTimerControlling.swift`

**Content**:
```swift
/// Protocol for compare mode auto-revert timer.
/// Allows mocking in tests without waiting for real timers.
@MainActor
protocol CompareModeTimerControlling: AnyObject {
    /// Callback invoked when timer fires.
    var onRevert: (() -> Void)? { get set }
    
    /// Starts the auto-revert timer.
    func start()
    
    /// Cancels the auto-revert timer.
    func cancel()
}
```

**Changes to `CompareModeTimer`**:
- Add conformance: `final class CompareModeTimer: CompareModeTimerControlling`
- No other changes needed (existing implementation matches protocol)

---

### Step 2: Create SystemDefaultObserving Protocol

**File**: `Sources/Core/Protocols/SystemDefaultObserving.swift`

**Content**:
```swift
import Foundation
import CoreAudio

/// Protocol for observing macOS system default output device.
/// Allows mocking in tests without real CoreAudio calls.
@MainActor
protocol SystemDefaultObserving: AnyObject {
    /// Whether the app is currently setting the system default (loop prevention).
    var isAppSettingSystemDefault: Bool { get }
    
    /// Callback invoked when system default changes.
    var onSystemDefaultChanged: ((AudioDevice) -> Void)? { get set }
    
    /// Starts observing system default output changes.
    func startObserving()
    
    /// Stops observing.
    func stopObserving()
    
    /// Gets the current system default output device UID.
    func getCurrentSystemDefaultOutputUID() -> String?
    
    /// Restores the system default output device.
    @discardableResult
    func restoreSystemDefaultOutput(to uid: String) -> Bool
    
    /// Sets driver as system default with loop prevention.
    func setDriverAsDefault(onSuccess: (() -> Void)?, onFailure: (() -> Void)?)
    
    /// Clears the app-setting-default flag after a delay.
    func clearAppSettingFlagAfterDelay()
}
```

**Changes to `SystemDefaultObserver`**:
- Add conformance: `final class SystemDefaultObserver: SystemDefaultObserving`
- No other changes needed

---

### Step 3: Add Static Device Selection Tests

The `determineAutomaticOutputDevice` function is already a static method and is highly testable. We should add more comprehensive tests.

**File**: `Tests/AudioRoutingCoordinatorTests.swift`

**Tests to add**:
```swift
// Already tested in EqualiserStoreTests.swift, but should be in AudioRoutingCoordinatorTests
- testDetermineAutomaticOutputDevice_preservesValidSelection
- testDetermineAutomaticOutputDevice_usesMacDefault_whenNoValidSelection
- testDetermineAutomaticOutputDevice_usesMacDefault_whenCurrentIsDriver
- testDetermineAutomaticOutputDevice_needsFallback_whenDriverIsMacDefault
- testDetermineAutomaticOutputDevice_needsFallback_whenNoValidDevices
- etc.
```

---

### Step 4: Create Mock Implementations for Testing

**File**: `Tests/Mocks/MockCompareModeTimer.swift`

```swift
@testable import Equaliser
import Foundation

/// Mock compare mode timer for testing.
@MainActor
final class MockCompareModeTimer: CompareModeTimerControlling {
    var onRevert: (() -> Void)?
    
    var startCallCount = 0
    var cancelCallCount = 0
    var isStarted = false
    
    func start() {
        startCallCount += 1
        isStarted = true
    }
    
    func cancel() {
        cancelCallCount += 1
        isStarted = false
    }
    
    /// Simulates timer firing (for testing)
    func simulateRevert() {
        onRevert?()
    }
}
```

**File**: `Tests/Mocks/MockSystemDefaultObserver.swift`

```swift
@testable import Equaliser
import Foundation
import CoreAudio

/// Mock system default observer for testing.
@MainActor
final class MockSystemDefaultObserver: SystemDefaultObserving {
    var isAppSettingSystemDefault = false
    var onSystemDefaultChanged: ((AudioDevice) -> Void)?
    
    var startObservingCallCount = 0
    var stopObservingCallCount = 0
    
    var stubbedDefaultUID: String?
    var stubbedRestoreSuccess = true
    
    func startObserving() {
        startObservingCallCount += 1
    }
    
    func stopObserving() {
        stopObservingCallCount += 1
    }
    
    func getCurrentSystemDefaultOutputUID() -> String? {
        stubbedDefaultUID
    }
    
    func restoreSystemDefaultOutput(to uid: String) -> Bool {
        stubbedRestoreSuccess
    }
    
    func setDriverAsDefault(onSuccess: (() -> Void)?, onFailure: (() -> Void)?) {
        onSuccess?()
    }
    
    func clearAppSettingFlagAfterDelay() {
        // No-op in mock
    }
    
    /// Simulates system default change (for testing)
    func simulateDefaultChange(_ device: AudioDevice) {
        onSystemDefaultChanged?(device)
    }
}
```

---

### Step 5: Verify AudioRoutingCoordinator Uses Protocol

**File**: `Sources/Core/Coordinators/AudioRoutingCoordinator.swift`

The coordinator already uses `SystemDefaultObserver` through dependency injection. We can optionally update the type annotation to use the protocol:

```swift
// Current:
private let systemDefaultObserver: SystemDefaultObserver

// Optional change (for flexibility):
private let systemDefaultObserver: SystemDefaultObserving
```

**Decision**: Keep concrete type for now. The protocol is primarily for testing. The coordinator can still work with the concrete type since it has full access.

---

## Files Summary

```
Sources/Core/Protocols/
├── CompareModeTimerControlling.swift    ← NEW: Protocol
└── SystemDefaultObserving.swift          ← NEW: Protocol

Sources/Core/Coordinators/
├── CompareModeTimer.swift               ← ADD: Protocol conformance
└── SystemDefaultObserver.swift          ← ADD: Protocol conformance

Tests/Mocks/
├── MockCompareModeTimer.swift           ← NEW: Mock implementation
└── MockSystemDefaultObserver.swift       ← NEW: Mock implementation

Tests/
└── AudioRoutingCoordinatorTests.swift    ← NEW: Device selection tests
```

---

## Testing Strategy

### Testable Business Logic

1. **CompareModeTimer**
   - Test: Timer starts correctly
   - Test: Timer cancels correctly
   - Test: onRevert callback fires

2. **SystemDefaultObserver**
   - Test: getCurrentSystemDefaultOutputUID returns correct UID
   - Test: restoreSystemDefaultOutput calls CoreAudio correctly (integration test)

3. **AudioRoutingCoordinator.determineAutomaticOutputDevice**
   - Already tested as static method
   - Tests verify device selection logic

### Integration Tests

Keep using real implementations for:
- Audio pipeline integration tests
- Device enumeration tests
- Full app smoke tests

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Protocol doesn't match implementation | Low | Medium | Protocol extracted from existing code |
| Test mock drift | Low | Low | Mocks are simple, match protocol |
| SwiftUI binding issues | None | None | Not using protocols for SwiftUI state |

---

## Verification Checklist

- [ ] `swift build` compiles without errors
- [ ] `swift test` passes all tests (153+ tests)
- [ ] Mock implementations compile
- [ ] Mock-based tests work
- [ ] Real app still works with concrete implementations

---

## Future Considerations

This phase creates the **foundation** for protocol-based testing. Future refactoring could:

1. Add `PresetManaging` protocol for `PresetManager`
2. Add `EQConfiguring` protocol for `EQConfiguration`
3. Create a full mock suite for integration testing
4. Use protocol composition for dependency injection in production code

However, these are **not** included in Phase 5 because:
- `PresetManager` and `EQConfiguration` are storage-free models
- Most testing benefit comes from mocking I/O (CoreAudio), not models
- SwiftUI state management works better with concrete types

---

## Success Criteria

1. ✅ Protocols defined for `CompareModeTimer` and `SystemDefaultObserver`
2. ✅ Concrete types conform to protocols
3. ✅ Mock implementations available for testing
4. ✅ All tests pass (153+ tests)
5. ✅ No behavior changes in production code