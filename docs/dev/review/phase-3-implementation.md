# Phase 3: Architecture Refactoring - Detailed Implementation Plan

**Priority:** P1-P2  
**Estimated Effort:** 3-5 days  
**Risk Level:** Medium (affects core coordinators)

---

## Goal

Resolve SOLID principle violations and improve maintainability through targeted extraction and refactoring.

---

## Problems Identified

### Problem 3.1: Driver Name Management in AudioRoutingCoordinator

**Location:** `src/store/coordinators/AudioRoutingCoordinator.swift:661-743`

```swift
// MARK: - Driver Name Management

/// Updates the driver name based on current routing state.
/// [100+ lines of driver naming logic embedded in coordinator]
@discardableResult
private func updateDriverName() -> Bool {
    // Manual mode or not routing: reset to default name
    guard !manualModeEnabled else { ... }
    
    // Complex toggle pattern for CoreAudio refresh...
    if success, let _ = driverAccess.deviceID {
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ... }
    }
}
```

**Analysis:**
- `AudioRoutingCoordinator` is 743 lines
- Driver naming logic is ~80 lines embedded within
- Contains CoreAudio refresh workarounds specific to driver naming
- Violates Single Responsibility Principle

**Impact:** Hard to test driver naming independently, difficult to modify.

---

### Problem 3.2: DeviceManager Already Uses Focused Protocols

**Location:** `src/services/device/DeviceManager.swift`

**Analysis:**
Upon review, `DeviceManager` already delegates to focused services with proper protocols:
- `DeviceEnumerationService` implements `Enumerating` protocol
- `DeviceVolumeService` implements `VolumeControlling` protocol  
- `DeviceSampleRateService` implements `SampleRateObserving` protocol

The facade pattern is intentional and correct:
```swift
@MainActor
final class DeviceManager: ObservableObject {
    let enumerator: DeviceEnumerationService      // Enumerating
    let volume: VolumeControlling                // VolumeControlling
    let sampleRate: SampleRateObserving           // SampleRateObserving
}
```

**Impact:** No changes needed - architecture is correct.

---

### Problem 3.3: EqualiserStore Design

**Location:** `src/store/EqualiserStore.swift`

**Analysis:**
`EqualiserStore` (571 lines) is actually well-structured as a thin coordinator:
- Delegates EQ band control to `EQConfiguration`
- Delegates routing to `AudioRoutingCoordinator`
- Delegates device changes to `DeviceChangeCoordinator`
- Delegates persistence to `AppStatePersistence`

The computed properties for `inputGain`, `outputGain`, `isBypassed`, etc. are forwarding wrappers - a reasonable coordinator pattern.

**Impact:** No major refactoring needed - architecture is sound.

---

### Problem 3.4: Meter Processing on Main Thread

**Location:** `src/services/meters/MeterStore.swift:135-143`

```swift
func startMeterUpdates() {
    guard meterTimer == nil else { return }
    guard metersEnabled else { return }
    
    meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            self?.refreshMeterSnapshot()  // Runs on main thread
        }
}
```

**Analysis:**
- Timer fires on main thread at 30 FPS
- `refreshMeterSnapshot()` does calculations synchronously
- UI updates require main thread, but calculations don't

**Impact:** Minor UI responsiveness during meter updates.

---

## Architectural Approach

### Strategy: Focused Extraction

Only extract what provides clear value:

| Component | Action | Rationale |
|-----------|--------|-----------|
| DriverNameManager | **Extract** | Clear SRP violation, complex logic, testable independently |
| DeviceManager | **No change** | Already uses focused protocols correctly |
| EqualiserStore | **No change** | Thin coordinator pattern is correct |
| MeterStore | **Optimize** | Move calculations off main thread |

### New Component: DriverNameManager

```
┌─────────────────────────────────────────────────────────────┐
│                  AudioRoutingCoordinator                    │
│                                                            │
│  - deviceManager: DeviceManager                            │
│  - driverAccess: DriverAccessing                           │
│  - driverNameManager: DriverNameManager ◄── NEW            │
│  - systemDefaultObserver: SystemDefaultObserver             │
│  - ...                                                     │
│                                                            │
│  func reconfigureRouting() {                                │
│    ...                                                     │
│    driverNameManager.updateDriverName(...)                  │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ delegates to
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     DriverNameManager                        │
│                                                            │
│  - driverAccess: DriverAccessing                            │
│  - systemDefaultObserver: SystemDefaultObserver             │
│  - deviceManager: DeviceManager                            │
│                                                            │
│  func updateDriverName(                                     │
│      manualMode: Bool,                                      │
│      outputDevice: AudioDevice?,                            │
│      selectedOutputUID: String?                            │
│  ) async -> Bool                                            │
│                                                            │
│  // CoreAudio refresh workaround encapsulated               │
└─────────────────────────────────────────────────────────────┘
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/services/audio/DriverNameManager.swift` | **NEW** - Extract driver naming logic |
| `src/store/coordinators/AudioRoutingCoordinator.swift` | Use `DriverNameManager` |
| `src/services/meters/MeterStore.swift` | Move calculations off main thread |

---

## Step-by-Step Implementation

### Step 1: Create DriverNameManager

**File:** `src/services/audio/DriverNameManager.swift` (NEW)

```swift
// DriverNameManager.swift
// Manages driver device naming with CoreAudio refresh workaround

import Foundation
import OSLog

/// Manages the Equaliser driver's display name.
/// 
/// The driver name is updated to reflect the current output device:
/// - Automatic mode: "{OutputDeviceName} (Equaliser)"
/// - Manual mode: "Equaliser"
///
/// ## CoreAudio Refresh Workaround
/// After renaming the driver, CoreAudio caches the old name. This manager
/// implements a workaround pattern:
/// 1. Set driver name via CoreAudio property
/// 2. Set output device as default (triggers notification)
/// 3. After delay, set driver as default again (triggers notification)
/// 4. Refresh device list to get updated name
@MainActor
final class DriverNameManager {
    
    // MARK: - Dependencies
    
    private let driverAccess: DriverAccessing
    private let systemDefaultObserver: SystemDefaultObserver
    private let deviceManager: DeviceManager
    
    private let logger = Logger(
        subsystem: "net.knage.equaliser",
        category: "DriverNameManager"
    )
    
    // MARK: - Initialization
    
    init(
        driverAccess: DriverAccessing,
        systemDefaultObserver: SystemDefaultObserver,
        deviceManager: DeviceManager
    ) {
        self.driverAccess = driverAccess
        self.systemDefaultObserver = systemDefaultObserver
        self.deviceManager = deviceManager
    }
    
    // MARK: - Public API
    
    /// Updates the driver name based on current routing state.
    ///
    /// - Parameters:
    ///   - manualMode: Whether manual mode is active
    ///   - selectedOutputUID: The currently selected output device UID
    ///   - selectedOutputDevice: The output device (if available)
    /// - Returns: `true` if name was set successfully, `false` otherwise
    @discardableResult
    func updateDriverName(
        manualMode: Bool,
        selectedOutputUID: String?,
        selectedOutputDevice: AudioDevice?
    ) async -> Bool {
        // Manual mode: reset to default name
        guard !manualMode else {
            return await resetDriverName(outputUID: selectedOutputUID)
        }
        
        // Automatic mode: need output device and visible driver
        guard let outputUID = selectedOutputUID,
              let outputDevice = selectedOutputDevice,
              driverAccess.isDriverVisible() else {
            logger.warning("updateDriverName: cannot update - no output device or driver not visible")
            return false
        }
        
        let driverName = "\(outputDevice.name) (Equaliser)"
        return await setDriverName(driverName, outputUID: outputUID)
    }
    
    // MARK: - Private Implementation
    
    /// Resets driver name to "Equaliser" (manual mode).
    private func resetDriverName(outputUID: String?) async -> Bool {
        let success = driverAccess.setDeviceName("Equaliser")
        
        guard success, let outputUID = outputUID else {
            return success
        }
        
        // Trigger macOS Control Center refresh
        // When switching from automatic to manual mode:
        // - Driver is already default (from automatic mode)
        // - Setting driver as default again is a no-op (no notification)
        // - Toggle to output device and back to trigger CoreAudio notifications
        
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
        
        // After delay, set driver back as default and refresh
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        systemDefaultObserver.setDriverAsDefault()
        deviceManager.refreshDevices()
        logger.debug("Device list refreshed after driver name reset")
        
        return success
    }
    
    /// Sets driver name to reflect output device (automatic mode).
    private func setDriverName(_ name: String, outputUID: String) async -> Bool {
        let success = driverAccess.setDeviceName(name)
        
        guard success, driverAccess.deviceID != nil else {
            return success
        }
        
        // Trigger macOS Control Center refresh
        // When switching from manual to automatic mode:
        // - Driver may or may not be the current default
        // - Toggle to output device and back to ensure CoreAudio notifications fire
        
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
        
        // After delay, set driver back as default and refresh
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        systemDefaultObserver.setDriverAsDefault()
        deviceManager.refreshDevices()
        logger.debug("Device list refreshed after driver name change to '\(name)'")
        
        return success
    }
}
```

---

### Step 2: Update AudioRoutingCoordinator

**File:** `src/store/coordinators/AudioRoutingCoordinator.swift`

#### 2.1 Add DriverNameManager Dependency

Add to `// MARK: - Dependencies` section:

```swift
// MARK: - Dependencies

let deviceManager: DeviceManager
let deviceChangeCoordinator: DeviceChangeCoordinator
private let eqConfiguration: EQConfiguration
private let meterStore: MeterStore
private let volumeService: VolumeControlling
private let systemDefaultObserver: SystemDefaultObserver
private let sampleRateService: SampleRateObserving
private let driverAccess: DriverAccessing
private let driverNameManager: DriverNameManager  // NEW
```

#### 2.2 Update Initializer

```swift
init(
    deviceManager: DeviceManager,
    deviceChangeCoordinator: DeviceChangeCoordinator,
    eqConfiguration: EQConfiguration,
    meterStore: MeterStore,
    volumeService: VolumeControlling,
    systemDefaultObserver: SystemDefaultObserver,
    sampleRateService: SampleRateObserving,
    driverAccess: DriverAccessing? = nil
) {
    self.deviceManager = deviceManager
    self.deviceChangeCoordinator = deviceChangeCoordinator
    self.eqConfiguration = eqConfiguration
    self.meterStore = meterStore
    self.volumeService = volumeService
    self.systemDefaultObserver = systemDefaultObserver
    self.sampleRateService = sampleRateService
    self.driverAccess = driverAccess ?? DriverManager.shared
    
    // Create driver name manager
    self.driverNameManager = DriverNameManager(
        driverAccess: self.driverAccess,
        systemDefaultObserver: systemDefaultObserver,
        deviceManager: deviceManager
    )
    
    // ... rest of init unchanged
}
```

#### 2.3 Replace updateDriverName() Implementation

Replace the existing `updateDriverName()` method with:

```swift
// MARK: - Driver Name Management

/// Updates the driver name based on current routing state.
/// Delegates to DriverNameManager for the CoreAudio refresh workaround.
/// - Returns: `true` if name was set successfully, `false` otherwise.
@discardableResult
private func updateDriverName() async -> Bool {
    let outputDevice = selectedOutputDeviceID.flatMap { deviceManager.device(forUID: $0) }
    
    return await driverNameManager.updateDriverName(
        manualMode: manualModeEnabled,
        selectedOutputUID: selectedOutputDeviceID,
        selectedOutputDevice: outputDevice
    )
}
```

**Note:** The method signature changes from sync to async, so call sites need to use `await`.

#### 2.4 Update Call Sites

Find all `updateDriverName()` call sites and add `await`:

```swift
// Before
_ = updateDriverName()

// After
await updateDriverName()
```

Call sites are typically in:
- `stopRouting()`
- Device change handlers
- Mode switch handlers

---

### Step 3: Refactor DispatchQueue to Task

**File:** `src/store/coordinators/AudioRoutingCoordinator.swift`

Replace the `DispatchQueue.main.asyncAfter` pattern in the removed `updateDriverName()` implementation. Since the logic is now in `DriverNameManager` using `Task.sleep`, this is handled automatically.

---

### Step 4: Optimize Meter Processing

**File:** `src/services/meters/MeterStore.swift`

#### 4.1 Add Background Queue

```swift
// MARK: - Private Properties

private var meterTimer: AnyCancellable?
private let meterInterval: TimeInterval = 1.0 / 30.0  // 30 FPS
private let meterQueue = DispatchQueue(label: "net.knage.equaliser.meters", qos: .userInteractive)
```

#### 4.2 Update startMeterUpdates()

```swift
func startMeterUpdates() {
    guard meterTimer == nil else { return }
    guard metersEnabled else { return }
    
    meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            // Dispatch calculation to background queue
            self?.meterQueue.async { [weak self] in
                self?.refreshMeterSnapshot()
            }
        }
}
```

**Note:** This requires `refreshMeterSnapshot` to be thread-safe. Since it only reads from `renderPipeline` and writes to local state, it should be safe. However, any UI updates must dispatch back to main thread.

#### 4.3 Ensure Thread Safety

Check `refreshMeterSnapshot()` for any main thread dependencies:

```swift
private func refreshMeterSnapshot() {
    guard metersEnabled else {
        DispatchQueue.main.async { [weak self] in
            self?.notifyAllObserversSilent()
        }
        return
    }
    
    // ... meter calculations (now on background queue) ...
    
    // UI updates must be on main thread
    DispatchQueue.main.async { [weak self] in
        self?.notifyObservers(for: .inputPeakLeft, value: leftPeak)
        // ... etc
    }
}
```

---

## Test Plan

### Unit Tests for DriverNameManager

**File:** `tests/services/audio/DriverNameManagerTests.swift` (NEW)

```swift
import XCTest
@testable import Equaliser

@MainActor
final class DriverNameManagerTests: XCTestCase {
    
    var mockDriverAccess: MockDriverManager!
    var mockSystemDefaultObserver: MockSystemDefaultObserver!
    var mockDeviceManager: DeviceManager!
    var driverNameManager: DriverNameManager!
    
    override func setUp() async throws {
        try await super.setUp()
        mockDriverAccess = MockDriverManager()
        mockSystemDefaultObserver = MockSystemDefaultObserver()
        // Note: DeviceManager requires real CoreAudio, so we use a simplified setup
    }
    
    func testUpdateDriverName_automaticMode_setsDeviceName() async {
        // Given
        mockDriverAccess.configureReadyDriver(deviceID: 1234)
        mockDriverAccess.stubbedIsDriverVisible = true
        mockDriverAccess.stubbedSetDeviceNameSuccess = true
        
        // When
        let result = await driverNameManager.updateDriverName(
            manualMode: false,
            selectedOutputUID: "output-uid",
            selectedOutputDevice: AudioDevice(
                id: 5678,
                uid: "output-uid",
                name: "Speakers",
                isInput: false,
                isOutput: true,
                transportType: 0
            )
        )
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockDriverAccess.lastDeviceName, "Speakers (Equaliser)")
    }
    
    func testUpdateDriverName_manualMode_resetsToEqualiser() async {
        // Given
        mockDriverAccess.stubbedSetDeviceNameSuccess = true
        
        // When
        let result = await driverNameManager.updateDriverName(
            manualMode: true,
            selectedOutputUID: "output-uid",
            selectedOutputDevice: nil
        )
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockDriverAccess.lastDeviceName, "Equaliser")
    }
    
    func testUpdateDriverName_driverNotVisible_returnsFalse() async {
        // Given
        mockDriverAccess.stubbedIsDriverVisible = false
        
        // When
        let result = await driverNameManager.updateDriverName(
            manualMode: false,
            selectedOutputUID: "output-uid",
            selectedOutputDevice: nil
        )
        
        // Then
        XCTAssertFalse(result)
    }
}
```

### Integration Tests

Verify the async `updateDriverName()` calls work correctly:
1. Launch app
2. Switch between automatic and manual mode
3. Verify driver name updates in CoreAudio

---

## Rollback Strategy

If issues arise:

1. **Git revert:**
   ```bash
   git revert <commit-hash>
   ```

2. **Restore inline logic:**
   - Revert `AudioRoutingCoordinator` to use inline `updateDriverName()` 
   - Delete `DriverNameManager.swift`

---

## Success Criteria

- [ ] `AudioRoutingCoordinator` reduced from ~743 to ~660 lines
- [ ] `DriverNameManager` created with ~100 lines
- [ ] All existing tests pass
- [ ] New `DriverNameManagerTests` pass
- [ ] Build succeeds in release mode
- [ ] Driver name updates correctly in both modes
- [ ] Meter calculations no longer block main thread

---

## Notes

### Why Not Refactor DeviceManager Further?

`DeviceManager` correctly uses the facade pattern with delegated services:
- Each service has a focused protocol
- The facade provides a unified API
- Tests can mock individual services

This is the intended design - no ISP violation exists.

### Why Not Refactor EqualiserStore?

`EqualiserStore` is a thin coordinator:
- Computed properties delegate to `EQConfiguration`
- Routing delegates to `AudioRoutingCoordinator`
- No state container responsibilities beyond coordination

This follows the documented coordinator pattern correctly.

### Why Move Meter Calculations?

The performance impact is minor (30 FPS calculations are fast), but:
- Removes any potential UI stutter
- Follows best practices for background work
- Future-proofs for more complex meter calculations

---

*This plan should be followed step-by-step. Each step should be verified with builds and tests before proceeding to the next.*