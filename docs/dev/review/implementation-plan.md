# Phased Implementation Plan: Addressing Code Review Findings

**Created:** March 22, 2026  
**Based On:** Comprehensive Code Review (OpenCode GLM-5 & Claude Opus 4.6)  
**Overall Rating:** 8/10 (Production Ready with Recommended Refactorings)

---

## Executive Summary

This plan addresses the issues identified in the code review across four phases. Each phase is designed to be completed independently, leaving the codebase in a stable, buildable state.

| Phase | Focus | Priority | Effort |
|-------|-------|----------|--------|
| 1 | Critical Safety Fixes | P0 | 1-2 days |
| 2 | Testability & Test Coverage | P1 | 3-5 days |
| 3 | Architecture Refactoring | P1-P2 | 3-5 days |
| 4 | Code Quality Improvements | P2-P3 | 2-3 days |

---

## Phase 1: Critical Safety Fixes (P0)

**Goal:** Address theoretical race condition and deprecated APIs that could cause production issues.

### 1.1 Fix Gain Race Condition

**Problem:** `RenderCallbackContext` uses `nonisolated(unsafe)` for gain values with theoretical race between the main thread writer and audio thread reader.

**Location:** `src/services/audio/rendering/RenderCallbackContext.swift:56-81`

**Impact:** Audio artifacts, potential crashes.

**Approach:**
1. Add `SwiftAtomics` package dependency
2. Convert target gain properties to `ManagedAtomic<Float>`
3. Use atomic load/store operations for cross-thread communication
4. Keep current gain values as `nonisolated(unsafe)` (audio thread only)

**Files to Modify:**
- `Package.swift` - Add Atomics dependency
- `src/services/audio/rendering/RenderCallbackContext.swift` - Atomic properties

**New Types:**
- None (modification only)

---

### 1.2 Replace Deprecated Atomic APIs

**Problem:** `OSAtomicAdd64Barrier` is deprecated in modern Swift.

**Location:** `src/services/audio/rendering/AudioRingBuffer.swift:103-104`

**Impact:** Future compatibility, warning accumulation.

**Approach:**
1. Use same `SwiftAtomics` package from 1.1
2. Replace `OSAtomicAdd64Barrier` with `ManagedAtomic<Int64>`
3. Maintain lock-free SPSC semantics

**Files to Modify:**
- `src/services/audio/rendering/AudioRingBuffer.swift`

**New Types:**
- None (modification only)

---

### 1.3 Add Buffer Bounds Assertion

**Problem:** `frameCount` could theoretically exceed `framesPerBuffer` causing overrun.

**Location:** `src/services/audio/rendering/RenderCallbackContext.swift:348-385`

**Impact:** Edge case safety.

**Approach:**
1. Add precondition assertion in render callback
2. Document the invariant in comments

**Files to Modify:**
- `src/services/audio/rendering/RenderCallbackContext.swift`

---

## Phase 2: Testability & Test Coverage (P1)

**Goal:** Improve test coverage for critical audio pipeline and resolve hidden dependencies.

### 2.1 Create DriverAccessing Protocol

**Problem:** `DriverManager.shared` accessed directly creates hidden singleton dependency, preventing unit testing.

**Location:** `src/store/coordinators/AudioRoutingCoordinator.swift:155-156`

**Impact:** Testing difficulty.

**Approach:**
1. Create `DriverAccessing` protocol in `src/services/driver/protocols/`
2. Extend `DriverManager` to conform
3. Inject protocol dependency in `AudioRoutingCoordinator.init()`
4. Update all call sites

**Files to Modify:**
- `src/services/driver/protocols/DriverAccessing.swift` (new)
- `src/services/driver/DriverManager.swift` - Add conformance
- `src/store/coordinators/AudioRoutingCoordinator.swift` - Inject dependency

**New Types:**
- `DriverAccessing` protocol

---

### 2.2 Create Mock DriverManager

**Problem:** No mock implementation for testing coordinator logic.

**Location:** `tests/mocks/`

**Impact:** Unable to test `AudioRoutingCoordinator` in isolation.

**Approach:**
1. Create `MockDriverManager` implementing `DriverAccessing`
2. Support configurable `isReady`, `deviceID`, `setDeviceName` behavior
3. Track call counts for verification

**Files to Modify:**
- `tests/mocks/MockDriverManager.swift` (new)

**New Types:**
- `MockDriverManager`

---

### 2.3 Add Audio Pipeline Unit Tests

**Problem:** Critical audio path has minimal test coverage.

**Location:** `tests/services/audio/`

**Impact:** Regression risk, hard to refactor confidently.

**Approach:**
1. Add ring buffer edge case tests (underrun, overflow)
2. Add render pipeline format validation tests
3. Add HALIOManager mode configuration tests
4. Test with mock audio objects where possible

**Files to Modify:**
- `tests/services/audio/AudioRingBufferTests.swift` - Expand coverage
- `tests/services/audio/RenderPipelineTests.swift` (new)
- `tests/services/audio/HALIOManagerTests.swift` (new)

**New Types:**
- `RenderPipelineTests`
- `HALIOManagerTests`

---

### 2.4 Fix Silent Failures

**Problem:** Silent failures in EQ configuration and preset loading hide bugs.

**Locations:**
- `src/domain/eq/EQConfiguration.swift:107`
- `src/services/presets/PresetManager.swift:85`

**Impact:** Hidden bugs, difficult debugging.

**Approach:**
1. Add logging to EQConfiguration snapshot loading
2. Add graceful fallback in PresetManager
3. Consider returning `Result` types for error propagation

**Files to Modify:**
- `src/domain/eq/EQConfiguration.swift` - Add logging
- `src/services/presets/PresetManager.swift` - Add fallback

---

## Phase 3: Architecture Refactoring (P1-P2)

**Goal:** Resolve SOLID principle violations and improve maintainability.

### 3.1 Extract DriverNameManager

**Problem:** `AudioRoutingCoordinator` has 740 lines with complex driver naming logic.

**Location:** `src/store/coordinators/AudioRoutingCoordinator.swift:650-739`

**Impact:** Maintainability, SRP violation.

**Approach:**
1. Create `DriverNameManager` class
2. Move driver renaming logic (setDeviceName, refresh pattern)
3. Expose simple API: `func updateDriverName(outputDevice: AudioDevice)`
4. Inject into `AudioRoutingCoordinator`

**Files to Modify:**
- `src/services/audio/DriverNameManager.swift` (new)
- `src/store/coordinators/AudioRoutingCoordinator.swift` - Extract logic

**New Types:**
- `DriverNameManager`

---

### 3.2 Split DeviceManager Interface

**Problem:** `DeviceManager` acts as facade with 25+ methods but thin protocol.

**Location:** `src/services/device/DeviceManager.swift:114-332`

**Impact:** ISP violation.

**Approach:**
1. Create focused protocols:
   - `DeviceEnumerating` - device list queries
   - `DeviceVolumeControlling` - volume get/set
   - `DeviceSampleRateQuerying` - sample rate queries
2. Keep `Enumerating` as composition of all
3. Update injection sites to use focused protocols

**Files to Modify:**
- `src/services/device/protocols/DeviceEnumerating.swift` (new)
- `src/services/device/protocols/DeviceVolumeControlling.swift` (new)
- `src/services/device/protocols/DeviceSampleRateQuerying.swift` (new)
- `src/services/device/DeviceManager.swift` - Implement all protocols

**New Types:**
- `DeviceEnumerating`
- `DeviceVolumeControlling` (already exists as `VolumeControlling`)
- `DeviceSampleRateQuerying` (already exists as `SampleRateObserving`)

---

### 3.3 Refactor EqualiserStore Responsibilities

**Problem:** `EqualiserStore` acts as both coordinator and state container with 571 lines.

**Location:** `src/store/EqualiserStore.swift`

**Impact:** SRP violation.

**Approach:**
1. Identify separable concerns:
   - EQ band control → delegate to existing `EQConfiguration`
   - Snapshot persistence → move to `AppStatePersistence`
   - Device selection delegation → already delegated
2. Ensure store is truly "thin coordinator"
3. Add clear documentation of coordinator pattern

**Files to Modify:**
- `src/store/EqualiserStore.swift` - Simplify
- `src/services/persistence/AppStatePersistence.swift` - Expand responsibility

**New Types:**
- None (refactoring only)

---

### 3.4 Move Meter Processing Off Main Thread

**Problem:** Meter calculations run on main thread at 30 FPS.

**Location:** `src/services/meters/MeterStore.swift:139-143`

**Impact:** UI responsiveness.

**Approach:**
1. Create background processing queue
2. Calculate meter values on background
3. Dispatch results to main thread
4. Keep observer pattern for updates

**Files to Modify:**
- `src/services/meters/MeterStore.swift`

**New Types:**
- None (modification only)

---

## Phase 4: Code Quality Improvements (P2-P3)

**Goal:** Address minor issues and improve code consistency.

### 4.1 Cache View Models

**Problem:** View models recreated on every access.

**Location:** `src/views/main/EQWindowView.swift:11-18`

**Impact:** Minor performance.

**Approach:**
1. Use `@State` for view model storage
2. Lazily create on first access
3. Maintain single instance per view lifecycle

**Files to Modify:**
- `src/views/main/EQWindowView.swift`

---

### 4.2 Replace DispatchQueue with Task

**Problem:** Inconsistent concurrency (mixing GCD and SwiftConcurrency).

**Location:** `src/store/coordinators/AudioRoutingCoordinator.swift:535-538`

**Impact:** Code consistency.

**Approach:**
1. Replace `DispatchQueue.main.asyncAfter` with `Task.sleep`
2. Maintain same semantics
3. Add documentation for delay purpose

**Files to Modify:**
- `src/store/coordinators/AudioRoutingCoordinator.swift`

---

### 4.3 Remove Redundant Change Notifications

**Problem:** Manual `objectWillChange.send()` when `@Published` already notifies.

**Location:** `src/domain/eq/EQConfiguration.swift:229`

**Impact:** Unnecessary work.

**Approach:**
1. Remove manual notification calls
2. Rely on `@Published` automatic notification
3. Test SwiftUI binding still works

**Files to Modify:**
- `src/domain/eq/EQConfiguration.swift`

---

### 4.4 Use Synthesized Codable

**Problem:** Manual Codable implementation could use synthesized conformance.

**Location:** `src/domain/eq/EQBandConfiguration.swift:23-40`

**Impact:** Code reduction.

**Approach:**
1. Remove manual `init(from decoder:)` and `encode(to encoder:)`
2. Rely on synthesized conformance
3. Verify JSON compatibility preserved

**Files to Modify:**
- `src/domain/eq/EQBandConfiguration.swift`

---

### 4.5 Add Preset Import Validation

**Problem:** Malformed JSON could crash or produce invalid state.

**Location:** `src/services/presets/EasyEffectsImporter.swift`

**Impact:** Edge case robustness.

**Approach:**
1. Validate band count within limits
2. Validate frequency within valid range
3. Validate bandwidth within valid range
4. Validate gain within valid range
5. Return descriptive errors

**Files to Modify:**
- `src/services/presets/EasyEffectsImporter.swift`
- `src/domain/eq/EQBandConfiguration.swift` - Add validation methods

---

### 4.6 Extract Audio Constants

**Problem:** Hardcoded values scattered across files.

**Locations:**
- `src/services/audio/rendering/RenderPipeline.swift:65` - Ring buffer size
- `src/services/audio/rendering/RenderCallbackContext.swift` - Frame counts

**Impact:** Organization, maintainability.

**Approach:**
1. Create `AudioConstants.swift` in `src/services/audio/`
2. Move hardcoded values to constants
3. Document purpose of each constant
4. Consider making some configurable

**Files to Modify:**
- `src/services/audio/AudioConstants.swift` (new)
- `src/services/audio/rendering/RenderPipeline.swift`
- `src/services/audio/rendering/RenderCallbackContext.swift`

**New Types:**
- `AudioConstants`

---

## Phase Dependency Graph

```
Phase 1 (Critical)
├── 1.1 Gain Race Condition
├── 1.2 Deprecated Atomics
└── 1.3 Buffer Bounds Assertion
│
Phase 2 (Testability)
├── 2.1 DriverAccessing Protocol ──┐
├── 2.2 Mock DriverManager         │
├── 2.3 Audio Pipeline Tests       │
└── 2.4 Silent Failures            │
                                   │
Phase 3 (Architecture)             │
├── 3.1 DriverNameManager          │
├── 3.2 DeviceManager Split        │
├── 3.3 EqualiserStore Refactor    │
└── 3.4 Meter Processing           │
                                   │
Phase 4 (Code Quality)             │
├── 4.1 Cache View Models          │
├── 4.2 DispatchQueue → Task       │
├── 4.3 Redundant Notifications    │
├── 4.4 Synthesized Codable        │
├── 4.5 Preset Validation          │
└── 4.6 Audio Constants            │
```

---

## Testing Strategy

### After Each Phase

1. Run full test suite: `swift test`
2. Verify build: `swift build -c release`
3. Manual smoke test:
   - Launch app
   - Start/stop routing
   - Switch devices
   - Load/save presets
   - Adjust EQ bands

### Phase 2 Specific Tests

- `XCTAssertTrue(HeadphoneSwitchPolicy.shouldSwitch(...))` - Pure function tests
- `XCTAssertEqual(AudioRingBuffer.write(...), ...)` - Ring buffer edge cases
- Mock injection tests for coordinators

---

## Risk Assessment

| Risk | Phase | Mitigation |
|------|-------|------------|
| Atomic operations change audio latency | 1 | Benchmark before/after |
| Protocol extraction breaks existing code | 2 | Incremental migration |
| Large refactoring causes regressions | 3 | Extract one service at a time |
| Meter threading causes race | 3 | Thorough testing with sanitizers |

---

## Success Criteria

- [ ] All P0 issues resolved
- [ ] Audio pipeline has >80% test coverage
- [ ] No direct singleton dependencies in coordinators
- [ ] Each coordinator has <500 lines
- [ ] All tests pass
- [ ] Build succeeds in release mode
- [ ] Manual QA passes

---

## Notes for Detailed Planning

Each phase will have a detailed implementation plan created before starting:

1. **Step-by-step implementation tasks**
2. **Files to modify** with specific line references
3. **New types to create** with full signatures
4. **Test coverage requirements**
5. **Rollback strategy**

---

*This plan will be refined as each phase is implemented. Detailed plans for each phase will be created separately.*