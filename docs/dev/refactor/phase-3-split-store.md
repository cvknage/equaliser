# Phase 3: Split EqualiserStore

**Risk Level**: Medium  
**Estimated Effort**: 3-4 sessions  
**Prerequisites**: Phase 1 and Phase 2 complete

## Goal

Extract focused coordinators from `EqualiserStore.swift` (1258 lines). The current class is a "God Object" that handles EQ configuration, audio routing, system default monitoring, device changes, compare mode timing, volume sync, sample rate sync, driver integration, and app lifecycle. Each responsibility will be extracted into a dedicated coordinator.

## Current State Analysis

### EqualiserStore Responsibilities (1258 lines)

| Responsibility | Lines | Purpose |
|---------------|-------|---------|
| EQ Configuration | 25-105, 1053-1156 | Computed properties, band updates |
| Preset Management | 1163-1256 | Save/load presets, delegate to PresetManager |
| Audio Routing | 530-811 | Device selection, pipeline management |
| System Default Monitoring | 339-443 | macOS default output changes |
| Device Change Handling | 454-528 | Output device disconnect/reconnect |
| Compare Mode Timer | 1138-1152 | Auto-revert from Flat mode |
| Volume Sync | 905-924 | Driver ↔ output device volume |
| Sample Rate Sync | 851-903 | Match driver to output rate |
| Driver Integration | 592-697, 815-849 | Driver visibility, mode switching |
| App Lifecycle | 446-452, 184-334 | Termination, state restoration |
| UI State | 67-110 | @Published properties for SwiftUI |
| Static Helpers | 932-1015, 1154-1160 | Pure functions |

### Current Dependencies

```
EqualiserStore (1258 lines)
├── DeviceManager (from Phase 1)
├── DriverManager (from Phase 2)
├── EQConfiguration
├── PresetManager
├── MeterStore
├── VolumeManager
├── RenderPipeline
└── AppStatePersistence
```

### Key Insight

EqualiserStore should become a **thin coordinator** that:
1. Owns the child coordinators
2. Owns the @Published properties for SwiftUI
3. Provides computed properties for UI convenience
4. Delegates all complex logic to coordinators

---

## Target Architecture

```
Sources/Core/
├── EqualiserStore.swift          ← Thin coordinator (~300 lines)
├── EQConfiguration.swift         ← Existing (no changes)
├── MeterStore.swift              ← Existing (no changes)
├── RoutingStatus.swift           ← Existing (no changes)
├── Coordinators/
│   ├── AudioRoutingCoordinator.swift   ← NEW: Device selection, pipeline
│   ├── SystemDefaultObserver.swift     ← NEW: macOS default changes
│   ├── DeviceChangeHandler.swift       ← NEW: Disconnect/reconnect
│   ├── CompareModeTimer.swift          ← NEW: Auto-revert timer
│   └── VolumeSyncCoordinator.swift     ← NEW: Volume sync setup
└── AppStateSnapshot.swift         ← Existing (no changes)
```

### New Types

```swift
// AudioRoutingCoordinator.swift
@MainActor
final class AudioRoutingCoordinator: ObservableObject {
    @Published var routingStatus: RoutingStatus = .idle
    @Published var selectedInputDeviceID: String?
    @Published var selectedOutputDeviceID: String?
    @Published var manualModeEnabled: Bool = false
    
    func reconfigureRouting(...)
    func stopRouting()
    func handleDriverInstalled()
    func switchToManualMode()
    func switchToAutomaticMode()
}

// SystemDefaultObserver.swift
@MainActor
final class SystemDefaultObserver {
    func startObserving()
    func stopObserving()
    func getCurrentSystemDefaultOutputUID() -> String?
    func restoreSystemDefaultOutput(to uid: String) -> Bool
}

// DeviceChangeHandler.swift
@MainActor
final class DeviceChangeHandler {
    func handleOutputDevicesChanged()
}

// CompareModeTimer.swift
@MainActor
final class CompareModeTimer {
    func startTimer()
    func cancelTimer()
}

// VolumeSyncCoordinator.swift  
@MainActor
final class VolumeSyncCoordinator {
    func setupVolumeSync(driverID: AudioDeviceID, outputID: AudioDeviceID)
    func tearDown()
    var onBoostGainChanged: ((Float) -> Void)?
}
```

---

## Implementation Steps

### Step 3.1: Create CompareModeTimer

**File**: `Sources/Core/Coordinators/CompareModeTimer.swift`

**Extract from EqualiserStore** (lines 146-147, 1138-1152):
- `compareModeRevertTimer` property
- `compareModeRevertInterval` constant
- `startCompareModeRevertTimer()` method
- `cancelCompareModeRevertTimer()` method

**Content**:
```swift
// CompareModeTimer.swift
// Auto-revert timer for compare mode

import Combine
import Foundation

/// Manages the auto-revert timer for compare mode.
/// When compare mode is set to `.flat`, this timer automatically
/// reverts back to `.eq` after a configurable interval.
@MainActor
final class CompareModeTimer {
    
    // MARK: - Properties
    
    private var timer: AnyCancellable?
    private let interval: TimeInterval
    
    /// Callback invoked when timer fires (should set compareMode to .eq)
    var onRevert: (() -> Void)?
    
    // MARK: - Initialization
    
    init(interval: TimeInterval = 300) { // 5 minutes default
        self.interval = interval
    }
    
    // MARK: - Public Methods
    
    /// Starts the auto-revert timer.
    /// If already running, cancels and restarts.
    func start() {
        cancel()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.onRevert?()
                self?.cancel()
            }
    }
    
    /// Cancels the auto-revert timer.
    func cancel() {
        timer?.cancel()
        timer = nil
    }
}
```

**Changes to EqualiserStore**:
- Add `private let compareModeTimer = CompareModeTimer()`
- In `init()`: `compareModeTimer.onRevert = { [weak self] in self?.compareMode = .eq }`
- In `compareMode.didSet`: Replace timer logic with `compareMode.start()` or `compareModeTimer.cancel()`

---

### Step 3.2: Create VolumeSyncCoordinator

**File**: `Sources/Core/Coordinators/VolumeSyncCoordinator.swift`

**Note**: VolumeManager already exists and is well-designed. This step wraps it for simpler integration.

**Extract from EqualiserStore** (lines 143-144, 905-924):
- `volumeManager` property
- `setupVolumeSync()` method
- Volume boost callback setup

**Content**:
```swift
// VolumeSyncCoordinator.swift
// Coordinates volume sync between driver and output device

import Foundation
import CoreAudio

/// Coordinates volume synchronization between driver and output device.
/// Thin wrapper around VolumeManager for simpler integration.
@MainActor
final class VolumeSyncCoordinator {
    
    // MARK: - Properties
    
    private var volumeManager: VolumeManager?
    private let deviceManager: DeviceManager
    
    /// Callback invoked when boost gain changes.
    var onBoostGainChanged: ((Float) -> Void)? {
        didSet {
            volumeManager?.onBoostGainChanged = onBoostGainChanged
        }
    }
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
    }
    
    // MARK: - Public Methods
    
    /// Sets up volume sync between driver and output device.
    func setup(driverID: AudioDeviceID, outputID: AudioDeviceID) {
        if volumeManager == nil {
            volumeManager = VolumeManager(deviceManager: deviceManager)
            volumeManager?.onBoostGainChanged = onBoostGainChanged
        }
        volumeManager?.setupVolumeSync(driverID: driverID, outputID: outputID)
    }
    
    /// Tears down volume sync.
    func tearDown() {
        volumeManager?.tearDown()
    }
}
```

---

### Step 3.3: Create SystemDefaultObserver

**File**: `Sources/Core/Coordinators/SystemDefaultObserver.swift`

**Extract from EqualiserStore** (lines 305-312, 339-443, 969-1015):
- Notification registration for default output changes
- `handleSystemDefaultOutputChange()` method
- `getCurrentSystemDefaultOutputUID()` method
- `restoreSystemDefaultOutput()` method
- `isAppSettingSystemDefault` flag

**Content**:
```swift
// SystemDefaultObserver.swift
// Observes and manages macOS system default output device

import Foundation
import CoreAudio
import OSLog

/// Observes macOS system default output device changes.
/// Manages the complexity of setting/restoring default output.
@MainActor
final class SystemDefaultObserver {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "SystemDefaultObserver")
    private let deviceManager: DeviceManager
    
    /// Prevents infinite loop when app sets driver as default
    private(set) var isAppSettingSystemDefault = false
    
    /// Callback invoked when system default changes (not caused by app)
    var onSystemDefaultChanged: ((AudioDevice) -> Void)?
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
    }
    
    // MARK: - Lifecycle
    
    /// Starts observing system default output changes.
    func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemDefaultOutputChange),
            name: .systemDefaultOutputDidChange,
            object: nil
        )
    }
    
    /// Stops observing.
    func stopObserving() {
        NotificationCenter.default.removeObserver(self, name: .systemDefaultOutputDidChange, object: nil)
    }
    
    // MARK: - System Default Management
    
    /// Gets the current system default output device UID.
    func getCurrentSystemDefaultOutputUID() -> String? {
        // ... (implementation from EqualiserStore lines 973-1015)
    }
    
    /// Restores the system default output device to the specified UID.
    @discardableResult
    func restoreSystemDefaultOutput(to uid: String) -> Bool {
        // ... (implementation from EqualiserStore lines 1021-1051)
    }
    
    /// Sets driver as system default with loop prevention.
    func setDriverAsDefault(onSuccess: (() -> Void)? = nil, onFailure: (() -> Void)? = nil) {
        isAppSettingSystemDefault = true
        
        guard DriverManager.shared.setAsDefaultOutputDevice() else {
            isAppSettingSystemDefault = false
            onFailure?()
            return
        }
        
        // Clear flag after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAppSettingSystemDefault = false
        }
        
        onSuccess?()
    }
    
    // MARK: - Notification Handler
    
    @objc private func handleSystemDefaultOutputChange() {
        // Ignore if app is setting default
        guard !isAppSettingSystemDefault else {
            logger.debug("App is setting system default, ignoring notification")
            return
        }
        
        // Get the new default
        guard let newDefault = deviceManager.defaultOutputDevice() else {
            logger.warning("No default output device found")
            return
        }
        
        // Ignore if it's our driver
        guard newDefault.uid != DRIVER_DEVICE_UID else {
            logger.debug("New default is our driver, ignoring")
            return
        }
        
        onSystemDefaultChanged?(newDefault)
    }
}
```

---

### Step 3.4: Create DeviceChangeHandler

**File**: `Sources/Core/Coordinators/DeviceChangeHandler.swift`

**Extract from EqualiserStore** (lines 120-124, 298-303, 454-528):
- Output device history management
- `handleOutputDevicesChanged()` method
- Device enumeration observation

**Content**:
```swift
// DeviceChangeHandler.swift
// Handles device connect/disconnect events

import Combine
import Foundation
import OSLog

/// Handles device enumeration changes (connect/disconnect).
/// Manages output device history for automatic reconnection.
@MainActor
final class DeviceChangeHandler: ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceChangeHandler")
    private let deviceManager: DeviceManager
    
    /// Stack of previous output device UIDs (most recent first).
    /// Used to restore output when current device disconnects.
    private var outputDeviceHistory: [String] = []
    
    /// Callback invoked when a replacement device should be selected
    var onSelectReplacementDevice: ((AudioDevice?) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        
        // Observe output device list changes
        deviceManager.$outputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleOutputDevicesChanged()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - History Management
    
    /// Adds a device to history (removes older occurrences first).
    func addToHistory(_ uid: String) {
        outputDeviceHistory.removeAll { $0 == uid }
        outputDeviceHistory.insert(uid, at: 0)
        if outputDeviceHistory.count > 10 {
            outputDeviceHistory.removeLast()
        }
        logger.debug("Added to output history, count: \(self.outputDeviceHistory.count)")
    }
    
    /// Clears history (e.g., when switching to manual mode).
    func clearHistory() {
        outputDeviceHistory.removeAll()
    }
    
    // MARK: - Device Change Handling
    
    private func handleOutputDevicesChanged() {
        // Callback will handle the logic
        // This is just the trigger
    }
    
    /// Finds a replacement device from history or available devices.
    /// - Parameter currentUID: The currently selected device UID (may be disconnected)
    /// - Returns: A replacement device, or nil if none found
    func findReplacementDevice(currentUID: String?) -> AudioDevice? {
        // Check if current device still exists
        if let uid = currentUID,
           deviceManager.outputDevices.contains(where: { $0.uid == uid }) {
            return nil // Current device still valid
        }
        
        // Search history for first available device
        for uid in outputDeviceHistory {
            if let device = deviceManager.device(forUID: uid),
               !device.isVirtual {
                outputDeviceHistory.removeAll { $0 == uid }
                return device
            }
        }
        
        // Fall back to macOS default
        if let newDefault = deviceManager.defaultOutputDevice(),
           newDefault.uid != DRIVER_DEVICE_UID,
           !newDefault.isVirtual {
            return newDefault
        }
        
        // Last resort: first non-virtual output
        return deviceManager.outputDevices.first(where: { !$0.isVirtual })
    }
}
```

---

### Step 3.5: Create AudioRoutingCoordinator

**File**: `Sources/Core/Coordinators/AudioRoutingCoordinator.swift`

This is the largest extraction. **Extract from EqualiserStore** (lines 530-811):
- `reconfigureRouting()` method
- `stopRouting()` method
- `stopPipeline()` method
- `routingStatus` property
- `selectedInputDeviceID`, `selectedOutputDeviceID` properties
- `manualModeEnabled` property
- Device selection logic
- RenderPipeline management
- Sample rate sync coordination

**Content** (abbreviated, see full implementation in plan):
```swift
// AudioRoutingCoordinator.swift
// Coordinates audio routing: device selection and pipeline management

import AVFoundation
import Combine
import Foundation
import OSLog

/// Coordinates audio routing between input and output devices.
/// Manages the RenderPipeline and device selection logic.
@MainActor
final class AudioRoutingCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var routingStatus: RoutingStatus = .idle
    @Published var selectedInputDeviceID: String?
    @Published var selectedOutputDeviceID: String?
    @Published var manualModeEnabled: Bool = false
    
    // MARK: - Dependencies
    
    let deviceManager: DeviceManager
    private let eqConfiguration: EQConfiguration
    private let meterStore: MeterStore
    
    // MARK: - Private Properties
    
    private var renderPipeline: RenderPipeline?
    private var volumeSyncCoordinator: VolumeSyncCoordinator
    private var systemDefaultObserver: SystemDefaultObserver
    private var deviceChangeHandler: DeviceChangeHandler
    
    private var observedOutputDeviceID: AudioDeviceID?
    private var isReconfiguring = false
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AudioRoutingCoordinator")
    
    // MARK: - Initialization
    
    init(
        deviceManager: DeviceManager,
        eqConfiguration: EQConfiguration,
        meterStore: MeterStore,
        volumeSyncCoordinator: VolumeSyncCoordinator,
        systemDefaultObserver: SystemDefaultObserver,
        deviceChangeHandler: DeviceChangeHandler
    ) {
        self.deviceManager = deviceManager
        self.eqConfiguration = eqConfiguration
        self.meterStore = meterStore
        self.volumeSyncCoordinator = volumeSyncCoordinator
        self.systemDefaultObserver = systemDefaultObserver
        self.deviceChangeHandler = deviceChangeHandler
        
        // Wire up callbacks
        systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
            self?.handleSystemDefaultChanged(device)
        }
        
        deviceChangeHandler.onSelectReplacementDevice = { [weak self] device in
            self?.selectReplacementDevice(device)
        }
    }
    
    // MARK: - Public Methods
    
    func reconfigureRouting() {
        // ... (logic from EqualiserStore.reconfigureRouting)
    }
    
    func stopRouting() {
        // ... (logic from EqualiserStore.stopRouting)
    }
    
    func handleDriverInstalled() {
        // ...
    }
    
    func switchToManualMode() {
        manualModeEnabled = true
        deviceChangeHandler.clearHistory()
        // ...
    }
    
    func switchToAutomaticMode() {
        guard DriverManager.shared.isReady else { return }
        manualModeEnabled = false
        reconfigureRouting()
    }
    
    // MARK: - Private Methods
    
    private func stopPipeline() {
        // ...
    }
    
    private func syncDriverSampleRate(to outputDeviceID: AudioDeviceID) {
        // ...
    }
    
    private func setupSampleRateListener(for outputDeviceID: AudioDeviceID) {
        // ...
    }
    
    private func handleSystemDefaultChanged(_ device: AudioDevice) {
        // ...
    }
    
    private func selectReplacementDevice(_ device: AudioDevice?) {
        // ...
    }
}
```

---

### Step 3.6: Refactor EqualiserStore as Thin Coordinator

**File**: `Sources/Core/EqualiserStore.swift`

After extracting the coordinators, EqualiserStore becomes a thin coordinator:

```swift
// EqualiserStore.swift (after refactoring)
// Thin coordinator for EQ application state

import AVFoundation
import Combine
import Foundation
import os.log
import AppKit
import SwiftUI

enum CompareMode: Int, Codable, Sendable {
    case eq = 0
    case flat = 1
}

@MainActor
final class EqualiserStore: ObservableObject {
    
    // MARK: - Computed Properties (delegate to EQConfiguration)
    
    var isBypassed: Bool {
        get { eqConfiguration.globalBypass }
        set {
            eqConfiguration.globalBypass = newValue
            routingCoordinator.updateProcessingMode(systemEQOff: newValue, compareMode: compareMode)
        }
    }
    
    var bandCount: Int {
        get { eqConfiguration.activeBandCount }
        set {
            eqConfiguration.setActiveBandCount(newValue)
            routingCoordinator.reconfigureRouting()
        }
    }
    
    var inputGain: Float {
        get { eqConfiguration.inputGain }
        set {
            let clamped = Self.clampGain(newValue)
            eqConfiguration.inputGain = clamped
            routingCoordinator.updateInputGain(linear: Self.dbToLinear(clamped))
        }
    }
    
    var outputGain: Float {
        get { eqConfiguration.outputGain }
        set {
            let clamped = Self.clampGain(newValue)
            eqConfiguration.outputGain = clamped
            routingCoordinator.updateOutputGain(linear: Self.dbToLinear(clamped))
        }
    }
    
    // MARK: - Published Properties
    
    @Published var compareMode: CompareMode = .eq {
        didSet {
            routingCoordinator.updateProcessingMode(systemEQOff: isBypassed, compareMode: compareMode)
            if compareMode == .flat {
                compareModeTimer.start()
            } else {
                compareModeTimer.cancel()
            }
        }
    }
    
    @Published var bandwidthDisplayMode: BandwidthDisplayMode = .octaves
    @Published var showDriverPrompt: Bool = false
    
    // MARK: - Forwarded Properties from RoutingCoordinator
    
    var routingStatus: RoutingStatus { routingCoordinator.routingStatus }
    var selectedInputDeviceID: String? { routingCoordinator.selectedInputDeviceID }
    var selectedOutputDeviceID: String? { routingCoordinator.selectedOutputDeviceID }
    var manualModeEnabled: Bool { routingCoordinator.manualModeEnabled }
    
    var inputDevices: [AudioDevice] { deviceManager.inputDevices }
    var outputDevices: [AudioDevice] { deviceManager.outputDevices }
    
    // MARK: - Components
    
    let deviceManager = DeviceManager()
    let eqConfiguration: EQConfiguration
    let presetManager: PresetManager
    let meterStore: MeterStore
    
    // MARK: - Coordinators
    
    private(set) var routingCoordinator: AudioRoutingCoordinator
    private let systemDefaultObserver: SystemDefaultObserver
    private let deviceChangeHandler: DeviceChangeHandler
    private let compareModeTimer = CompareModeTimer()
    private let volumeSyncCoordinator: VolumeSyncCoordinator
    
    // MARK: - Private Properties
    
    let persistence: AppStatePersistence
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "EqualiserStore")
    private var cancellables = Set<AnyCancellable>()
    public static let gainRange: ClosedRange<Float> = -36...36
    
    // MARK: - Snapshot
    
    var currentSnapshot: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: eqConfiguration.globalBypass,
            inputGain: eqConfiguration.inputGain,
            outputGain: eqConfiguration.outputGain,
            activeBandCount: eqConfiguration.activeBandCount,
            bands: eqConfiguration.bands,
            inputDeviceID: manualModeEnabled ? routingCoordinator.selectedInputDeviceID : nil,
            outputDeviceID: routingCoordinator.selectedOutputDeviceID,
            bandwidthDisplayMode: bandwidthDisplayMode.rawValue,
            manualModeEnabled: manualModeEnabled,
            metersEnabled: meterStore.metersEnabled
        )
    }
    
    // MARK: - Initialization
    
    init(persistence: AppStatePersistence = AppStatePersistence()) {
        self.persistence = persistence
        self.eqConfiguration = EQConfiguration(from: persistence.load()) ?? EQConfiguration()
        self.presetManager = PresetManager()
        self.meterStore = MeterStore(metersEnabled: persistence.load()?.metersEnabled ?? true)
        
        // Create coordinators
        self.volumeSyncCoordinator = VolumeSyncCoordinator(deviceManager: deviceManager)
        self.systemDefaultObserver = SystemDefaultObserver(deviceManager: deviceManager)
        self.deviceChangeHandler = DeviceChangeHandler(deviceManager: deviceManager)
        self.routingCoordinator = AudioRoutingCoordinator(
            deviceManager: deviceManager,
            eqConfiguration: eqConfiguration,
            meterStore: meterStore,
            volumeSyncCoordinator: volumeSyncCoordinator,
            systemDefaultObserver: systemDefaultObserver,
            deviceChangeHandler: deviceChangeHandler
        )
        
        // Wire up callbacks
        compareModeTimer.onRevert = { [weak self] in
            self?.compareMode = .eq
        }
        
        persistence.setStore(self)
        
        // ... (state restoration logic)
        
        // Start observing system default changes
        systemDefaultObserver.startObserving()
        
        // Wire up EQ configuration changes
        eqConfiguration.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        presetManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Routing Delegation
    
    func reconfigureRouting() {
        routingCoordinator.reconfigureRouting()
    }
    
    func stopRouting() {
        routingCoordinator.stopRouting()
    }
    
    func handleDriverInstalled() {
        routingCoordinator.handleDriverInstalled()
    }
    
    func switchToManualMode() {
        routingCoordinator.switchToManualMode()
    }
    
    func switchToAutomaticMode() {
        routingCoordinator.switchToAutomaticMode()
    }
    
    // MARK: - EQ Control
    
    func updateBandGain(index: Int, gain: Float) {
        eqConfiguration.updateBandGain(index: index, gain: gain)
        routingCoordinator.updateBandGain(index: index)
        presetManager.markAsModified()
    }
    
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        eqConfiguration.updateBandBandwidth(index: index, bandwidth: bandwidth)
        routingCoordinator.updateBandBandwidth(index: index)
        presetManager.markAsModified()
    }
    
    func updateBandFrequency(index: Int, frequency: Float) {
        eqConfiguration.updateBandFrequency(index: index, frequency: frequency)
        routingCoordinator.updateBandFrequency(index: index)
        presetManager.markAsModified()
    }
    
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        eqConfiguration.updateBandFilterType(index: index, filterType: filterType)
        routingCoordinator.updateBandFilterType(index: index)
        presetManager.markAsModified()
    }
    
    func updateBandBypass(index: Int, bypass: Bool) {
        eqConfiguration.updateBandBypass(index: index, bypass: bypass)
        routingCoordinator.updateBandBypass(index: index)
        presetManager.markAsModified()
    }
    
    func updateBandCount(_ count: Int) {
        bandCount = EQConfiguration.clampBandCount(count)
        presetManager.markAsModified()
    }
    
    func updateInputGain(_ gain: Float) {
        inputGain = gain
        presetManager.markAsModified()
    }
    
    func updateOutputGain(_ gain: Float) {
        outputGain = gain
        presetManager.markAsModified()
    }
    
    // MARK: - Preset Management
    
    @discardableResult
    func saveCurrentAsPreset(named name: String) throws -> Preset {
        let preset = try presetManager.createPreset(
            named: name,
            from: eqConfiguration,
            inputGain: inputGain,
            outputGain: outputGain
        )
        presetManager.selectPreset(named: name)
        return preset
    }
    
    func updateCurrentPreset() throws {
        guard let currentName = presetManager.selectedPresetName else { return }
        try saveCurrentAsPreset(named: currentName)
    }
    
    func loadPreset(_ preset: Preset) {
        presetManager.applyPreset(preset, to: eqConfiguration)
        inputGain = preset.settings.inputGain
        outputGain = preset.settings.outputGain
        isBypassed = preset.settings.globalBypass
        bandCount = preset.settings.activeBandCount
        routingCoordinator.reapplyConfiguration()
        presetManager.selectPreset(named: preset.metadata.name)
    }
    
    func loadPreset(named name: String) {
        guard let preset = presetManager.preset(named: name) else {
            logger.warning("Preset not found: \(name)")
            return
        }
        loadPreset(preset)
    }
    
    func flattenBands() {
        for i in 0..<eqConfiguration.activeBandCount {
            eqConfiguration.updateBandGain(index: i, gain: 0)
        }
        inputGain = 0
        outputGain = 0
        isBypassed = false
        routingCoordinator.reapplyConfiguration()
        presetManager.markAsModified()
    }
    
    func createNewPreset() {
        bandCount = 10
        _ = eqConfiguration.setActiveBandCount(10, preserveConfiguredBands: false)
        eqConfiguration.resetBandsWithFrequencySpread()
        inputGain = 0
        outputGain = 0
        isBypassed = false
        routingCoordinator.reapplyConfiguration()
        presetManager.selectPreset(named: nil)
    }
    
    func setEqualiserWindow(_ window: NSWindow?) {
        meterStore.setEqualiserWindow(window)
    }
    
    // MARK: - Static Helpers
    
    static func clampGain(_ gain: Float) -> Float {
        min(max(gain, gainRange.lowerBound), gainRange.upperBound)
    }
    
    private static func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }
}
```

---

## Summary of Changes

| File | Action | Approx Lines |
|------|--------|--------------|
| `CompareModeTimer.swift` | **NEW** | ~50 lines |
| `VolumeSyncCoordinator.swift` | **NEW** | ~60 lines |
| `SystemDefaultObserver.swift` | **NEW** | ~130 lines |
| `DeviceChangeHandler.swift` | **NEW** | ~100 lines |
| `AudioRoutingCoordinator.swift` | **NEW** | ~400 lines |
| `EqualiserStore.swift` | **MODIFY** | ~300 lines (from 1258) |

**Net Result**:
- `EqualiserStore` reduced from 1258 lines to ~300 lines (coordinator)
- Clear separation of concerns
- Each coordinator is testable in isolation
- Backward compatibility via property forwarding

---

## Testing Strategy

### Unit Tests (New)

```swift
// CompareModeTimerTests.swift
func testStart_startsTimer()
func testCancel_cancelsTimer()
func testOnRevert_invokedAfterInterval()

// AudioRoutingCoordinatorTests.swift
func testDetermineAutomaticOutputDevice_preservesCurrent()
func testDetermineAutomaticOutputDevice_usesMacDefault()
func testDetermineAutomaticOutputDevice_usesFallback()
```

### Integration Tests

- Verify routing still works end-to-end
- Verify device changes handled correctly
- Verify sample rate sync works

---

## Rollback Plan

If Phase 3 causes issues:

1. All changes are additive (new files)
2. Revert EqualiserStore.swift to original from git
3. Delete the `Coordinators/` directory
4. No other files were modified

---

## Verification Checklist

- [ ] `swift build` compiles without errors
- [ ] `swift test` passes all tests
- [ ] App launches and shows EQ window
- [ ] Automatic mode routing works
- [ ] Manual mode routing works
- [ ] Device disconnect/reconnect handled
- [ ] Compare mode auto-reverts after 5 minutes
- [ ] Volume sync works
- [ ] Sample rate sync works
- [ ] Presets load/save correctly