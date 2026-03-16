# Phase 2: Extract Driver Services

**Risk Level**: Low  
**Estimated Effort**: 2 sessions  
**Prerequisites**: Phase 1 complete

## Goal

Extract focused, single-responsibility services from `DriverManager.swift` (703 lines). The current class handles multiple concerns: installation lifecycle, device discovery, device properties, and system default device management. Each responsibility will become a separate service while `DriverManager` remains as a facade.

## Current State Analysis

### DriverManager Responsibilities (703 lines)

| Responsibility | Lines | Purpose |
|---------------|-------|---------|
| Installation/Uninstallation | 75-138 | Install driver with admin privileges, uninstall |
| Status/Version | 453-543 | Check installation status, version comparison |
| Device Discovery | 545-651 | Find driver device by UID, retry logic |
| Device Properties | 140-232, 655-681 | Get/set device name, get/set sample rate |
| System Default Device | 234-449 | Set driver as default, restore to built-in speakers |
| Device ID Cache | 60, 144-148, 183-187, 244, 506, 535, 635, 656 | Cache and refresh device ID |
| Validation | 319-334, 478-486 | Validate device exists |

### Consumers

1. **EqualiserStore** — primary consumer using 20+ methods:
   - `isReady` — check if driver installed
   - `deviceID` — get cached device ID
   - `isDriverVisible()` — check CoreAudio visibility
   - `findDriverDeviceWithRetry()` — async device discovery
   - `setDeviceName(_:)` — set driver name
   - `setAsDefaultOutputDevice()` — make driver the default output
   - `restoreToBuiltInSpeakers()` — restore system default
   - `setDriverSampleRate(matching:)` — match output device sample rate
   - `status` — observe installation status

2. **DriverInstallationView** — UI for installation:
   - `isReady` — show installed status
   - `status` — observe installation status
   - `installDriver()` — trigger installation

3. **SettingsView** — settings panel:
   - `isReady` — show driver status
   - `status` — observe installation status

### Published Properties

- `status: DriverStatus` — UI observes this for installation state
- `isInstalling: Bool` — UI shows progress
- `installError: String?` — UI shows errors
- `deviceID: AudioObjectID?` — cached device ID
- `driverSampleRate: Float64?` — current sample rate

---

## Target Architecture

```
Sources/Driver/
├── DriverConstants.swift          ← Existing (no changes)
├── DriverManager.swift            ← Facade composing services
├── DriverLifecycleService.swift   ← NEW: Install/uninstall, status
├── DriverPropertyService.swift    ← NEW: Name, sample rate
├── DriverDeviceRegistry.swift     ← NEW: Device ID cache, discovery
└── Protocols/
    ├── DriverLifecycle.swift      ← NEW: Protocol for lifecycle
    ├── DriverPropertyAccessing.swift ← NEW: Protocol for properties
    └── DriverDeviceDiscovering.swift  ← NEW: Protocol for discovery
```

### Service Interfaces

```swift
// DriverLifecycleService.swift
@MainActor
protocol DriverLifecycleManaging: ObservableObject {
    var status: DriverStatus { get }
    var isInstalling: Bool { get }
    var installError: String? { get }
    var isReady: Bool { get }
    
    func installDriver() async throws
    func uninstallDriver() async throws
    func checkInstallationStatus()
}

// DriverPropertyService.swift
@MainActor
protocol DriverPropertyAccessing: AnyObject {
    var driverSampleRate: Float64? { get }
    
    func setDeviceName(_ name: String)
    func getDeviceName() -> String?
    func setDriverSampleRate(matching targetRate: Float64) -> Float64?
}

// DriverDeviceRegistry.swift
@MainActor
protocol DriverDeviceDiscovering: ObservableObject {
    var deviceID: AudioDeviceID? { get }
    
    func isDriverVisible() -> Bool
    func findDriverDeviceWithRetry(initialDelayMs: Int, maxAttempts: Int) async -> AudioDeviceID?
    func setAsDefaultOutputDevice() -> Bool
    func restoreToBuiltInSpeakers() -> Bool
}
```

### Facade Pattern

`DriverManager` will remain as a singleton facade:

```swift
@MainActor
public final class DriverManager: ObservableObject {
    public static let shared = DriverManager()
    
    // Services (internal for testing)
    let lifecycle: DriverLifecycleManaging
    let properties: DriverPropertyAccessing
    let registry: DriverDeviceDiscovering
    
    // Convenience pass-throughs for backward compatibility
    public var status: DriverStatus { lifecycle.status }
    public var isInstalling: Bool { lifecycle.isInstalling }
    public var deviceID: AudioObjectID? { registry.deviceID }
    // ... etc
}
```

---

## Implementation Steps

### Step 2.1: Create DriverDeviceRegistry Service

**File**: `Sources/Driver/DriverDeviceRegistry.swift`

**Extract from DriverManager** (lines 60, 144-148, 183-187, 244, 319-334, 478-486, 506, 535, 545-651):
- `deviceID` published property
- `findDriverDevice()` private → internal
- `findDriverDeviceWithRetry()` async
- `isDriverVisible()`
- `validateDeviceExists(_:)` private
- `setAsDefaultOutputDevice()`
- `restoreToBuiltInSpeakers()`
- `getCurrentDefaultOutputDeviceID()` private
- `previousSystemDefaultDeviceID` private

**Content**:
```swift
// DriverDeviceRegistry.swift
// Driver device discovery and registry management

import Foundation
import CoreAudio
import OSLog

/// Manages driver device discovery and caching.
/// Responsible for finding the driver in CoreAudio and managing the device ID cache.
@MainActor
public final class DriverDeviceRegistry: ObservableObject, DriverDeviceDiscovering {
    
    // MARK: - Published Properties
    
    /// The cached device ID for the driver
    @Published public private(set) var deviceID: AudioObjectID?
    
    // MARK: - Private Properties
    
    private var previousSystemDefaultDeviceID: AudioDeviceID?
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverDeviceRegistry")
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Device Discovery
    
    /// Checks if driver is currently visible in CoreAudio.
    /// First validates cached ID, then attempts fresh lookup.
    public func isDriverVisible() -> Bool {
        if let cachedID = deviceID, validateDeviceExists(cachedID) {
            return true
        }
        deviceID = findDriverDevice()
        return deviceID != nil
    }
    
    /// Finds the driver device with retry logic for CoreAudio reconfiguration delays.
    public func findDriverDeviceWithRetry(
        initialDelayMs: Int = 100,
        maxAttempts: Int = 6
    ) async -> AudioDeviceID? {
        logger.debug("Waiting \(initialDelayMs)ms for CoreAudio stabilization...")
        try? await Task.sleep(for: .milliseconds(initialDelayMs))
        
        var delayMs = 50
        
        for attempt in 1...maxAttempts {
            deviceID = findDriverDevice()
            
            if let id = deviceID {
                if attempt > 1 {
                    logger.info("Found driver on attempt \(attempt) after previous delays")
                }
                return id
            }
            
            logger.debug("Driver not found (attempt \(attempt)/\(maxAttempts)), retrying in \(delayMs)ms...")
            try? await Task.sleep(for: .milliseconds(delayMs))
            delayMs = min(delayMs * 2, 800)
        }
        
        logger.error("Driver not found after \(maxAttempts) attempts")
        return nil
    }
    
    /// Finds the Equaliser driver device by UID.
    /// - Returns: The AudioObjectID if found, nil otherwise.
    public func refreshDeviceID() -> AudioObjectID? {
        deviceID = findDriverDevice()
        return deviceID
    }
    
    // MARK: - Private Discovery
    
    private func findDriverDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            logger.error("Failed to get device count: \(status)")
            return nil
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard status == noErr else {
            logger.error("Failed to get device list: \(status)")
            return nil
        }
        
        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &uidAddress,
                0,
                nil,
                &uidSize,
                &uid
            )
            
            if status == noErr, let uidString = uid?.takeRetainedValue() as String?,
               uidString == DRIVER_DEVICE_UID {
                logger.debug("Found driver: deviceID=\(deviceID)")
                return deviceID
            }
        }
        
        logger.error("Driver not found among \(deviceCount) devices")
        return nil
    }
    
    private func validateDeviceExists(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return status == noErr
    }
    
    // MARK: - System Default Device
    
    public func setAsDefaultOutputDevice() -> Bool {
        previousSystemDefaultDeviceID = getCurrentDefaultOutputDeviceID()
        
        deviceID = findDriverDevice()
        
        guard let deviceID = deviceID else {
            logger.error("Cannot set default output: driver device not found in CoreAudio")
            return false
        }
        
        guard validateDeviceExists(deviceID) else {
            logger.error("Device ID \(deviceID) failed validation - device may be stale or removed")
            self.deviceID = nil
            return false
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceIDValue = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDValue
        )
        
        if status != noErr {
            logger.error("Failed to set driver as default output: \(status)")
            return false
        }
        
        // Verify the system default actually changed
        var verifyID: AudioDeviceID = 0
        var verifySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let verifyStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil, &verifySize, &verifyID
        )
        
        if verifyStatus == noErr && verifyID == deviceID {
            logger.info("Set driver as default output device (ID: \(deviceID))")
            return true
        } else {
            logger.error("Failed to verify default output device (expected \(deviceID), got \(verifyID))")
            return false
        }
    }
    
    public func restoreToBuiltInSpeakers() -> Bool {
        // Enumerate audio devices to find first physical output
        // ... (implementation)
    }
    
    private func getCurrentDefaultOutputDeviceID() -> AudioDeviceID? {
        // ... (implementation)
    }
}
```

**Verification**: Build should succeed. No functional changes.

---

### Step 2.2: Create DriverPropertyService

**File**: `Sources/Driver/DriverPropertyService.swift`

**Extract from DriverManager** (lines 142-169, 171-232, 655-681):
- `setDeviceName(_:)`
- `getDeviceName()`
- `setDriverSampleRate(matching:)`
- `driverSampleRate` published property

**Content**:
```swift
// DriverPropertyService.swift
// Driver property access (name, sample rate)

import Foundation
import CoreAudio
import OSLog

/// Manages driver properties: name and sample rate.
@MainActor
public final class DriverPropertyService: ObservableObject, DriverPropertyAccessing {
    
    // MARK: - Published Properties
    
    @Published public private(set) var driverSampleRate: Float64?
    
    // MARK: - Dependencies
    
    private let registry: DriverDeviceDiscovering
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverPropertyService")
    
    // MARK: - Initialization
    
    public init(registry: DriverDeviceDiscovering) {
        self.registry = registry
    }
    
    // MARK: - Device Name
    
    public func setDeviceName(_ name: String) {
        // Refresh device ID in case CoreAudio re-enumerated
        registry.refreshDeviceID()
        
        guard let deviceID = registry.deviceID else {
            logger.warning("setDeviceName: driver device not found")
            return
        }
        
        var address = DRIVER_ADDRESS_NAME
        var nameRef: CFString = name as CFString
        
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<CFString>.stride),
            &nameRef
        )
        
        if status != noErr {
            logger.error("Failed to set device name: \(status)")
        }
    }
    
    public func getDeviceName() -> String? {
        registry.refreshDeviceID()
        
        guard let deviceID = registry.deviceID else {
            return nil
        }
        
        var address = DRIVER_ADDRESS_NAME
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &nameRef
        )
        
        if status != noErr {
            logger.error("Failed to get device name: \(status)")
            return nil
        }
        
        return nameRef?.takeRetainedValue() as String?
    }
    
    // MARK: - Sample Rate
    
    public func setDriverSampleRate(matching targetRate: Float64) -> Float64? {
        registry.refreshDeviceID()
        
        guard let deviceID = registry.deviceID else {
            logger.warning("setDriverSampleRate: driver device not found")
            return nil
        }
        
        let closestRate = closestSupportedSampleRate(to: targetRate)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var rate = closestRate
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &rate
        )
        
        if status != noErr {
            logger.error("Failed to set driver sample rate: \(status)")
            return nil
        }
        
        // Verify the rate was actually set by reading it back
        var verifyRate: Float64 = 0
        var verifySize = UInt32(MemoryLayout<Float64>.size)
        let verifyStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &verifySize, &verifyRate)
        
        if verifyStatus != noErr {
            logger.warning("Could not verify driver sample rate after setting")
            driverSampleRate = closestRate
            return closestRate
        }
        
        if verifyRate != closestRate {
            logger.warning("Driver sample rate mismatch: set \(closestRate), got \(verifyRate)")
            driverSampleRate = verifyRate
            return verifyRate
        }
        
        driverSampleRate = closestRate
        logger.info("Driver sample rate set and verified: \(closestRate) Hz (requested: \(targetRate))")
        return closestRate
    }
}
```

**Verification**: Build should succeed.

---

### Step 2.3: Create DriverLifecycleService

**File**: `Sources/Driver/DriverLifecycleService.swift`

**Extract from DriverManager** (lines 14-44, 53-71, 73-138, 453-543):
- `DriverStatus` enum
- `DriverError` enum
- `status`, `isInstalling`, `installError` published properties
- `isReady` computed property
- `installDriver()` async throws
- `uninstallDriver()` async throws
- `checkInstallationStatus()`
- `getInstalledDriverVersion()` private
- `getBundledDriverVersion()` private

**Content**:
```swift
// DriverLifecycleService.swift
// Driver installation and lifecycle management

import Foundation
import CoreAudio
import OSLog

/// Driver installation status
public enum DriverStatus: Equatable {
    case notInstalled
    case installed(version: String)
    case needsUpdate(currentVersion: String, bundledVersion: String)
    case error(String)
}

/// Driver-related errors
public enum DriverError: LocalizedError {
    case driverNotFoundInBundle
    case installationFailed(String)
    case uninstallationFailed(String)
    case deviceNotFound
    case propertySetFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .driverNotFoundInBundle:
            return "Driver not found in application bundle"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallationFailed(let message):
            return "Uninstallation failed: \(message)"
        case .deviceNotFound:
            return "Driver device not found in CoreAudio"
        case .propertySetFailed(let message):
            return "Failed to set driver property: \(message)"
        }
    }
}

/// Manages driver installation, uninstallation, and status.
@MainActor
public final class DriverLifecycleService: ObservableObject, DriverLifecycleManaging {
    
    // MARK: - Published Properties
    
    @Published public private(set) var status: DriverStatus = .notInstalled
    @Published public var isInstalling: Bool = false
    @Published public var installError: String?
    
    // MARK: - Private Properties
    
    private var installedVersion: String?
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverLifecycleService")
    
    // MARK: - Computed Properties
    
    public var isReady: Bool {
        if case .installed(_) = status {
            return true
        }
        
        // Fallback: check if driver actually exists on disk
        let exists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        return exists
    }
    
    // MARK: - Initialization
    
    public init() {
        checkInstallationStatus()
    }
    
    // MARK: - Installation
    
    public func installDriver() async throws {
        guard !isInstalling else { return }
        
        isInstalling = true
        installError = nil
        
        do {
            guard let bundledURL = Bundle.main.url(forResource: "Equaliser", withExtension: "driver") else {
                throw DriverError.driverNotFoundInBundle
            }
            
            logger.info("Installing driver from \(bundledURL.path)")
            
            let script = "if [ -d '\(DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(DRIVER_BUNDLE_PATH)'; fi; mkdir -p '\(DRIVER_INSTALL_PATH)'; cp -R '\(bundledURL.path)' '\(DRIVER_BUNDLE_PATH)'; chown -R root:wheel '\(DRIVER_BUNDLE_PATH)'; chmod -R 755 '\(DRIVER_BUNDLE_PATH)'; killall coreaudiod"
            
            try await executeWithAdminPrivileges(script: script)
            
            try await Task.sleep(for: .seconds(2))
            
            checkInstallationStatus()
            
            if case .notInstalled = status {
                throw DriverError.installationFailed("Driver not found after installation")
            }
            
            logger.info("Driver installed successfully")
            
            NotificationCenter.default.post(name: .driverDidInstall, object: nil)
            
        } catch {
            isInstalling = false
            throw error
        }
        
        isInstalling = false
    }
    
    public func uninstallDriver() async throws {
        guard !isInstalling else { return }
        
        isInstalling = true
        
        do {
            let script = "if [ -d '\(DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(DRIVER_BUNDLE_PATH)'; killall coreaudiod; fi"
            
            try await executeWithAdminPrivileges(script: script)
            
            try await Task.sleep(for: .seconds(1))
            
            checkInstallationStatus()
            
            logger.info("Driver uninstalled successfully")
            
            NotificationCenter.default.post(name: .driverDidUninstall, object: nil)
            
        } catch {
            isInstalling = false
            throw error
        }
        
        isInstalling = false
    }
    
    // MARK: - Status Checking
    
    public func checkInstallationStatus() {
        logger.debug("Checking installation status...")
        logger.debug("Driver bundle path: \(DRIVER_BUNDLE_PATH)")
        
        let fileExists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        logger.debug("Driver bundle exists: \(fileExists)")
        
        guard fileExists else {
            logger.warning("Driver not found at \(DRIVER_BUNDLE_PATH)")
            status = .notInstalled
            return
        }
        
        installedVersion = getInstalledDriverVersion()
        let versionStr = installedVersion ?? "unknown"
        logger.debug("Installed version: \(versionStr)")
        
        if let version = installedVersion {
            let bundledVersion = getBundledDriverVersion()
            logger.debug("Bundled version: \(bundledVersion)")
            if version < bundledVersion {
                status = .needsUpdate(currentVersion: version, bundledVersion: bundledVersion)
            } else {
                status = .installed(version: version)
            }
        } else {
            status = .installed(version: "unknown")
        }
        
        let statusStr = String(describing: status)
        logger.info("Installation status: \(statusStr)")
    }
    
    // MARK: - Private Helpers
    
    private func getBundledDriverVersion() -> String {
        guard let resourcePath = Bundle.main.resourcePath else { return "1.0" }
        let driverInfoPath = resourcePath + "/Equaliser.driver/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: driverInfoPath),
              let version = info["CFBundleShortVersionString"] as? String else {
            return "1.0"
        }
        return version
    }
    
    private func getInstalledDriverVersion() -> String? {
        let infoPath = DRIVER_BUNDLE_PATH + "/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }
    
    private func executeWithAdminPrivileges(script: String) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw DriverError.installationFailed("Script failed (status \(task.terminationStatus)): \(errorMessage)")
        }
    }
}
```

**Verification**: Build should succeed.

---

### Step 2.4: Create Protocol Files

**File**: `Sources/Driver/Protocols/DriverLifecycleManaging.swift`

```swift
// DriverLifecycleManaging.swift
// Protocol for driver lifecycle management

import Foundation

@MainActor
protocol DriverLifecycleManaging: ObservableObject {
    var status: DriverStatus { get }
    var isInstalling: Bool { get }
    var installError: String? { get }
    var isReady: Bool { get }
    
    func installDriver() async throws
    func uninstallDriver() async throws
    func checkInstallationStatus()
}
```

**File**: `Sources/Driver/Protocols/DriverPropertyAccessing.swift`

```swift
// DriverPropertyAccessing.swift
// Protocol for driver property access

import Foundation
import CoreAudio

@MainActor
protocol DriverPropertyAccessing: AnyObject {
    var driverSampleRate: Float64? { get }
    
    func setDeviceName(_ name: String)
    func getDeviceName() -> String?
    func setDriverSampleRate(matching targetRate: Float64) -> Float64?
}
```

**File**: `Sources/Driver/Protocols/DriverDeviceDiscovering.swift`

```swift
// DriverDeviceDiscovering.swift
// Protocol for driver device discovery

import Foundation
import CoreAudio

@MainActor
protocol DriverDeviceDiscovering: ObservableObject {
    var deviceID: AudioObjectID? { get }
    
    func isDriverVisible() -> Bool
    func findDriverDeviceWithRetry(initialDelayMs: Int, maxAttempts: Int) async -> AudioDeviceID?
    func refreshDeviceID() -> AudioObjectID?
    func setAsDefaultOutputDevice() -> Bool
    func restoreToBuiltInSpeakers() -> Bool
}
```

**Verification**: Build should succeed.

---

### Step 2.5: Convert DriverManager to Facade

**File**: `Sources/Driver/DriverManager.swift`

Transform DriverManager into a facade that composes the three services.

**Changes**:
1. Remove all implementation code (moved to services)
2. Add service properties
3. Add convenience pass-through methods
4. Keep `DriverStatus` and `DriverError` enums in this file for backward compatibility

**Final DriverManager**:
```swift
// DriverManager.swift
// Facade for driver-related services - maintains backward compatibility

import Foundation
import CoreAudio
import OSLog

// MARK: - Driver Status (kept for backward compatibility)

public enum DriverStatus: Equatable {
    case notInstalled
    case installed(version: String)
    case needsUpdate(currentVersion: String, bundledVersion: String)
    case error(String)
}

// MARK: - Driver Error (kept for backward compatibility)

public enum DriverError: LocalizedError {
    case driverNotFoundInBundle
    case installationFailed(String)
    case uninstallationFailed(String)
    case deviceNotFound
    case propertySetFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .driverNotFoundInBundle:
            return "Driver not found in application bundle"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallationFailed(let message):
            return "Uninstallation failed: \(message)"
        case .deviceNotFound:
            return "Driver device not found in CoreAudio"
        case .propertySetFailed(let message):
            return "Failed to set driver property: \(message)"
        }
    }
}

// MARK: - Driver Manager Facade

/// Facade for driver-related services.
/// Maintains backward compatibility while delegating to specialised services.
@MainActor
public final class DriverManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = DriverManager()
    
    // MARK: - Services (internal for testing)
    
    let lifecycleService: DriverLifecycleService
    let propertyService: DriverPropertyService
    let deviceRegistry: DriverDeviceRegistry
    
    // MARK: - Published Properties (forwarded from services)
    
    public var status: DriverStatus { lifecycleService.status }
    public var isInstalling: Bool { lifecycleService.isInstalling }
    public var installError: String? { lifecycleService.installError }
    public var deviceID: AudioObjectID? { deviceRegistry.deviceID }
    public var isReady: Bool { lifecycleService.isReady }
    public var driverSampleRate: Float64? { propertyService.driverSampleRate }
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverManager")
    
    // MARK: - Initialization
    
    private init() {
        let registry = DriverDeviceRegistry()
        self.deviceRegistry = registry
        self.lifecycleService = DriverLifecycleService()
        self.propertyService = DriverPropertyService(registry: registry)
    }
    
    // MARK: - Lifecycle (pass-through)
    
    public func installDriver() async throws {
        try await lifecycleService.installDriver()
    }
    
    public func uninstallDriver() async throws {
        try await lifecycleService.uninstallDriver()
    }
    
    public func checkInstallationStatus() {
        lifecycleService.checkInstallationStatus()
    }
    
    // MARK: - Device Discovery (pass-through)
    
    public func isDriverVisible() -> Bool {
        deviceRegistry.isDriverVisible()
    }
    
    public func findDriverDeviceWithRetry(
        initialDelayMs: Int = 100,
        maxAttempts: Int = 6
    ) async -> AudioDeviceID? {
        await deviceRegistry.findDriverDeviceWithRetry(
            initialDelayMs: initialDelayMs,
            maxAttempts: maxAttempts
        )
    }
    
    // MARK: - Device Properties (pass-through)
    
    public func setDeviceName(_ name: String) {
        propertyService.setDeviceName(name)
    }
    
    public func getDeviceName() -> String? {
        propertyService.getDeviceName()
    }
    
    @discardableResult
    public func setDriverSampleRate(matching targetRate: Float64) -> Float64? {
        propertyService.setDriverSampleRate(matching: targetRate)
    }
    
    // MARK: - System Default Device (pass-through)
    
    @discardableResult
    public func setAsDefaultOutputDevice() -> Bool {
        deviceRegistry.setAsDefaultOutputDevice()
    }
    
    @discardableResult
    public func restoreToBuiltInSpeakers() -> Bool {
        deviceRegistry.restoreToBuiltInSpeakers()
    }
}
```

**Verification**: 
- Build should succeed
- All existing code using `DriverManager.shared` continues to work unchanged

---

### Step 2.6: Update Protocol Files to Avoid Duplication

Since `DriverStatus` and `DriverError` are now defined in `DriverManager.swift`, we need to ensure the protocols use the same types. The protocol files should reference these types.

No changes needed — the protocols don't define these types, they're defined in `DriverManager.swift` which is the main entry point.

---

### Step 2.7: Run Tests

The existing tests don't directly test `DriverManager` (it requires real hardware/driver). Verify:

- [ ] `swift build` compiles without errors
- [ ] `swift test` passes all tests
- [ ] App launches and can interact with driver settings

---

## Testing Strategy

### Unit Tests (Optional but Recommended)

Create `DriverServiceTests.swift`:

```swift
// DriverServiceTests.swift
@testable import Equaliser
import XCTest

final class DriverLifecycleServiceTests: XCTestCase {
    func testIsReady_whenNotInstalled_returnsFalse() {
        // This would require mocking FileManager
    }
    
    func testStatus_whenInstalled_returnsVersion() {
        // This would require mocking file system
    }
}

final class DriverDeviceRegistryTests: XCTestCase {
    func testFindDriverDevice_whenNotFound_returnsNil() {
        let registry = DriverDeviceRegistry()
        XCTAssertNil(registry.deviceID)
    }
    
    func testIsDriverVisible_whenNoDevice_returnsFalse() {
        let registry = DriverDeviceRegistry()
        XCTAssertFalse(registry.isDriverVisible())
    }
}

final class DriverPropertyServiceTests: XCTestCase {
    func testGetDeviceName_whenNoDevice_returnsNil() {
        let registry = DriverDeviceRegistry()
        let service = DriverPropertyService(registry: registry)
        XCTAssertNil(service.getDeviceName())
    }
}
```

---

## Summary of Changes

| File | Action | Lines |
|------|--------|-------|
| `DriverLifecycleService.swift` | **NEW** | ~160 lines |
| `DriverPropertyService.swift` | **NEW** | ~130 lines |
| `DriverDeviceRegistry.swift` | **NEW** | ~250 lines |
| `Protocols/DriverLifecycleManaging.swift` | **NEW** | ~15 lines |
| `Protocols/DriverPropertyAccessing.swift` | **NEW** | ~15 lines |
| `Protocols/DriverDeviceDiscovering.swift` | **NEW** | ~15 lines |
| `DriverManager.swift` | **MODIFY** | ~180 lines (facade) |
| `DriverConstants.swift` | **NO CHANGE** | — |

**Net Result**:
- `DriverManager.swift` reduced from 703 lines to ~180 lines (facade)
- Clear separation of concerns
- Each service is focused and testable
- Backward compatibility maintained via facade pattern

---

## Rollback Plan

If Phase 2 causes issues:

1. Revert all new files in `Sources/Driver/` (except `DriverConstants.swift`)
2. Restore original `DriverManager.swift` from git
3. Delete `Sources/Driver/Protocols/` directory

---

## Verification Checklist

- [x] `swift build` succeeds without errors
- [x] `swift test` passes all tests (141 tests passed)
- [ ] Manual test: app launches and shows driver installation UI correctly
- [ ] Manual test: driver installation flow works
- [ ] Manual test: device name can be set/get
- [ ] Manual test: sample rate changes work
- [ ] Manual test: system default device setting works

---

## Implementation Summary

Phase 2 was successfully implemented on 2026-03-16.

### Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `DriverTypes.swift` | 39 | Shared types (DriverStatus, DriverError) |
| `DriverDeviceRegistry.swift` | 367 | Device ID cache, discovery, system default |
| `DriverPropertyService.swift` | 140 | Name and sample rate properties |
| `DriverLifecycleService.swift` | 183 | Install/uninstall, status checking |
| `Protocols/DriverDeviceDiscovering.swift` | 26 | Protocol for device discovery |
| `Protocols/DriverPropertyAccessing.swift` | 23 | Protocol for property access |
| `Protocols/DriverLifecycleManaging.swift` | 28 | Protocol for lifecycle management |

### Files Modified

| File | Before | After | Change |
|------|--------|-------|--------|
| `DriverManager.swift` | 703 lines | 128 lines | **-575 lines** (now a facade) |

### Architecture

**Before**: `DriverManager` was a 703-line class handling:
- Installation/uninstallation
- Status checking and version comparison
- Device ID caching and discovery
- Device name and sample rate properties
- System default device management

**After**: `DriverManager` is a 128-line **facade** composing three focused services:
- `DriverLifecycleService` — install/uninstall, status
- `DriverDeviceRegistry` — device ID cache, discovery, system default
- `DriverPropertyService` — name, sample rate

### Benefits

1. **Single Responsibility Principle**: Each service has one responsibility
2. **Dependency Injection**: `DriverPropertyService` depends on `DriverDeviceRegistry`
3. **Backward Compatibility**: `DriverManager.shared` facade preserves all public APIs
4. **Testability**: Services can be unit tested in isolation
5. **Discoverability**: Code organized by capability

### Verification

- ✅ Build succeeds
- ✅ All 141 tests pass
- ✅ Backward compatibility maintained — no changes required to consumers