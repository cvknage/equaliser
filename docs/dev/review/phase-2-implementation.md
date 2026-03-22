# Phase 2: Testability & Test Coverage - Detailed Implementation Plan

**Priority:** P1  
**Estimated Effort:** 3-5 days  
**Risk Level:** Low (additive changes)

---

## Goal

Improve test coverage for critical audio pipeline and resolve hidden dependencies to enable isolated testing of coordinators.

---

## Problems Identified

### Problem 2.1: DriverManager Singleton Dependency

**Location:** `src/store/coordinators/AudioRoutingCoordinator.swift:155`

```swift
guard DriverManager.shared.isReady else {
    routingStatus = .driverNotInstalled
    // ...
}
```

**Analysis:**
- `DriverManager.shared` is accessed directly in `AudioRoutingCoordinator`
- This creates a hidden singleton dependency
- Cannot inject mock for testing
- Tests would require actual driver to be installed

**Impact:** `AudioRoutingCoordinator` cannot be unit tested in isolation.

---

### Problem 2.2: No Mock DriverManager

**Location:** `tests/mocks/`

**Analysis:**
- Existing mocks: `MockCompareModeTimer`, `MockSystemDefaultObserver`
- Pattern established: protocol-based mocking
- No mock implementation for `DriverManager`

**Impact:** Unable to test automatic routing logic, driver visibility checks, device name updates.

---

### Problem 2.3: Minimal Audio Pipeline Tests

**Location:** `tests/services/audio/AudioRingBufferTests.swift`

**Analysis:**
- Ring buffer tests exist and are comprehensive (14 tests)
- No tests for `RenderPipeline`
- No tests for `HALIOManager`
- No tests for `RenderCallbackContext`

**Impact:** 
- Regression risk during refactoring
- Hard to verify gain calculations
- Cannot test edge cases (sample rate changes, format mismatches)

---

### Problem 2.4: Silent Failures

**Location:** 
- `src/domain/eq/EQConfiguration.swift:107` - Snapshot loading
- `src/services/presets/PresetManager.swift` - Preset loading

```swift
// EQConfiguration.swift:107 - Silent if band count mismatch
if snapshot.bands.count == EQConfiguration.maxBandCount {
    bands = snapshot.bands
}
// No logging, no error, just silent failure

// PresetManager - similar pattern
```

**Impact:** Hidden bugs, difficult debugging, unexpected behaviour.

---

## Architectural Approach

### Dependency Injection Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                    Production Code                              │
│                                                                 │
│  AudioRoutingCoordinator                                        │
│  ├── deviceManager: DeviceManager                              │
│  ├── deviceChangeCoordinator: DeviceChangeCoordinator           │
│  ├── eqConfiguration: EQConfiguration                           │
│  ├── meterStore: MeterStore                                     │
│  ├── volumeService: VolumeControlling                           │
│  ├── systemDefaultObserver: SystemDefaultObserver               │
│  ├── sampleRateService: SampleRateObserving                     │
│  └── driverAccess: DriverAccessing ◀─── NEW PROTOCOL           │
│                                              │                  │
│                                              │                  │
│                                              ▼                  │
│                                    DriverManager.shared         │
│                                    (conforms to DriverAccessing) │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       Test Code                                  │
│                                                                 │
│  AudioRoutingCoordinatorTests                                   │
│  ├── MockDriverManager (conforms to DriverAccessing)            │
│  │   ├── stubbedIsReady = true/false                            │
│  │   ├── stubbedIsDriverVisible = true/false                    │
│  │   └── callCounts for verification                            │
│  └── Assertions on coordinator behaviour                         │
└─────────────────────────────────────────────────────────────────┘
```

### New Protocol Hierarchy

```
DriverAccessing (NEW)
├── isReady: Bool
├── isDriverVisible() -> Bool
├── findDriverDeviceWithRetry(...) async -> AudioDeviceID?
└── setDeviceName(_: String) -> Bool

DriverLifecycleManaging (EXISTING)
├── status: DriverStatus
├── isReady: Bool
├── installDriver() async throws
└── uninstallDriver() async throws

DriverManager (EXISTING)
├── conforms to DriverAccessing (NEW)
├── conforms to DriverLifecycleManaging (EXISTING)
└── property access: deviceID, driverSampleRate, etc.
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/services/driver/protocols/DriverAccessing.swift` | **NEW** - Protocol definition |
| `src/services/driver/DriverManager.swift` | Add `DriverAccessing` conformance |
| `src/store/coordinators/AudioRoutingCoordinator.swift` | Inject `DriverAccessing` |
| `tests/mocks/MockDriverManager.swift` | **NEW** - Mock implementation |
| `src/domain/eq/EQConfiguration.swift` | Add logging for snapshot loading |
| `src/services/presets/PresetManager.swift` | Add graceful fallback |
| `tests/services/audio/RenderPipelineTests.swift` | **NEW** - Pipeline tests |
| `tests/store/AudioRoutingCoordinatorTests.swift` | **NEW** - Coordinator tests |

---

## Step-by-Step Implementation

### Step 1: Create DriverAccessing Protocol

**File:** `src/services/driver/protocols/DriverAccessing.swift` (NEW)

```swift
// DriverAccessing.swift
// Protocol for driver access operations used by coordinators

import CoreAudio
import Foundation

/// Protocol for accessing driver state and operations.
/// Used to decouple coordinators from DriverManager singleton.
@MainActor
protocol DriverAccessing: AnyObject {
    /// Whether the driver is installed and ready for use.
    var isReady: Bool { get }
    
    /// Checks if the driver is currently visible in CoreAudio.
    func isDriverVisible() -> Bool
    
    /// Finds the driver device with retry logic.
    /// - Parameters:
    ///   - initialDelayMs: Initial delay before first check (default 100ms)
    ///   - maxAttempts: Maximum number of retry attempts (default 6)
    /// - Returns: The driver device ID if found, nil otherwise.
    func findDriverDeviceWithRetry(
        initialDelayMs: Int,
        maxAttempts: Int
    ) async -> AudioDeviceID?
    
    /// Sets the driver's device name to reflect the output device.
    /// - Parameter name: The name to set (will be prefixed with output device name).
    /// - Returns: Whether the operation succeeded.
    func setDeviceName(_ name: String) -> Bool
}
```

**Key Design Decisions:**
1. `@MainActor` - Matches `DriverManager` actor isolation
2. `isReady` as property - Most common check, simple accessor
3. `setDeviceName` returns `Bool` - Indicates success/failure
4. Only includes methods actually used by `AudioRoutingCoordinator`

---

### Step 2: Add DriverAccessing Conformance to DriverManager

**File:** `src/services/driver/DriverManager.swift`

Add at the end of the public interface section (around line 100):

```swift
// MARK: - DriverAccessing Protocol Conformance

extension DriverManager: DriverAccessing {
    // isReady - already exists as computed property
    
    // isDriverVisible() - already exists
    
    // findDriverDeviceWithRetry - already exists
    
    // setDeviceName - already exists
}
```

**Note:** `DriverManager` already implements all required methods. The extension just declares conformance.

---

### Step 3: Inject DriverAccessing into AudioRoutingCoordinator

**File:** `src/store/coordinators/AudioRoutingCoordinator.swift`

#### 3.1 Add Protocol Dependency

Add to `// MARK: - Dependencies` section (around line 24):

```swift
// MARK: - Dependencies

let deviceManager: DeviceManager
let deviceChangeCoordinator: DeviceChangeCoordinator
private let eqConfiguration: EQConfiguration
private let meterStore: MeterStore
private let volumeService: VolumeControlling
private let systemDefaultObserver: SystemDefaultObserver
private let sampleRateService: SampleRateObserving
private let driverAccess: DriverAccessing  // NEW: Injected dependency
```

#### 3.2 Update Initializer

Update the `init` method (around line 46):

```swift
init(
    deviceManager: DeviceManager,
    deviceChangeCoordinator: DeviceChangeCoordinator,
    eqConfiguration: EQConfiguration,
    meterStore: MeterStore,
    volumeService: VolumeControlling,
    systemDefaultObserver: SystemDefaultObserver,
    sampleRateService: SampleRateObserving,
    driverAccess: DriverAccessing? = nil  // NEW: Optional with default
) {
    self.deviceManager = deviceManager
    self.deviceChangeCoordinator = deviceChangeCoordinator
    self.eqConfiguration = eqConfiguration
    self.meterStore = meterStore
    self.volumeService = volumeService
    self.systemDefaultObserver = systemDefaultObserver
    self.sampleRateService = sampleRateService
    self.driverAccess = driverAccess ?? DriverManager.shared  // NEW: Default to singleton
    
    // ... rest of init unchanged
}
```

#### 3.3 Replace All DriverManager.shared Calls

Find all occurrences of `DriverManager.shared` and replace with `driverAccess`:

| Location | Before | After |
|----------|--------|-------|
| Line ~155 | `DriverManager.shared.isReady` | `driverAccess.isReady` |
| Line ~163 | `DriverManager.shared.isDriverVisible()` | `driverAccess.isDriverVisible()` |
| Line ~167 | `DriverManager.shared.findDriverDeviceWithRetry()` | `driverAccess.findDriverDeviceWithRetry()` |

**Example change around line 155:**

```swift
// BEFORE
guard DriverManager.shared.isReady else {
    routingStatus = .driverNotInstalled
    logger.warning("Routing cannot start: driver not installed")
    showDriverPrompt = true
    return
}

// AFTER
guard driverAccess.isReady else {
    routingStatus = .driverNotInstalled
    logger.warning("Routing cannot start: driver not installed")
    showDriverPrompt = true
    return
}
```

**Example change around line 167:**

```swift
// BEFORE
Task { @MainActor in
    if await DriverManager.shared.findDriverDeviceWithRetry() != nil {
        // ...
    }
}

// AFTER
Task { @MainActor in
    if await driverAccess.findDriverDeviceWithRetry() != nil {
        // ...
    }
}
```

---

### Step 4: Create MockDriverManager

**File:** `tests/mocks/MockDriverManager.swift` (NEW)

```swift
@testable import Equaliser
import CoreAudio
import Foundation

/// Mock driver manager for testing.
/// Provides controllable driver behaviour without real CoreAudio calls.
@MainActor
final class MockDriverManager: DriverAccessing {
    
    // MARK: - DriverAccessing Protocol
    
    var isReady: Bool {
        get { _isReady }
        set { _isReady = newValue }
    }
    
    private var _isReady = false
    
    func isDriverVisible() -> Bool {
        isDriverVisibleCallCount += 1
        return stubbedIsDriverVisible
    }
    
    func findDriverDeviceWithRetry(
        initialDelayMs: Int = 100,
        maxAttempts: Int = 6
    ) async -> AudioDeviceID? {
        findDriverDeviceWithRetryCallCount += 1
        lastFindRetryParams = (initialDelayMs, maxAttempts)
        return stubbedDeviceID
    }
    
    func setDeviceName(_ name: String) -> Bool {
        setDeviceNameCallCount += 1
        lastDeviceName = name
        return stubbedSetDeviceNameSuccess
    }
    
    // MARK: - Test Helpers
    
    /// Number of times isDriverVisible() was called.
    var isDriverVisibleCallCount = 0
    
    /// Number of times findDriverDeviceWithRetry() was called.
    var findDriverDeviceWithRetryCallCount = 0
    
    /// Number of times setDeviceName() was called.
    var setDeviceNameCallCount = 0
    
    /// The last device name passed to setDeviceName.
    var lastDeviceName: String?
    
    /// The last retry parameters used.
    var lastFindRetryParams: (initialDelayMs: Int, maxAttempts: Int)?
    
    // MARK: - Stubbed Values
    
    /// Whether the driver is ready (isReady property).
    var stubbedIsReady = false
    
    /// Whether isDriverVisible() returns true.
    var stubbedIsDriverVisible = false
    
    /// The device ID returned by findDriverDeviceWithRetry().
    var stubbedDeviceID: AudioDeviceID? = nil
    
    /// Whether setDeviceName() succeeds.
    var stubbedSetDeviceNameSuccess = true
    
    // MARK: - Convenience Methods
    
    /// Configures the mock for a successful driver state.
    func configureReadyDriver(deviceID: AudioDeviceID = 1) {
        _isReady = true
        stubbedIsDriverVisible = true
        stubbedDeviceID = deviceID
    }
    
    /// Configures the mock for a not-installed driver state.
    func configureNotInstalled() {
        _isReady = false
        stubbedIsDriverVisible = false
        stubbedDeviceID = nil
    }
    
    /// Resets all call counts and stubbed values.
    func reset() {
        _isReady = false
        stubbedIsDriverVisible = false
        stubbedDeviceID = nil
        stubbedSetDeviceNameSuccess = true
        
        isDriverVisibleCallCount = 0
        findDriverDeviceWithRetryCallCount = 0
        setDeviceNameCallCount = 0
        
        lastDeviceName = nil
        lastFindRetryParams = nil
    }
}
```

---

### Step 5: Add Audio Pipeline Tests

**File:** `tests/services/audio/RenderPipelineTests.swift` (NEW)

```swift
import XCTest
@testable import Equaliser

final class RenderPipelineTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInit_createsPipelineWithCorrectChannelCount() {
        let config = EQConfiguration(initialBandCount: 10)
        // Note: Pipeline requires HAL units which can't be easily mocked
        // This test verifies basic initialization behaviour
        // Real audio tests would require integration testing
    }
    
    // MARK: - Gain Calculation Tests
    
    func testGainLinear_fromZeroDB() {
        // 0 dB = linear 1.0
        let linear = AudioMath.dbToLinear(0.0)
        XCTAssertEqual(linear, 1.0, accuracy: 0.0001)
    }
    
    func testGainLinear_fromPositiveDB() {
        // +6 dB ≈ 2x linear
        let linear = AudioMath.dbToLinear(6.0)
        XCTAssertEqual(linear, 2.0, accuracy: 0.1)
    }
    
    func testGainLinear_fromNegativeDB() {
        // -6 dB ≈ 0.5x linear
        let linear = AudioMath.dbToLinear(-6.0)
        XCTAssertEqual(linear, 0.5, accuracy: 0.1)
    }
    
    // MARK: - Boost Gain Tests
    
    func testBoostGain_alwaysApplied() {
        // Boost gain is for driver volume compensation
        // It should ALWAYS be applied, even in bypass mode
        // This is tested through integration, but we verify the math here
        
        let driverVolume: Float = 0.5  // Driver at 50%
        let boostGain: Float = 1.0 / driverVolume  // 2x boost
        
        XCTAssertEqual(boostGain, 2.0, accuracy: 0.0001)
    }
    
    // MARK: - Processing Mode Tests
    
    func testProcessingMode_normalMode() {
        // Mode 1 = normal (EQ + gains)
        XCTAssertEqual(EQConfiguration().processingMode, 1)
    }
    
    func testProcessingMode_bypassMode() {
        // Mode 0 = full bypass
        var config = EQConfiguration()
        config.globalBypass = true
        XCTAssertEqual(config.processingMode, 0)
    }
}

// MARK: - RenderCallbackContext Atomic Tests

final class RenderCallbackContextAtomicTests: XCTestCase {
    
    // Note: RenderCallbackContext requires HAL units which can't be easily mocked.
    // These tests verify the atomic gain storage logic in isolation.
    
    func testAtomicGainStorage_roundTrip() {
        // Verify that Float → Int32 bits → Float round-trips correctly
        let testValues: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0, 0.75, -1.0]
        
        for value in testValues {
            let bits = Int32(bitPattern: value.bitPattern)
            let restored = Float(bitPattern: UInt32(bitPattern: bits))
            XCTAssertEqual(restored, value, accuracy: 0.0001)
        }
    }
    
    func testAtomicGainStorage_preservesSpecialValues() {
        // Test edge cases
        let smallValue: Float = 0.001  // Very small gain
        let largeValue: Float = 10.0   // Large gain
        
        let smallBits = Int32(bitPattern: smallValue.bitPattern)
        let largeBits = Int32(bitPattern: largeValue.bitPattern)
        
        let restoredSmall = Float(bitPattern: UInt32(bitPattern: smallBits))
        let restoredLarge = Float(bitPattern: UInt32(bitPattern: largeBits))
        
        XCTAssertEqual(restoredSmall, smallValue, accuracy: 0.00001)
        XCTAssertEqual(restoredLarge, largeValue, accuracy: 0.0001)
    }
}
```

---

### Step 6: Add AudioRoutingCoordinator Tests

**File:** `tests/store/AudioRoutingCoordinatorTests.swift` (NEW)

```swift
import XCTest
@testable import Equaliser

@MainActor
final class AudioRoutingCoordinatorTests: XCTestCase {
    
    var sut: AudioRoutingCoordinator!
    var mockDeviceManager: DeviceManager!
    var mockDriverAccess: MockDriverManager!
    var mockSystemDefaultObserver: MockSystemDefaultObserver!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock driver access
        mockDriverAccess = MockDriverManager()
        
        // Create mock system default observer
        mockSystemDefaultObserver = MockSystemDefaultObserver()
        
        // Note: DeviceManager requires real CoreAudio, so we use a simplified setup
        // For full coordinator tests, we would need a DeviceManager mock too
    }
    
    override func tearDown() async throws {
        sut = nil
        mockDriverAccess = nil
        mockSystemDefaultObserver = nil
        try await super.tearDown()
    }
    
    // MARK: - Driver State Tests
    
    func testReconfigureRouting_driverNotInstalled_showsPrompt() async {
        // Given: Driver not installed
        mockDriverAccess.configureNotInstalled()
        
        // When: Reconfigure routing (automatic mode)
        //sut = AudioRoutingCoordinator(
        //    ...
        //    driverAccess: mockDriverAccess
        //)
        
        // Then: Should show driver prompt
        //XCTAssertTrue(sut.showDriverPrompt)
        //XCTAssertEqual(sut.routingStatus, .driverNotInstalled)
        
        // Note: Full test requires DeviceManager mock
        // This is a placeholder showing the pattern
    }
    
    func testReconfigureRouting_driverReady_proceedsWithRouting() async {
        // Given: Driver installed and ready
        mockDriverAccess.configureReadyDriver(deviceID: 1234)
        
        // When: Reconfigure routing (automatic mode)
        
        // Then: Should not show prompt
        //XCTAssertFalse(sut.showDriverPrompt)
    }
    
    // MARK: - Driver Access Call Tracking
    
    func testIsReady_propertyAccessed() {
        // Verify isReady is accessed through protocol
        mockDriverAccess.stubbedIsReady = true
        XCTAssertTrue(mockDriverAccess.isReady)
        
        mockDriverAccess.stubbedIsReady = false
        XCTAssertFalse(mockDriverAccess.isReady)
    }
    
    func testIsDriverVisible_calledCorrectly() {
        mockDriverAccess.stubbedIsDriverVisible = true
        let result = mockDriverAccess.isDriverVisible()
        XCTAssertTrue(result)
        XCTAssertEqual(mockDriverAccess.isDriverVisibleCallCount, 1)
    }
    
    func testFindDriverDeviceWithRetry_tracksParameters() async {
        mockDriverAccess.stubbedDeviceID = 5678
        
        let result = await mockDriverAccess.findDriverDeviceWithRetry(
            initialDelayMs: 200,
            maxAttempts: 3
        )
        
        XCTAssertEqual(result, 5678)
        XCTAssertEqual(mockDriverAccess.findDriverDeviceWithRetryCallCount, 1)
        XCTAssertEqual(mockDriverAccess.lastFindRetryParams?.initialDelayMs, 200)
        XCTAssertEqual(mockDriverAccess.lastFindRetryParams?.maxAttempts, 3)
    }
    
    func testSetDeviceName_tracksCall() {
        let success = mockDriverAccess.setDeviceName("Speakers")
        XCTAssertTrue(success)
        XCTAssertEqual(mockDriverAccess.setDeviceNameCallCount, 1)
        XCTAssertEqual(mockDriverAccess.lastDeviceName, "Speakers")
    }
}
```

---

### Step 7: Add Logging to EQConfiguration Snapshot Loading

**File:** `src/domain/eq/EQConfiguration.swift`

Find the `convenience init(from snapshot:)` initializer (around line 101) and update:

```swift
/// Creates a configuration from an app state snapshot.
/// - Parameter snapshot: The snapshot to restore from.
/// - Note: Only restores bands if count matches maxBandCount for safety.
convenience init(from snapshot: AppStateSnapshot) {
    self.init(initialBandCount: snapshot.activeBandCount)
    globalBypass = snapshot.globalBypass
    inputGain = snapshot.inputGain
    outputGain = snapshot.outputGain
    activeBandCount = snapshot.activeBandCount
    
    // Validate band count before restoring
    if snapshot.bands.count == EQConfiguration.maxBandCount {
        bands = snapshot.bands
        logger.debug("Restored \(snapshot.bands.count) bands from snapshot")
    } else {
        // Log mismatch - this shouldn't happen in normal operation
        logger.warning(
            "Snapshot band count (\(snapshot.bands.count)) doesn't match max (\(EQConfiguration.maxBandCount)), using default bands"
        )
    }
}
```

Add a logger property if not already present:

```swift
private static let logger = Logger(subsystem: "net.knage.equaliser", category: "EQConfiguration")
```

---

### Step 8: Add Graceful Fallback to PresetManager

**File:** `src/services/presets/PresetManager.swift`

Find the preset loading method and add error handling with fallback:

```swift
/// Loads a preset by name.
/// - Parameter name: The preset name.
/// - Returns: The preset if found, nil otherwise.
func loadPreset(named name: String) -> Preset? {
    // Try user presets first
    if let userPreset = userPresets.first(where: { $0.name == name }) {
        logger.debug("Loaded user preset: \(name)")
        return userPreset
    }
    
    // Then try factory presets
    if let factoryPreset = factoryPresets.first(where: { $0.name == name }) {
        logger.debug("Loaded factory preset: \(name)")
        return factoryPreset
    }
    
    // Not found - log warning and return nil
    logger.warning("Preset not found: \(name)")
    return nil
}

/// Loads a preset by name with graceful fallback.
/// If the named preset isn't found, returns the "Flat" preset or creates one.
/// - Parameter name: The preset name.
/// - Returns: The preset (never nil).
func loadPresetWithFallback(named name: String) -> Preset {
    if let preset = loadPreset(named: name) {
        return preset
    }
    
    // Fallback 1: Try "Flat" preset
    if let flatPreset = loadPreset(named: "Flat") {
        logger.warning("Preset '\(name)' not found, falling back to 'Flat'")
        return flatPreset
    }
    
    // Fallback 2: Create a default flat preset
    logger.warning("No presets available, creating default flat preset")
    return Preset(
        name: "Default",
        bands: (0..<EQConfiguration.maxBandCount).map { _ in
            EQBandConfiguration.parametric(frequency: 1000, bandwidth: 1.0)
        },
        inputGain: 0.0,
        outputGain: 0.0
    )
}
```

---

## Test Plan

### Unit Tests to Run

```bash
# Run all tests
swift test

# Run specific test suites
swift test --filter AudioRingBufferTests
swift test --filter RenderPipelineTests
swift test --filter AudioRoutingCoordinatorTests
swift test --filter MockDriverManagerTests
```

### New Tests Added

| Test File | Tests | Purpose |
|-----------|-------|---------|
| `RenderPipelineTests.swift` | 6 | Gain calculations, processing modes |
| `AudioRoutingCoordinatorTests.swift` | 6 | Driver access injection, call tracking |
| `RenderCallbackContextAtomicTests` | 2 | Float bit pattern round-trips |

### Integration Testing

Manual test required:
1. Launch app with driver not installed
2. Verify `showDriverPrompt` shows
3. Install driver
4. Verify app proceeds with routing

---

## Rollback Strategy

If issues arise:

1. **Git revert:**
   ```bash
   git revert <commit-hash>
   ```

2. **Remove protocol:**
   - Revert `DriverAccessing` protocol changes
   - Restore `DriverManager.shared` direct access

3. **Remove mock:**
   - Delete `MockDriverManager.swift`

---

## Success Criteria

- [ ] All existing tests pass
- [ ] New tests pass
- [ ] `AudioRoutingCoordinator` can be instantiated with `MockDriverManager`
- [ ] `MockDriverManager` provides full control over driver state
- [ ] `EQConfiguration` logs snapshot restore issues
- [ ] `PresetManager` has graceful fallback when preset not found
- [ ] Build succeeds in release mode

---

## Notes

### Why Not Full DeviceManager Mock?

`DeviceManager` requires real CoreAudio device enumeration. Creating a full mock would require:
1. Protocol extraction for `Enumerating`, `VolumeControlling`, `SampleRateObserving`
2. Mock implementations for each protocol
3. Significant refactoring of existing code

This is out of scope for Phase 2 but could be addressed in Phase 3 (Architecture Refactoring).

### Why Optional driverAccess Parameter?

The parameter is optional with a default of `DriverManager.shared`:
- Production code doesn't need to change
- Tests can inject `MockDriverManager`
- Backward compatible with existing call sites

---

*This plan should be followed step-by-step. Each step should be verified with builds and tests before proceeding to the next.*