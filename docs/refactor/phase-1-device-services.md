# Phase 1: Extract Device Services

**Risk Level**: Low  
**Estimated Effort**: 2-3 sessions  
**Prerequisites**: None

## Goal

Extract focused, single-responsibility services from `DeviceManager.swift` (987 lines). The current class mixes device enumeration, volume control, mute control, and sample rate observation. Each responsibility will become a separate service.

## Current State Analysis

### DeviceManager Responsibilities (987 lines)

| Responsibility | Lines | Purpose |
|---------------|-------|---------|
| Device Enumeration | 1-367 | List input/output devices, find by UID |
| Volume Control | 562-824 | Get/set volume, observe changes |
| Mute Control | 622-696, 795-824 | Get/set mute, observe changes |
| Sample Rate | 461-559 | Get/observe sample rates |
| Default Device | 369-438, 406-430 | Get system default output |

### Consumers

1. **EqualiserStore** — primary consumer
   - Device enumeration (input/output lists)
   - Device lookup by UID
   - Sample rate observation
   - Fallback device selection

2. **VolumeManager** — volume sync
   - Get/set device volume
   - Get/set device mute
   - Observe volume/mute changes

3. **Tests** — DeviceManagerTests.swift
   - Tests `shouldIncludeDevice(name:)`
   - Tests `AudioDevice.isVirtual`
   - Tests `AudioDevice.isAggregate`
   - Tests `selectFallbackOutputDevice(from:)`

## Target Architecture

```
Sources/Device/
├── AudioDevice.swift              ← Existing struct (no changes)
├── DeviceConstants.swift          ← Existing constants (no changes)
├── DeviceManager.swift            ← Facade composing services
├── DeviceEnumerator.swift         ← NEW: Device enumeration
├── DeviceVolumeService.swift      ← NEW: Volume/mute control
└── DeviceSampleRateService.swift  ← NEW: Sample rate observation
```

### Service Interfaces

```swift
// DeviceEnumerator.swift
protocol DeviceEnumerating {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func refreshDevices()
    func device(forUID uid: String) -> AudioDevice?
    func deviceID(forUID uid: String) -> AudioDeviceID?
    func findDeviceByUID(_ uid: String) -> AudioDevice?
    func defaultOutputDevice() -> AudioDevice?
    func findEqualiserDriverDevice() -> AudioDevice?
    static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice?
}

// DeviceVolumeService.swift
protocol VolumeControlling {
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float?
    func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
    func getMute(deviceID: AudioDeviceID) -> Bool?
    func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void)
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID)
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void)
    func stopObservingMuteChanges(on deviceID: AudioDeviceID)
}

// DeviceSampleRateService.swift
protocol SampleRateObserving {
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64?
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64?
    func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void)
    func stopObservingSampleRateChanges(on deviceID: AudioDeviceID)
}
```

### Facade Pattern

`DeviceManager` will remain as a facade that composes the services:

```swift
@MainActor
final class DeviceManager: ObservableObject {
    let enumerator: DeviceEnumerating
    let volume: VolumeControlling
    let sampleRate: SampleRateObserving
    
    // Convenience pass-throughs for backward compatibility
    var inputDevices: [AudioDevice] { enumerator.inputDevices }
    var outputDevices: [AudioDevice] { enumerator.outputDevices }
    // ... etc
}
```

---

## Implementation Steps

### Step 1.1: Create CoreAudio Helpers

**File**: `Sources/Device/CoreAudioHelpers.swift`

Extract shared CoreAudio property access helpers used across services.

**Extract from**:
- `DeviceManager.fetchStringProperty(id:selector:)` (lines 257-277)
- `DeviceManager.fetchTransportType(id:)` (lines 240-255)
- `DeviceManager.hasStreams(id:scope:)` (lines 279-290)
- CoreAudio constants (lines 7-14)

**Content**:
```swift
// CoreAudioHelpers.swift
// Shared CoreAudio property access utilities

import Foundation
import CoreAudio

// MARK: - CoreAudio Constants
// These are defined in CoreAudio headers but not directly accessible in Swift

/// Virtual master volume property selector
let kAudioHardwareServiceDeviceProperty_VirtualMasterVolume: AudioObjectPropertySelector = 0x00006d76  // 'mvmt'

/// Virtual master mute property selector  
let kAudioHardwareServiceDeviceProperty_VirtualMasterMute: AudioObjectPropertySelector = 0x00006d6d  // 'mdmt'

/// Owned objects property selector
let kAudioDevicePropertyOwnedObjects: AudioObjectPropertySelector = 0x6f6f776e  // 'oown'

/// Device volume scalar property selector
let kAudioDevicePropertyVolumeScalar: AudioObjectPropertySelector = 0x766F6C6D  // 'volm'

/// Device mute property selector
let kAudioDevicePropertyMute: AudioObjectPropertySelector = 0x6D757465  // 'mute'

/// Virtual device transport type
let kAudioDeviceTransportTypeVirtual: UInt32 = 0x76697274  // 'virt'

/// Aggregate device transport type
let kAudioDeviceTransportTypeAggregate: UInt32 = 0x61676720  // 'agg '

// MARK: - String Property Helpers

/// Fetches a string property from a CoreAudio device.
/// - Parameters:
///   - id: The device ID
///   - selector: The property selector
/// - Returns: The string value, or nil if not found
func fetchStringProperty(id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr else {
        return nil
    }
    
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }
    
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, buffer) == noErr else {
        return nil
    }
    
    let unmanaged = buffer.bindMemory(to: Unmanaged<CFString>.self, capacity: 1)
    return unmanaged.pointee.takeRetainedValue() as String
}

/// Fetches the transport type for a device.
/// - Parameter id: The device ID
/// - Returns: The transport type, or 0 if unavailable
func fetchTransportType(id: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var transportType: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transportType) == noErr else {
        return 0
    }
    
    return transportType
}

/// Checks if a device has streams for a given scope.
/// - Parameters:
///   - id: The device ID
///   - scope: The scope (input or output)
/// - Returns: True if the device has streams
func hasStreams(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var propertySize: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &propertySize) == noErr && propertySize > 0
}
```

**Verification**: Build should succeed. No functional changes.

---

### Step 1.2: Create DeviceEnumerator Service

**File**: `Sources/Device/DeviceEnumerator.swift`

**Extract from DeviceManager** (lines 48-467 excluding volume/mute/sample-rate):
- Device lists (`inputDevices`, `outputDevices`)
- `refreshDevices()`
- `makeDevice(from:)`
- `shouldIncludeDevice(name:)`
- `findDeviceByUID(_:)`
- `device(forUID:)`, `deviceID(forUID:)`
- `findEqualiserDriverDevice()`, `findBlackHoleDevice()`
- `bestInputDeviceForEQ()`
- `defaultOutputDevice()`, `currentSystemDefaultOutputDevice()`
- `selectFallbackOutputDevice(from:)` (static)
- Notification listeners (device change, driver install)

**Content**:
```swift
// DeviceEnumerator.swift
// Device enumeration and discovery service

import Foundation
import CoreAudio
import os.log

/// Device enumeration service.
/// Provides cached lists of audio input/output devices and device lookup.
@MainActor
final class DeviceEnumerator: ObservableObject, DeviceEnumerating {
    
    // MARK: - Published Properties
    
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private let listenerBlockQueue = DispatchQueue(label: "net.knage.equaliser.DeviceEnumerator.listener")
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceEnumerator")
    
    // MARK: - Initialization
    
    init() {
        refreshDevices()
        setupDeviceChangeListener()
        setupDefaultOutputListener()
        setupDriverInstallNotification()
    }
    
    deinit {
        cleanupListener()
    }
    
    // MARK: - Listener Setup
    
    // ... (copy listener setup methods from DeviceManager)
    
    // MARK: - Device Enumeration
    
    func refreshDevices() {
        // ... (copy from DeviceManager.refreshDevices())
    }
    
    private func makeDevice(from id: AudioDeviceID) -> AudioDevice? {
        // ... (copy from DeviceManager, using helper functions)
    }
    
    func shouldIncludeDevice(name: String) -> Bool {
        !name.hasPrefix("CADefaultDeviceAggregate")
    }
    
    // MARK: - Device Lookup
    
    func findDeviceByUID(_ uid: String) -> AudioDevice? {
        // ... (copy implementation)
    }
    
    func device(forUID uid: String) -> AudioDevice? {
        // ... (copy implementation)
    }
    
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        // ... (copy implementation)
    }
    
    // MARK: - Special Device Discovery
    
    func findEqualiserDriverDevice() -> AudioDevice? {
        // ... (copy implementation)
    }
    
    func findBlackHoleDevice() -> AudioDevice? {
        inputDevices.first { $0.name.contains("BlackHole") }
    }
    
    func bestInputDeviceForEQ() -> AudioDevice? {
        // ... (copy implementation)
    }
    
    // MARK: - Default Device
    
    func defaultOutputDevice() -> AudioDevice? {
        // ... (copy implementation)
    }
    
    func currentSystemDefaultOutputDevice() -> AudioDevice? {
        defaultOutputDevice()
    }
    
    // MARK: - Static Helpers
    
    public static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice? {
        // ... (copy implementation)
    }
    
    // MARK: - Cleanup
    
    nonisolated func cleanupListener() {
        // ... (copy implementation)
    }
}
```

**Define Protocol**:
```swift
// DeviceEnumerating.swift (in Sources/Device/Protocols/)
protocol DeviceEnumerating: ObservableObject {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    func refreshDevices()
    func device(forUID uid: String) -> AudioDevice?
    func deviceID(forUID uid: String) -> AudioDeviceID?
    func findDeviceByUID(_ uid: String) -> AudioDevice?
    func defaultOutputDevice() -> AudioDevice?
    func findEqualiserDriverDevice() -> AudioDevice?
    static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice?
}
```

**Verification**: 
- Build should succeed
- All tests pass
- `DeviceEnumerator` compiles with same functionality as extracted methods

---

### Step 1.3: Create DeviceVolumeService

**File**: `Sources/Device/DeviceVolumeService.swift`

**Extract from DeviceManager** (lines 562-824):
- `getVirtualMasterVolume(deviceID:)`
- `setVirtualMasterVolume(deviceID:volume:)`
- `getDeviceVolumeScalar(deviceID:)`
- `setDeviceVolumeScalar(deviceID:volume:)`
- `getMute(deviceID:)`
- `setDeviceMute(deviceID:muted:)`
- `observeDeviceVolumeChanges(deviceID:handler:)`
- `stopObservingDeviceVolumeChanges(deviceID:)`
- `observeMuteChanges(on:handler:)`
- `stopObservingMuteChanges(on:)`
- Private helper methods for control objects

**Content**:
```swift
// DeviceVolumeService.swift
// Volume and mute control service for audio devices

import Foundation
import CoreAudio
import os.log

/// Volume and mute control for audio devices.
/// Handles both virtual master volume and device-level volume/mute.
@MainActor
final class DeviceVolumeService: VolumeControlling {
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var volumeListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private nonisolated(unsafe) var muteListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private let listenerQueue = DispatchQueue(label: "net.knage.equaliser.DeviceVolumeService.listener")
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceVolumeService")
    
    // MARK: - Virtual Master Volume
    
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float? {
        // ... (copy implementation)
    }
    
    @discardableResult
    func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool {
        // ... (copy implementation)
    }
    
    // MARK: - Device-Level Volume
    
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        // ... (copy implementation)
    }
    
    @discardableResult
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
        // ... (copy implementation)
    }
    
    // MARK: - Mute Control
    
    func getMute(deviceID: AudioDeviceID) -> Bool? {
        // ... (copy implementation)
    }
    
    @discardableResult
    func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        // ... (copy implementation)
    }
    
    // MARK: - Volume Observation
    
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void) {
        // ... (copy implementation)
    }
    
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID) {
        // ... (copy implementation)
    }
    
    // MARK: - Mute Observation
    
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void) {
        // ... (copy implementation)
    }
    
    func stopObservingMuteChanges(on deviceID: AudioDeviceID) {
        // ... (copy implementation)
    }
    
    // MARK: - Private Helpers
    
    private func getVolumeFromControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        // ... (copy implementation)
    }
    
    private func getVolumeFromControl(controlID: AudioObjectID) -> Float? {
        // ... (copy implementation)
    }
    
    private func setVolumeOnControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, volume: Float) -> Bool {
        // ... (copy implementation)
    }
    
    private func setVolumeOnControl(controlID: AudioObjectID, volume: Float) -> Bool {
        // ... (copy implementation)
    }
    
    private func getMuteFromControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool? {
        // ... (copy implementation)
    }
    
    private func getMuteFromControl(controlID: AudioObjectID) -> Bool? {
        // ... (copy implementation)
    }
}
```

**Define Protocol**:
```swift
// VolumeControlling.swift (in Sources/Device/Protocols/)
protocol VolumeControlling {
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float?
    @discardableResult func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?
    @discardableResult func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool
    func getMute(deviceID: AudioDeviceID) -> Bool?
    @discardableResult func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void)
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID)
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void)
    func stopObservingMuteChanges(on deviceID: AudioDeviceID)
}
```

**Verification**:
- Build should succeed
- VolumeManager continues to work unchanged (via DeviceManager facade)

---

### Step 1.4: Create DeviceSampleRateService

**File**: `Sources/Device/DeviceSampleRateService.swift`

**Extract from DeviceManager** (lines 461-559):
- `getActualSampleRate(deviceID:)`
- `getNominalSampleRate(deviceID:)`
- `observeSampleRateChanges(on:handler:)`
- `stopObservingSampleRateChanges(on:)`
- Private `sampleRateListenerBlocks` storage

**Content**:
```swift
// DeviceSampleRateService.swift
// Sample rate query and observation service

import Foundation
import CoreAudio
import os.log

/// Sample rate query and observation for audio devices.
@MainActor
final class DeviceSampleRateService: SampleRateObserving {
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var sampleRateListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private let listenerQueue = DispatchQueue(label: "net.knage.equaliser.DeviceSampleRateService.listener")
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceSampleRateService")
    
    // MARK: - Sample Rate Queries
    
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyActualSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr else {
            return nil
        }
        
        return rate
    }
    
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr else {
            return nil
        }
        
        return rate
    }
    
    // MARK: - Sample Rate Observation
    
    func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            if let rate = self.getNominalSampleRate(deviceID: deviceID) {
                Task { @MainActor in
                    handler(rate)
                }
            }
        }
        
        sampleRateListenerBlocks[deviceID] = block
        
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            listenerQueue,
            block
        )
        
        if status != noErr {
            logger.warning("Failed to observe sample rate changes on device \(deviceID): \(status)")
        }
    }
    
    func stopObservingSampleRateChanges(on deviceID: AudioDeviceID) {
        guard let block = sampleRateListenerBlocks.removeValue(forKey: deviceID) else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &address,
            listenerQueue,
            block
        )
    }
}
```

**Define Protocol**:
```swift
// SampleRateObserving.swift (in Sources/Device/Protocols/)
protocol SampleRateObserving {
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64?
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64?
    func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void)
    func stopObservingSampleRateChanges(on deviceID: AudioDeviceID)
}
```

**Verification**:
- Build should succeed
- All tests pass

---

### Step 1.5: Convert DeviceManager to Facade

**File**: `Sources/Device/DeviceManager.swift`

Transform DeviceManager into a facade that composes the three services while maintaining backward compatibility.

**Changes**:
1. Remove all implementation code (moved to services)
2. Add service properties
3. Add convenience pass-through methods
4. Keep `AudioDevice` struct in place

**Final DeviceManager**:
```swift
// DeviceManager.swift
// Facade for device services - maintains backward compatibility

import Foundation
import CoreAudio
import os.log

// MARK: - Notification Extension
extension Notification.Name {
    static let systemDefaultOutputDidChange = Notification.Name("net.knage.equaliser.systemDefaultOutputDidChange")
}

// MARK: - Device Manager Facade

/// Facade for device-related services.
/// Maintains backward compatibility while delegating to specialised services.
@MainActor
final class DeviceManager: ObservableObject {
    
    // MARK: - Services
    
    /// Device enumeration service
    let enumerator: DeviceEnumerating
    
    /// Volume and mute control service
    let volume: VolumeControlling
    
    /// Sample rate service
    let sampleRate: SampleRateObserving
    
    // MARK: - Convenience Properties (backward compatibility)
    
    var inputDevices: [AudioDevice] { enumerator.inputDevices }
    var outputDevices: [AudioDevice] { enumerator.outputDevices }
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceManager")
    
    // MARK: - Initialization
    
    init(
        enumerator: DeviceEnumerating? = nil,
        volume: VolumeControlling? = nil,
        sampleRate: SampleRateObserving? = nil
    ) {
        self.enumerator = enumerator ?? DeviceEnumerator()
        self.volume = volume ?? DeviceVolumeService()
        self.sampleRate = sampleRate ?? DeviceSampleRateService()
    }
    
    // MARK: - Device Enumeration (pass-through)
    
    func refreshDevices() {
        (enumerator as? DeviceEnumerator)?.refreshDevices()
    }
    
    func shouldIncludeDevice(name: String) -> Bool {
        (enumerator as? DeviceEnumerator)?.shouldIncludeDevice(name: name) ?? true
    }
    
    func findDeviceByUID(_ uid: String) -> AudioDevice? {
        enumerator.findDeviceByUID(uid)
    }
    
    func device(forUID uid: String) -> AudioDevice? {
        enumerator.device(forUID: uid)
    }
    
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        enumerator.deviceID(forUID: uid)
    }
    
    func findEqualiserDriverDevice() -> AudioDevice? {
        enumerator.findEqualiserDriverDevice()
    }
    
    func findBlackHoleDevice() -> AudioDevice? {
        (enumerator as? DeviceEnumerator)?.findBlackHoleDevice()
    }
    
    func bestInputDeviceForEQ() -> AudioDevice? {
        (enumerator as? DeviceEnumerator)?.bestInputDeviceForEQ()
    }
    
    func defaultOutputDevice() -> AudioDevice? {
        enumerator.defaultOutputDevice()
    }
    
    func currentSystemDefaultOutputDevice() -> AudioDevice? {
        enumerator.currentSystemDefaultOutputDevice()
    }
    
    static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice? {
        DeviceEnumerator.selectFallbackOutputDevice(from: devices)
    }
    
    // MARK: - Volume Control (pass-through)
    
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float? {
        volume.getVirtualMasterVolume(deviceID: deviceID)
    }
    
    @discardableResult
    func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool {
        self.volume.setVirtualMasterVolume(deviceID: deviceID, volume: volume)
    }
    
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        volume.getDeviceVolumeScalar(deviceID: deviceID)
    }
    
    @discardableResult
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
        self.volume.setDeviceVolumeScalar(deviceID: deviceID, volume: volume)
    }
    
    func getMute(deviceID: AudioDeviceID) -> Bool? {
        volume.getMute(deviceID: deviceID)
    }
    
    @discardableResult
    func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        volume.setDeviceMute(deviceID: deviceID, muted: muted)
    }
    
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void) {
        volume.observeDeviceVolumeChanges(deviceID: deviceID, handler: handler)
    }
    
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID) {
        volume.stopObservingDeviceVolumeChanges(deviceID: deviceID)
    }
    
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void) {
        volume.observeMuteChanges(on: deviceID, handler: handler)
    }
    
    func stopObservingMuteChanges(on deviceID: AudioDeviceID) {
        volume.stopObservingMuteChanges(on: deviceID)
    }
    
    // MARK: - Sample Rate (pass-through)
    
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64? {
        sampleRate.getActualSampleRate(deviceID: deviceID)
    }
    
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64? {
        sampleRate.getNominalSampleRate(deviceID: deviceID)
    }
    
    func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void) {
        sampleRate.observeSampleRateChanges(on: deviceID, handler: handler)
    }
    
    func stopObservingSampleRateChanges(on deviceID: AudioDeviceID) {
        sampleRate.stopObservingSampleRateChanges(on: deviceID)
    }
}
```

**Verification**:
- Build should succeed
- All existing code using `DeviceManager` continues to work unchanged
- No changes required to `EqualiserStore` or `VolumeManager`

---

### Step 1.6: Update Tests

**File**: `Tests/DeviceManagerTests.swift`

Tests should still pass without modification because:
- `DeviceManager` facade maintains the same public API
- `AudioDevice` struct is unchanged
- Static method `selectFallbackOutputDevice` still accessible via `DeviceManager.selectFallbackOutputDevice(from:)`

**Add new tests** (optional but recommended):
```swift
// DeviceEnumeratorTests.swift
final class DeviceEnumeratorTests: XCTestCase {
    // Tests for DeviceEnumerator specifically
}

// DeviceVolumeServiceTests.swift
final class DeviceVolumeServiceTests: XCTestCase {
    // Tests for DeviceVolumeService specifically
}
```

**Verification**:
- `swift test` — all existing tests pass
- No test failures

---

### Step 1.7: Update VolumeManager to Use Service Directly

**File**: `Sources/Core/VolumeManager.swift`

Update `VolumeManager` to accept `VolumeControlling` protocol instead of concrete `DeviceManager`. This is an optional improvement for future testability.

**Change dependency injection**:
```swift
// Before
private let deviceManager: DeviceManager

init(deviceManager: DeviceManager) {
    self.deviceManager = deviceManager
}

// After (preferred)
private let volumeService: VolumeControlling
private let enumerator: DeviceEnumerating

init(volumeService: VolumeControlling, enumerator: DeviceEnumerating) {
    self.volumeService = volumeService
    self.enumerator = enumerator
}
```

**Keep backward-compatible initialiser**:
```swift
convenience init(deviceManager: DeviceManager) {
    self.init(
        volumeService: deviceManager.volume,
        enumerator: deviceManager.enumerator
    )
}
```

**Note**: This step is optional. The current approach of passing `DeviceManager` and using its pass-through methods works fine. The improvement is for test injection.

---

### Step 1.8: Clean Up

1. Remove extracted code from original `DeviceManager.swift`
2. Ensure CoreAudio constant imports are correct in all new files
3. Run full test suite

**Final File Structure**:
```
Sources/Device/
├── AudioDevice.swift            (unchanged)
├── DeviceConstants.swift        (unchanged)
├── CoreAudioHelpers.swift       (NEW)
├── DeviceEnumerator.swift       (NEW)
├── DeviceVolumeService.swift    (NEW)
├── DeviceSampleRateService.swift (NEW)
├── Protocols/
│   ├── DeviceEnumerating.swift  (NEW)
│   ├── VolumeControlling.swift   (NEW)
│   └── SampleRateObserving.swift (NEW)
└── DeviceManager.swift           (facade)
```

---

## Testing Checklist

After each step:

- [x] `swift build` compiles without errors
- [x] `swift test` passes all tests (141 tests passed)
- [x] Manual test: app launches and shows devices
- [x] Manual test: volume sync still works
- [x] Manual test: sample rate changes handled

---

## Rollback Plan

If Phase 1 causes issues:

1. Revert all new files
2. Restore original `DeviceManager.swift` from git
3. No other files were modified (only additions)

Each step is incremental and can be rolled back independently by removing the new file and restoring the original implementation in `DeviceManager.swift`.

---

## Summary of Changes

| File | Action | Lines Changed |
|------|--------|---------------|
| `CoreAudioHelpers.swift` | **NEW** | ~100 lines |
| `DeviceEnumerator.swift` | **NEW** | ~250 lines (extracted) |
| `DeviceVolumeService.swift` | **NEW** | ~260 lines (extracted) |
| `DeviceSampleRateService.swift` | **NEW** | ~80 lines (extracted) |
| `DeviceEnumerating.swift` | **NEW** | ~15 lines (protocol) |
| `VolumeControlling.swift` | **NEW** | ~15 lines (protocol) |
| `SampleRateObserving.swift` | **NEW** | ~10 lines (protocol) |
| `DeviceManager.swift` | **MODIFY** | Replace with facade (~200 lines) |
| `VolumeManager.swift` | **MODIFY** (optional) | ~10 lines (DI improvement) |

**Net Result**:
- `DeviceManager.swift` reduced from 987 lines to ~215 lines (facade)
- Clear separation of concerns
- Each service is focused and testable
- Backward compatibility maintained

---

## Implementation Summary

Phase 1 was successfully implemented on 2026-03-16.

### Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `CoreAudioHelpers.swift` | 92 | Shared CoreAudio property access utilities |
| `DeviceEnumerator.swift` | 357 | Device enumeration and discovery |
| `DeviceVolumeService.swift` | 410 | Volume and mute control |
| `DeviceSampleRateService.swift` | 101 | Sample rate query and observation |
| `DeviceEnumerating.swift` | 42 | Protocol for enumeration |
| `VolumeControlling.swift` | 44 | Protocol for volume control |
| `SampleRateObserving.swift` | 20 | Protocol for sample rate |

### Files Modified

| File | Before | After | Change |
|------|--------|-------|--------|
| `DeviceManager.swift` | 987 lines | 215 lines | -772 lines (now a facade) |

### Verification

- ✅ Build succeeds
- ✅ All 141 tests pass
- ✅ App launches correctly
- ✅ Backward compatibility maintained — no changes required to `EqualiserStore` or `VolumeManager`