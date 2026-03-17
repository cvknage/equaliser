# SOLID/DRY Refactoring Plan

This document outlines a phased approach to refactoring the Equaliser codebase to follow SOLID principles and DRY (Don't Repeat Yourself). Each phase is incremental and should leave the codebase in a working state.

## Executive Summary

The Equaliser codebase has a **"God Object"** problem centred on `EqualiserStore`. This 1258-line class orchestrates virtually all app functionality, violating **Single Responsibility Principle** (SRP). Several supporting classes also have mixed responsibilities. The architecture lacks clear layering between audio, routing, state management, and UI concerns.

---

## Problems Identified

### 1. EqualiserStore — God Object (SRP Violation)

**File**: `Sources/Core/EqualiserStore.swift` (1258 lines)

**Responsibilities mixed together**:
- EQ configuration coordination
- Device routing orchestration
- Audio pipeline lifecycle
- System default output monitoring  
- Compare mode timer management
- Preset coordination delegation
- Volume sync coordination
- Sample rate listener management
- App termination handling
- Driver installation state

**Why it's a problem**:
- Changes to routing logic require touching the same file as preset logic
- Testing requires mocking the entire audio pipeline
- Difficult to understand the full flow
- High risk of merge conflicts

### 2. DeviceManager — Mixed Concerns (SRP Violation)

**File**: `Sources/Device/DeviceManager.swift` (987 lines)

**Responsibilities mixed together**:
- Device enumeration
- Volume control (virtual master, channel, device-level)
- Mute control
- Sample rate observation
- System notifications

### 3. DriverManager — Properties vs Lifecycle (SRP/ISP Violation)

**File**: `Sources/Driver/DriverManager.swift` (703 lines)

**Responsibilities mixed**:
- Driver installation/uninstallation
- Device name property
- Sample rate property
- Default device toggle
- Version checking

### 4. RenderPipeline — Static Callbacks (Testability Issue)

**File**: `Sources/Audio/Rendering/RenderPipeline.swift` (606 lines)

**Problem**: Static callback functions make unit testing difficult. All audio callbacks are static methods that cannot be mocked.

### 5. Meter Calculations Duplicated (DRY Violation)

**Files**:
- `Sources/Core/MeterStore.swift` (402 lines)
- `Sources/Audio/Rendering/RenderCallbackContext.swift` (422 lines)

**Problem**: Meter normalisation, peak hold, RMS calculations could be centralised.

### 6. Persistence Scattered

**File**: `Sources/App/AppStateSnapshot.swift`

**Problem**: Persistence logic is spread between `AppStateSnapshot`, `AppStatePersistence`, and embedded in `EqualiserStore`'s `currentSnapshot` computed property.

### 7. No Protocol Abstractions (DIP Violation)

**Problem**: No protocols define the interfaces between components. Views bind directly to concrete `EqualiserStore` rather than abstractions.

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         View Layer                               │
│   Views observe ViewModels, not the Store directly               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                     Coordinator Layer                            │
│   AudioRoutingCoordinator, PresetCoordinator, VolumeCoordinator │
│   Each coordinates ONE domain                                     │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                       Service Layer                              │
│   DeviceService, DriverService, AudioPipeline, MeterService      │
│   Each service is focused on ONE capability                      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                        Core Layer                                │
│   EQConfiguration, AudioDevice, Preset (pure domain models)      │
└─────────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **Single Responsibility**: Each type does ONE thing
2. **Dependency Inversion**: Depend on abstractions (protocols), not concretions
3. **Open/Closed**: New features add types, don't modify existing ones
4. **Interface Segregation**: Clients depend only on interfaces they use
5. **DRY**: Shared logic extracted to focused utilities

---

## Files to Modify

### Phase 1 — Extract Device Services (Low Risk)

| Current File | New File | Responsibility |
|--------------|----------|----------------|
| `DeviceManager.swift` | `DeviceEnumerator.swift` | Device enumeration, cached lists |
| `DeviceManager.swift` | `DeviceVolumeService.swift` | Volume/mute control |
| `DeviceManager.swift` | `DeviceSampleRateService.swift` | Sample rate observation |
| `DeviceManager.swift` | `AudioDevice+Extensions.swift` | Transport type helpers |

**Risk**: Low — DeviceManager has clear boundaries between its responsibilities.

### Phase 2 — Extract Driver Services (Low Risk)

| Current File | New File | Responsibility |
|--------------|----------|----------------|
| `DriverManager.swift` | `DriverLifecycleService.swift` | Install/uninstall |
| `DriverManager.swift` | `DriverPropertyService.swift` | Name, sample rate |
| `DriverManager.swift` | `DriverDeviceRegistry.swift` | Device ID lookup |

**Risk**: Low — DriverManager is already moderately separated.

### Phase 3 — Split EqualiserStore (Medium Risk)

| Current File | New File | Responsibility |
|--------------|----------|----------------|
| `EqualiserStore.swift` | `AudioRoutingCoordinator.swift` | Pipeline start/stop, device selection |
| `EqualiserStore.swift` | `SystemDefaultObserver.swift` | macOS default output changes |
| `EqualiserStore.swift` | `CompareModeTimer.swift` | Auto-revert timer |
| `EqualiserStore.swift` | `VolumeSyncService.swift` | Driver ↔ output device volume sync |
| `EqualiserStore.swift` | `EQCoordinator.swift` | Slimmed store — just EQ state |

**Risk**: Medium — EqualiserStore is the core of the app. Requires careful extraction.

### Phase 4 — Extract Meter Services (Low Risk)

| Current File | New File | Responsibility |
|--------------|----------|----------------|
| `MeterStore.swift` | `MeterCalculationService.swift` | Peak/RMS calculation logic |
| `RenderCallbackContext.swift` | (uses) | MeterCalculationService for dB conversion |

**Risk**: Low — Meter logic is isolated.

### Phase 5 — Protocol Abstractions (Medium Risk)

| New File | Purpose |
|----------|---------|
| `Protocols/DeviceEnumerating.swift` | Protocol for device enumeration |
| `Protocols/VolumeControlling.swift` | Protocol for volume control |
| `Protocols/RoutingCoordinating.swift` | Protocol for audio routing |
| `Protocols/PresetManaging.swift` | Protocol for preset operations |

**Risk**: Medium — Requires updating all consumers.

### Phase 6 — View Model Layer (Medium Risk)

| New File | Purpose |
|----------|---------|
| `ViewModels/EQViewModel.swift` | UI state for EQ window |
| `ViewModels/RoutingViewModel.swift` | UI state for routing status |
| `ViewModels/PresetViewModel.swift` | UI state for presets |

**Risk**: Medium — Views change from direct store binding to view model binding.

---

## New Types or Modules

### Core Domain Models (No Changes Required)

These are already well-designed:
- `AudioDevice` (struct)
- `EQBandConfiguration` (struct)
- `EQConfiguration` (class, but storage-free)
- `Preset` (struct)

### New Service Types

```
Sources/
├── Audio/
│   ├── Services/
│   │   ├── AudioRoutingCoordinator.swift    ← Orchestrates pipeline lifecycle
│   │   ├── SystemDefaultObserver.swift      ← macOS default output listener
│   │   ├── CompareModeTimer.swift           ← Auto-revert timer
│   │   └── VolumeSyncService.swift          ← Volume sync, uses VolumeManager
│   ├── Device/
│   │   ├── DeviceEnumerator.swift          ← Device listing
│   │   ├── DeviceVolumeService.swift       ← Volume/mute control
│   │   └── DeviceSampleRateService.swift   ← Sample rate observation
│   └── Driver/
│       ├── DriverLifecycleService.swift    ← Install/uninstall
│       └── DriverPropertyService.swift      ← Name, rate, visibility
├── Core/
│   ├── EqualiserStore.swift                ← Slimmed to just EQ state coordination
│   └── Protocols/
│       ├── DeviceEnumerating.swift
│       ├── VolumeControlling.swift
│       └── RoutingCoordinating.swift
└── ViewModels/
    ├── EQViewModel.swift
    ├── RoutingViewModel.swift
    └── PresetViewModel.swift
```

---

## Risk Assessment

| Phase | Risk Level | Reason |
|-------|------------|--------|
| Phase 1 | Low | Device services have clear boundaries |
| Phase 2 | Low | DriverManager is already compartmentalised |
| Phase 3 | **Medium** | EqualiserStore is central; changes affect everything |
| Phase 4 | Low | Meter logic is isolated |
| Phase 5 | Medium | Protocols touch all layers |
| Phase 6 | Medium | View layer changes are visible to users |

---

## Phase Details

Each phase will have its own detailed plan document linked below:

- [x] [Phase 1: Extract Device Services](./docs/refactor/phase-1-device-services.md) — **Complete**
- [x] [Phase 2: Extract Driver Services](./docs/refactor/phase-2-driver-services.md) — **Complete**
- [x] [Phase 3: Split EqualiserStore](./docs/refactor/phase-3-split-store.md) — **Complete**
- [x] [Phase 4: Extract Meter Services](./docs/refactor/phase-4-meter-services.md) — **Complete**
- [x] [Phase 5: Protocol Abstractions](./docs/refactor/phase-5-protocols.md) — **Complete**
- [x] [Phase 6: View Model Layer](./docs/refactor/phase-6-view-models.md) — **Complete**

---

## Testing Strategy

### Phase 1-2: Service Extraction
- Run existing tests after each step
- Add unit tests for new service types
- Integration tests remain unchanged

### Phase 3: EqualiserStore Split
- Create test doubles for routing
- Test coordinator independently
- Verify compare mode timer works
- Test system default observer

### Phase 5: Protocols
- Create mock implementations for testing
- Verify all consumers work with mocks

### Phase 6: View Models
- Snapshot tests for UI
- Verify bindings work correctly

---

## Deferred Improvements

These are **not** included in this plan but could be addressed later:

1. **RenderPipeline static callbacks** — Would require significant re-architecture of audio thread handling
2. **Persistence layer consolidation** — Currently works; low priority
3. **SwiftUI optimisation** — Could use `@StateObject` more consistently
4. **Combine to Async/await** — Could modernise reactive streams for newer code

---

## Progress Tracking

| Phase | Status | Started | Completed |
|-------|--------|---------|-----------|
| Phase 1: Device Services | ✅ Complete | 2026-03-16 | 2026-03-16 |
| Phase 2: Driver Services | ✅ Complete | 2026-03-16 | 2026-03-16 |
| Phase 3: Split Store | ✅ Complete | 2026-03-16 | 2026-03-16 |
| Phase 4: Meter Services | ✅ Complete | 2026-03-16 | 2026-03-16 |
| Phase 5: Protocols | ✅ Complete | 2026-03-16 | 2026-03-16 |
| Phase 6: View Models | ✅ Complete | 2026-03-16 | 2026-03-16 |
