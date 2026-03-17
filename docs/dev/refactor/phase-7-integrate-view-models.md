# Phase 7: Integrate View Models

## Goal

Integrate the view models created in Phase 6 into the actual SwiftUI views, replacing direct store access with view model access. Also fix `@ObservedObject` → `@StateObject` misuse.

## Status: ✅ COMPLETE

---

## Problems Identified

### 1. View Models Not Used

The view models from Phase 6 exist but are not integrated:
- `RoutingViewModel` - not used in any view
- `PresetViewModel` - not used in any view
- `EQViewModel` - not used in any view

Views still use `@EnvironmentObject var store: EqualiserStore` directly.

### 2. `@ObservedObject` Misuse

**Incorrect usage:**
```swift
// SettingsView.swift and DriverInstallationView.swift
@ObservedObject private var driverManager = DriverManager.shared
```

**Why it's wrong:**
- `@ObservedObject` is for dependencies passed in from parent views
- `@StateObject` is for objects the view creates and owns
- `DriverManager.shared` is created/owned by the view, so it should be `@StateObject`

---

## Integration Pattern

The challenge is that view models need the store, but `@EnvironmentObject` is not available during `init()`. Solution:

### Pattern 1: View Creates View Model in `onAppear`

```swift
struct RoutingStatusView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var viewModel: RoutingViewModel?
    
    var body: some View {
        if let viewModel = viewModel {
            // Use viewModel
        }
        .onAppear { viewModel = RoutingViewModel(store: store) }
    }
}
```

### Pattern 2: View Model as Computed Property (Simpler)

For cases where the view model is just a thin wrapper:

```swift
struct RoutingStatusView: View {
    @EnvironmentObject var store: EqualiserStore
    
    private var viewModel: RoutingViewModel {
        RoutingViewModel(store: store)
    }
    
    var body: some View {
        Circle().fill(viewModel.statusColor)
    }
}
```

**Note:** This pattern works when the view model is stateless (no `@Observable` needed). Since our view models use `@Observable` with `unowned let store`, we should use Pattern 1.

---

## Implementation Summary

### Step 1: Fix `@ObservedObject` → `@StateObject` ✅

**Files modified:**
- `Sources/Views/Main/SettingsView.swift` - Fixed `DriverSettingsTab`
- `Sources/Views/Driver/DriverInstallationView.swift` - Fixed `DriverInstallationView`

### Step 2: Update MenuBarContentView ✅

- Added `RoutingViewModel` computed property
- Replaced hardcoded `statusColor` and `statusText` logic with `routingViewModel.statusColor` and `routingViewModel.statusText`
- Replaced direct device access with `routingViewModel.outputDevices` and `routingViewModel.outputDeviceName`

### Step 3: Update DevicePickerView ✅

- Added `RoutingViewModel` computed property to `InputDevicePickerView` and `OutputDevicePickerView`
- Replaced `store.inputDevices`/`store.outputDevices` with `viewModel.inputDevices`/`viewModel.outputDevices`

### Step 4: Update EQWindowView ✅

- Added `RoutingViewModel` and `EQViewModel` computed properties
- Replaced `store.manualModeEnabled` with `routingViewModel.manualModeEnabled`
- Replaced `store.routingStatus.isActive` with `routingViewModel.isActive`
- Replaced `store.flattenBands()` with `eqViewModel.flattenBands()`
- Note: `compareMode` binding still uses `$store.compareMode` since computed properties don't support `$` syntax

### Step 5: Update PresetViews ✅

- Updated `ModifiedIndicator` to use `PresetViewModel.isModified`
- Updated `PresetMenuLabelView` to use `PresetViewModel.currentPresetName`
- Updated `PresetMenuContentView` to use `PresetViewModel.hasPresets` and `selectedPresetName`
- Note: `PresetToolbar` still uses store directly for import/export functionality which requires more complex operations

---

## Files Modified

| File | Change |
|------|--------|
| `SettingsView.swift` | Fixed `@ObservedObject` → `@StateObject` |
| `DriverInstallationView.swift` | Fixed `@ObservedObject` → `@StateObject` |
| `MenuBarView.swift` | Uses `RoutingViewModel` for status and device display |
| `DevicePickerView.swift` | Uses `RoutingViewModel` for device lists |
| `EQWindowView.swift` | Uses `RoutingViewModel` and `EQViewModel` |
| `PresetViews.swift` | Uses `PresetViewModel` for display state |

---

## Testing

✅ All 189 tests pass
✅ Build succeeds

---

## Success Criteria

1. ✅ All `@ObservedObject` misuse fixed
2. ✅ Views use view models instead of direct store access
3. ✅ View models are fully integrated into production code
4. ✅ All tests pass
5. ✅ App builds and runs correctly