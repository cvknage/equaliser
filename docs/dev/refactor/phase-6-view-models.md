# Phase 6: View Model Layer

## Goal

Add view models to encapsulate view-specific state derivation and presentation logic, achieving proper separation of concerns and enabling SwiftUI Previews with mock data.

---

## Architecture Rationale

### The Problem

Views currently derive presentation state inline:

```swift
// RoutingStatusView.swift - presentation logic IN the view
var statusColor: Color {
    switch store.routingStatus {
    case .idle: return .gray
    case .starting: return .yellow
    case .active: return .green
    case .driverNotInstalled: return .orange
    case .error: return .red
    }
}
```

This violates **Separation of Concerns**:
- `EqualiserStore` handles audio routing (domain logic)
- Views should only render, not derive display state

### The Solution: View Models

```
┌─────────────────────────────────────────────────────────────────┐
│  View Layer (SwiftUI)                                           │
│  - Renders UI components                                         │
│  - Binds to ViewModel properties                                 │
│  - Calls ViewModel actions                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Presentation Layer (ViewModels)                                 │
│  - Derives display state from store                             │
│  - Formats strings for UI                                       │
│  - Exposes actions as methods                                   │
│  - Testable in isolation                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Logic Layer (Coordinators/Managers)                            │
│  - AudioRoutingCoordinator                                       │
│  - DeviceManager                                                 │
│  - PresetManager                                                  │
│  - EQConfiguration                                               │
└─────────────────────────────────────────────────────────────────┘
```

### Benefits

| Benefit | Before (ViewModels) | After (ViewModels) |
|---------|---------------------|---------------------|
| Testability | Need full store + CoreAudio | Test presentation logic in isolation |
| SwiftUI Previews | Need real store | Use mock view models |
| Separation of Concerns | UI logic mixed in views | Clean separation |
| Future flexibility | Hard to add display modes | Easy to add alternative views |

---

## View Models to Create

### 1. RoutingViewModel

**Purpose**: Encapsulate routing status display logic

**File**: `Sources/ViewModels/RoutingViewModel.swift`

**Derived State**:
- `statusColor: Color` - Color for status indicator
- `statusText: String` - Human-readable status text
- `isActive: Bool` - Whether routing is active
- `canStartRouting: Bool` - Whether routing can be started
- `inputDeviceName: String` - Formatted input device name
- `outputDeviceName: String` - Formatted output device name

**Actions**:
- `toggleRouting()` - Start/stop routing
- `selectOutputDevice(uid:)` - Change output device

### 2. PresetViewModel

**Purpose**: Encapsulate preset management UI state

**File**: `Sources/ViewModels/PresetViewModel.swift`

**Derived State**:
- `presetNames: [String]` - Sorted list of preset names
- `currentPresetName: String` - Current preset name or "Custom"
- `isModified: Bool` - Whether current settings differ from saved preset
- `hasPresets: Bool` - Whether any presets exist
- `canSave: Bool` - Whether save action is enabled

**Actions**:
- `selectPreset(named:)` - Load a preset
- `saveAsNew(name:)` - Create new preset
- `updateCurrent()` - Update current preset
- `createNew()` - Create new blank preset

### 3. EQViewModel

**Purpose**: Encapsulate EQ configuration UI state

**File**: `Sources/ViewModels/EQViewModel.swift`

**Derived State**:
- `bandCount: Int` - Number of active bands
- `bands: [EQBandConfiguration]` - Band configurations
- `isBypassed: Bool` - Bypass state
- `compareMode: CompareMode` - Compare mode state
- `inputGain: Float` - Input gain in dB
- `outputGain: Float` - Output gain in dB

**Formatted Display**:
- `formattedFrequency(_:)` - "100 Hz", "1.5 kHz"
- `formattedGain(_:)` - "+6.0 dB", "-3.0 dB"

**Actions**:
- `updateBandGain(index:gain:)`
- `updateBandFrequency(index:frequency:)`
- `updateBandBandwidth(index:bandwidth:)`
- `setBandCount(_:)`
- `flattenBands()`

---

## Implementation Steps

### Step 1: Create ViewModels Directory

```bash
mkdir Sources/ViewModels
```

### Step 2: Create RoutingViewModel

```swift
// Sources/ViewModels/RoutingViewModel.swift
import SwiftUI

@MainActor
@Observable
final class RoutingViewModel {
    private unowned let store: EqualiserStore
    
    init(store: EqualiserStore) {
        self.store = store
    }
    
    // MARK: - Status Display
    
    var statusColor: Color {
        switch store.routingStatus {
        case .idle: return .gray
        case .starting: return .yellow
        case .active: return .green
        case .driverNotInstalled: return .orange
        case .error: return .red
        }
    }
    
    var statusText: String {
        switch store.routingStatus {
        case .idle: return "Idle"
        case .starting: return "Starting..."
        case .active(let input, let output): return "\(input) → \(output)"
        case .driverNotInstalled: return "Driver Not Installed"
        case .error(let message): return "Error: \(message)"
        }
    }
    
    var statusIsActive: Bool {
        if case .active = store.routingStatus { return true }
        return false
    }
    
    // MARK: - Device Names
    
    var inputDeviceName: String {
        guard let uid = store.selectedInputDeviceID else { return "None" }
        return store.inputDevices.first { $0.uid == uid }?.displayName ?? "Unknown"
    }
    
    var outputDeviceName: String {
        guard let uid = store.selectedOutputDeviceID else { return "None" }
        return store.outputDevices.first { $0.uid == uid }?.displayName ?? "Unknown"
    }
    
    // MARK: - Available Devices
    
    var inputDevices: [AudioDevice] {
        store.inputDevices
    }
    
    var outputDevices: [AudioDevice] {
        store.outputDevices
    }
    
    var selectedInputDeviceID: String? {
        store.selectedInputDeviceID
    }
    
    var selectedOutputDeviceID: String? {
        store.selectedOutputDeviceID
    }
    
    // MARK: - Toggle State
    
    var canToggleRouting: Bool {
        if store.manualModeEnabled {
            return store.selectedInputDeviceID != nil 
                && store.selectedOutputDeviceID != nil
        }
        return true // Automatic mode handles device selection
    }
    
    var isRoutingActive: Bool {
        store.routingStatus.isActive
    }
    
    var manualModeEnabled: Bool {
        store.manualModeEnabled
    }
    
    var showDriverPrompt: Bool {
        store.showDriverPrompt
    }
    
    // MARK: - Actions
    
    func toggleRouting() {
        if store.routingStatus.isActive {
            store.stopRouting()
        } else {
            store.reconfigureRouting()
        }
    }
    
    func selectInputDevice(_ uid: String?) {
        store.selectedInputDeviceID = uid
    }
    
    func selectOutputDevice(_ uid: String?) {
        store.selectedOutputDeviceID = uid
    }
    
    func handleDriverInstalled() {
        store.handleDriverInstalled()
    }
    
    func switchToManualMode() {
        store.switchToManualMode()
    }
}
```

### Step 3: Create PresetViewModel

```swift
// Sources/ViewModels/PresetViewModel.swift
import SwiftUI

@MainActor
@Observable
final class PresetViewModel {
    private unowned let store: EqualiserStore
    
    init(store: EqualiserStore) {
        self.store = store
    }
    
    // MARK: - Preset List
    
    var presetNames: [String] {
        store.presetManager.presets
            .map { $0.metadata.name }
            .sorted()
    }
    
    var presets: [Preset] {
        store.presetManager.presets.sorted { $0.metadata.name < $1.metadata.name }
    }
    
    var hasPresets: Bool {
        !store.presetManager.presets.isEmpty
    }
    
    // MARK: - Current Preset
    
    var currentPresetName: String {
        store.presetManager.selectedPresetName ?? "Custom"
    }
    
    var isModified: Bool {
        store.presetManager.isModified
    }
    
    var canUpdateCurrent: Bool {
        store.presetManager.selectedPresetName != nil
    }
    
    var selectedPresetName: String? {
        store.presetManager.selectedPresetName
    }
    
    // MARK: - Bandwidth Display Mode
    
    var bandwidthDisplayMode: BandwidthDisplayMode {
        get { store.bandwidthDisplayMode }
        set { store.bandwidthDisplayMode = newValue }
    }
    
    // MARK: - Actions
    
    func selectPreset(named name: String) {
        store.loadPreset(named: name)
    }
    
    func createNew() {
        store.createNewPreset()
    }
    
    func saveAsNew(name: String) throws {
        try store.saveCurrentAsPreset(named: name)
    }
    
    func updateCurrent() throws {
        try store.updateCurrentPreset()
    }
}
```

### Step 4: Create EQViewModel

```swift
// Sources/ViewModels/EQViewModel.swift
import AVFoundation
import SwiftUI

@MainActor
@Observable
final class EQViewModel {
    private unowned let store: EqualiserStore
    
    init(store: EqualiserStore) {
        self.store = store
    }
    
    // MARK: - Band Configuration
    
    var bandCount: Int {
        store.bandCount
    }
    
    var bands: [EQBandConfiguration] {
        store.eqConfiguration.bands
    }
    
    // MARK: - Gain State
    
    var inputGain: Float {
        get { store.inputGain }
        set { store.updateInputGain(newValue) }
    }
    
    var outputGain: Float {
        get { store.outputGain }
        set { store.updateOutputGain(newValue) }
    }
    
    // MARK: - Bypass State
    
    var isSystemEQEnabled: Bool {
        get { !store.isBypassed }
        set { store.isBypassed = !newValue }
    }
    
    // MARK: - Compare Mode
    
    var compareMode: CompareMode {
        get { store.compareMode }
        set { store.compareMode = newValue }
    }
    
    // MARK: - Formatted Display
    
    func formattedFrequency(_ frequency: Float) -> String {
        if frequency >= 1000 {
            return String(format: "%.1f kHz", frequency / 1000)
        } else {
            return String(format: "%.0f Hz", frequency)
        }
    }
    
    func formattedGain(_ gain: Float) -> String {
        gain >= 0 ? String(format: "+%.1f dB", gain) : String(format: "%.1f dB", gain)
    }
    
    func formatBandwidth(_ bandwidth: Float, mode: BandwidthDisplayMode) -> String {
        switch mode {
        case .octaves:
            return String(format: "%.2f oct", bandwidth)
        case .q:
            let q = BandwidthConverter.bandwidthToQ(bandwidth)
            return String(format: "Q %.2f", q)
        }
    }
    
    // MARK: - Band Actions
    
    func updateBandGain(index: Int, gain: Float) {
        store.updateBandGain(index: index, gain: gain)
    }
    
    func updateBandFrequency(index: Int, frequency: Float) {
        store.updateBandFrequency(index: index, frequency: frequency)
    }
    
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        store.updateBandBandwidth(index: index, bandwidth: bandwidth)
    }
    
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        store.updateBandFilterType(index: index, filterType: filterType)
    }
    
    func updateBandBypass(index: Int, bypass: Bool) {
        store.updateBandBypass(index: index, bypass: bypass)
    }
    
    // MARK: - Global Actions
    
    func setBandCount(_ count: Int) {
        store.updateBandCount(count)
    }
    
    func flattenBands() {
        store.flattenBands()
    }
}
```

### Step 5: Update RoutingStatusView

```swift
// Sources/Views/Device/RoutingStatusView.swift
struct RoutingStatusView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var viewModel: RoutingViewModel?
    
    let status: RoutingStatus
    let isBypassed: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel?.statusColor ?? .gray)
                .frame(width: 8, height: 8)
            
            Text(viewModel?.statusText ?? "Unknown")
                .font(.caption)
                .lineLimit(1)
            
            if isBypassed {
                Text("(bypassed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { viewModel = RoutingViewModel(store: store) }
    }
}
```

### Step 6: Update MenuBarView

```swift
// Sources/Views/Main/MenuBarView.swift
struct MenuBarContentView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var routingViewModel: RoutingViewModel?
    @State private var presetViewModel: PresetViewModel?
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider()
                .padding(.vertical, 12)
            
            controlGroupSection
            
            Divider()
                .padding(.vertical, 12)
            
            actionButtonsSection
        }
        .padding(16)
        .onAppear {
            routingViewModel = RoutingViewModel(store: store)
            presetViewModel = PresetViewModel(store: store)
        }
    }
    
    // Use viewModel?.statusColor instead of computed property
    private var statusColor: Color {
        routingViewModel?.statusColor ?? .gray
    }
    
    private var statusText: String {
        routingViewModel?.statusText ?? "Unknown"
    }
    
    // ... rest of view
}
```

### Step 7: Create Tests

```swift
// Tests/RoutingViewModelTests.swift
@testable import Equaliser
import XCTest
import SwiftUI

@MainActor
final class RoutingViewModelTests: XCTestCase {
    
    func testStatusColor_idle_isGray() {
        let store = EqualiserStore()
        // Store starts in idle state
        let vm = RoutingViewModel(store: store)
        
        XCTAssertEqual(vm.statusColor, .gray)
    }
    
    func testStatusText_idle_returnsIdle() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)
        
        XCTAssertEqual(vm.statusText, "Idle")
    }
    
    func testCanToggleRouting_manualModeWithDevices_returnsTrue() {
        let store = EqualiserStore()
        store.selectedInputDeviceID = "test-input"
        store.selectedOutputDeviceID = "test-output"
        // Need to set manual mode
        let vm = RoutingViewModel(store: store)
        
        XCTAssertTrue(vm.canToggleRouting)
    }
    
    func testSelectedOutputDeviceName_nilDevice_returnsNone() {
        let store = EqualiserStore()
        let vm = RoutingViewModel(store: store)
        
        XCTAssertEqual(vm.outputDeviceName, "None")
    }
}
```

```swift
// Tests/PresetViewModelTests.swift
@testable import Equaliser
import XCTest

@MainActor
final class PresetViewModelTests: XCTestCase {
    
    func testCurrentPresetName_noPreset_returnsCustom() {
        let store = EqualiserStore()
        let vm = PresetViewModel(store: store)
        
        XCTAssertEqual(vm.currentPresetName, "Custom")
    }
    
    func testHasPresets_noPresets_returnsFalse() {
        let store = EqualiserStore()
        let vm = PresetViewModel(store: store)
        
        XCTAssertFalse(vm.hasPresets)
    }
    
    func testIsModified_afterChange_returnsTrue() {
        let store = EqualiserStore()
        let vm = PresetViewModel(store: store)
        
        store.updateBandGain(index: 0, gain: 6.0)
        
        XCTAssertTrue(vm.isModified)
    }
}
```

---

## Files Summary

### New Files

| File | Lines | Purpose |
|------|-------|---------|
| `Sources/ViewModels/RoutingViewModel.swift` | ~120 | Routing status display |
| `Sources/ViewModels/PresetViewModel.swift` | ~80 | Preset UI state |
| `Sources/ViewModels/EQViewModel.swift` | ~100 | EQ band configuration |
| `Tests/RoutingViewModelTests.swift` | ~50 | Routing view model tests |
| `Tests/PresetViewModelTests.swift` | ~40 | Preset view model tests |

### Modified Files

| File | Change |
|------|--------|
| `Sources/Views/Device/RoutingStatusView.swift` | Use RoutingViewModel |
| `Sources/Views/Device/DevicePickerView.swift` | Use RoutingViewModel |
| `Sources/Views/Main/MenuBarView.swift` | Use RoutingViewModel, PresetViewModel |
| `Sources/Views/Presets/PresetViews.swift` | Use PresetViewModel |

---

## Implementation Order

1. Create `Sources/ViewModels/` directory
2. Create `RoutingViewModel.swift`
3. Create `PresetViewModel.swift`
4. Create `EQViewModel.swift`
5. Create `RoutingViewModelTests.swift`
6. Create `PresetViewModelTests.swift`
7. Update `RoutingStatusView` to use view model
8. Update `MenuBarView` to use view models
9. Update `PresetViews` to use view model
10. Run tests and verify

---

## Success Criteria

1. ✅ Presentation logic extracted from views
2. ✅ View models testable in isolation
3. ✅ SwiftUI Previews work with mock view models
4. ✅ All tests pass (170+ tests)
5. ✅ No behavior changes in production code
6. ✅ Views are simpler (less `switch` statements)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Over-abstraction | Low | Medium | View models are thin pass-through |
| Breaking SwiftUI bindings | Low | Medium | Use `@Observable` for reactive updates |
| Performance impact | Very Low | Low | Computed properties are cheap |
| Test complexity | Low | Low | View models test easily with real store |