//  DriverManager.swift
//  Equaliser
//
//  Manages the built-in virtual audio driver installation and lifecycle

import Foundation
import CoreAudio
import OSLog

private let log = Logger(subsystem: "net.knage.equaliser", category: "DriverManager")

// MARK: - Driver Status

public enum DriverStatus: Equatable {
    case notInstalled
    case installed(version: String)
    case needsUpdate(currentVersion: String, bundledVersion: String)
    case error(String)
}

// MARK: - Driver Error

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

// MARK: - Driver Manager

@MainActor
public final class DriverManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = DriverManager()
    
    // MARK: - Published Properties
    
     @Published public private(set) var status: DriverStatus = .notInstalled
     @Published public var isInstalling: Bool = false
     @Published public var installError: String?
     @Published public private(set) var deviceID: AudioObjectID?
     
     // MARK: - Private Properties
     
     private var installedVersion: String?
     private var previousSystemDefaultDeviceID: AudioDeviceID?
    
    // MARK: - Initialization
    
    private init() {
        checkInstallationStatus()
    }
    
    // MARK: - Public Methods - Installation
    
    public func installDriver() async throws {
        guard !isInstalling else { return }
        
        isInstalling = true
        installError = nil
        
        do {
            guard let bundledURL = Bundle.main.url(forResource: "Equaliser", withExtension: "driver") else {
                throw DriverError.driverNotFoundInBundle
            }
            
 log.info("Installing driver from \(bundledURL.path)")
            
            let script = "if [ -d '\(DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(DRIVER_BUNDLE_PATH)'; fi; mkdir -p '\(DRIVER_INSTALL_PATH)'; cp -R '\(bundledURL.path)' '\(DRIVER_BUNDLE_PATH)'; chown -R root:wheel '\(DRIVER_BUNDLE_PATH)'; chmod -R 755 '\(DRIVER_BUNDLE_PATH)'; killall coreaudiod"
            
            try await executeWithAdminPrivileges(script: script)
            
            try await Task.sleep(for: .seconds(2))
            
            checkInstallationStatus()
            
            if case .notInstalled = status {
                throw DriverError.installationFailed("Driver not found after installation")
            }
            
            log.info("Driver installed successfully")
            
            // Notify that driver was installed so DeviceManager can refresh
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
            
            log.info("Driver uninstalled successfully")
            
            // Notify that driver was uninstalled so DeviceManager can refresh
            NotificationCenter.default.post(name: .driverDidUninstall, object: nil)
            
        } catch {
            isInstalling = false
            throw error
        }
        
        isInstalling = false
    }
    
    // MARK: - Public Methods - Device Properties
    
     public func setDeviceName(_ name: String) {
         // Refresh device ID in case CoreAudio re-enumerated
         deviceID = findDriverDevice()
         
         guard let deviceID = deviceID else { 
             log.warning("setDeviceName: driver device not found")
             return 
         }
         
         var address = DRIVER_ADDRESS_NAME
         // Note: Compiler warns about CFString pointer, but this is correct for SET operations.
         // For GET operations we use Unmanaged<CFString>? to handle ownership, but for SET
         // operations we must provide a pointer to the existing CFString reference.
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
              log.error("Failed to set device name: \(status)")
          }
     }
     
     public func setOutputLatency(_ frames: UInt32) {
         guard let deviceID = deviceID else { return }
         
         var address = DRIVER_ADDRESS_LATENCY
         var latencyValue = frames
         
         let status = AudioObjectSetPropertyData(
             deviceID,
             &address,
             0,
             nil,
             UInt32(MemoryLayout<UInt32>.size),
             &latencyValue
         )
         
         if status != noErr {
             log.error("Failed to set output latency: \(status)")
         }
     }
     
     // MARK: - Sample Rate
     
     /// The current sample rate of the driver, if known.
     @Published public private(set) var driverSampleRate: Float64?
     
     /// Sets the driver's nominal sample rate to the closest supported rate.
     /// Verifies the rate was actually set by reading it back.
     /// - Parameter targetRate: The desired sample rate (e.g., from output device).
     /// - Returns: The actual rate set, or nil on failure.
     @discardableResult
     public func setDriverSampleRate(matching targetRate: Float64) -> Float64? {
         deviceID = findDriverDevice()
         
         guard let deviceID = deviceID else {
             log.warning("setDriverSampleRate: driver device not found")
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
             log.error("Failed to set driver sample rate: \(status)")
             return nil
         }
         
         // Verify the rate was actually set by reading it back
         var verifyRate: Float64 = 0
         var verifySize = UInt32(MemoryLayout<Float64>.size)
         let verifyStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &verifySize, &verifyRate)
         
         if verifyStatus != noErr {
             log.warning("Could not verify driver sample rate after setting")
             driverSampleRate = closestRate
             return closestRate
         }
         
         if verifyRate != closestRate {
             log.warning("Driver sample rate mismatch: set \(closestRate), got \(verifyRate)")
             driverSampleRate = verifyRate
             return verifyRate
         }
         
          driverSampleRate = closestRate
          log.info("Driver sample rate set and verified: \(closestRate) Hz (requested: \(targetRate))")
          return closestRate
      }
      
        @discardableResult
       public func setAsDefaultOutputDevice() -> Bool {
           // Store the current system default BEFORE we modify it
           previousSystemDefaultDeviceID = getCurrentDefaultOutputDeviceID()
           
           // Refresh device ID in case CoreAudio re-enumerated devices
           // This is critical because CoreAudio may assign new IDs after:
           // - coreaudiod restart
           // - device hot-swap
           // - sleep/wake cycle
           deviceID = findDriverDevice()
           
           guard let deviceID = deviceID else {
               log.error("Cannot set default output: driver device not found in CoreAudio")
               return false
           }
           
           // Validate device still exists and responds to queries
           guard validateDeviceExists(deviceID) else {
               log.error("Device ID \(deviceID) failed validation - device may be stale or removed")
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
               log.error("Failed to set driver as default output: \(status)")
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
               log.info("Set driver as default output device (ID: \(deviceID))")
               return true
           } else {
               log.error("Failed to verify default output device (expected \(deviceID), got \(verifyID))")
               return false
           }
       }
       
       /// Gets the current system default output device ID
       /// - Returns: The device ID, or nil if none set or error
       private func getCurrentDefaultOutputDeviceID() -> AudioDeviceID? {
           var deviceID: AudioDeviceID = 0
           var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
           var address = AudioObjectPropertyAddress(
               mSelector: kAudioHardwarePropertyDefaultOutputDevice,
               mScope: kAudioObjectPropertyScopeGlobal,
               mElement: kAudioObjectPropertyElementMain
           )
           
           let status = AudioObjectGetPropertyData(
               AudioObjectID(kAudioObjectSystemObject),
               &address, 0, nil, &propertySize, &deviceID
           )
           
           guard status == noErr, deviceID != 0 else {
               return nil
           }
           return deviceID
       }
       
       /// Validates that a device ID still exists and responds to CoreAudio queries
       /// - Parameter deviceID: The device ID to validate
       /// - Returns: true if device is valid and responsive
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
        
        /// Restores system default to a known-good device (built-in speakers).
        /// Called when the stored previous default no longer exists.
        /// - Returns: true if successful, false otherwise
        @discardableResult
        public func restoreToBuiltInSpeakers() -> Bool {
            // Enumerate audio devices to find first physical output
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
                log.error("Failed to get device count: \(status)")
                return false
            }
            
            let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
            var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
            
            status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &propertySize,
                &deviceIDs
            )
            
            guard status == noErr else {
                log.error("Failed to get device list: \(status)")
                return false
            }
            
            // Iterate through devices and find first physical output
            for deviceID in deviceIDs {
                // Check if this device has output channels
                var scopeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreamConfiguration,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: kAudioObjectPropertyElementMain
                )
                
                var bufferListSize: UInt32 = 0
                let scopeStatus = AudioObjectGetPropertyDataSize(deviceID, &scopeAddress, 0, nil, &bufferListSize)
                
                guard scopeStatus == noErr && bufferListSize > 0 else {
                    continue
                }
                
                // Check transport type - physical devices have non-zero transport type
                var transportAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyTransportType,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                
                var transportType: UInt32 = 0
                var transportSize = UInt32(MemoryLayout<UInt32>.size)
                let transportStatus = AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)
                
                if transportStatus == noErr && transportType != 0 {
                    // This is a physical device - set it as default
                    var setAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    
                    var deviceIDValue = deviceID
                    let setStatus = AudioObjectSetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &setAddress,
                        0,
                        nil,
                        UInt32(MemoryLayout<AudioDeviceID>.size),
                        &deviceIDValue
                    )
                    
                    if setStatus == noErr {
                        // Verify it was set correctly
                        var verifyID: AudioDeviceID = 0
                        var verifySize = UInt32(MemoryLayout<AudioDeviceID>.size)
                        var verifyAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        let verifyStatus = AudioObjectGetPropertyData(
                            AudioObjectID(kAudioObjectSystemObject),
                            &verifyAddress,
                            0, nil, &verifySize, &verifyID
                        )
                        
                        if verifyStatus == noErr && verifyID == deviceID {
                            log.info("Restored system default to built-in speakers (ID: \(deviceID))")
                            return true
                        }
                    }
                }
            }
            
            log.error("No built-in output device found to restore")
            return false
        }
     
     // MARK: - Public Methods - Queries
    
    public var isReady: Bool {
        // Check cached status first
        if case .installed(_) = status {
            return true
        }
        
        // Fallback: check if driver actually exists on disk
        // This handles race conditions during app initialization
        let exists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        
        if exists && deviceID == nil {
            // Driver exists but we haven't found the device yet - refresh status
            checkInstallationStatus()
            // Re-check status after refresh
            if case .installed(_) = status {
                return true
            }
        }
        
        return exists
    }
    
    public func checkInstallationStatus() {
        log.debug("Checking installation status...")
        log.debug("Driver bundle path: \(DRIVER_BUNDLE_PATH)")
        
        let fileExists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        log.debug("Driver bundle exists: \(fileExists)")
        
        guard fileExists else {
            log.warning("Driver not found at \(DRIVER_BUNDLE_PATH)")
            status = .notInstalled
            deviceID = nil
            return
        }
        
        installedVersion = getInstalledDriverVersion()
        let versionStr = installedVersion ?? "unknown"
        log.debug("Installed version: \(versionStr)")
        
        deviceID = findDriverDevice()
        let deviceIDStr = deviceID != nil ? String(deviceID!) : "nil"
        log.debug("Device ID: \(deviceIDStr)")
        
        if let version = installedVersion {
            let bundledVersion = getBundledDriverVersion()
            log.debug("Bundled version: \(bundledVersion)")
            if version < bundledVersion {
                status = .needsUpdate(currentVersion: version, bundledVersion: bundledVersion)
            } else {
                status = .installed(version: version)
            }
        } else {
            status = .installed(version: "unknown")
        }
        
        let statusStr = String(describing: status)
        log.info("Installation status: \(statusStr)")
    }
    
    private func getBundledDriverVersion() -> String {
        // Read from bundled driver in app's Resources folder
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
    
    // MARK: - Plugin-Level Discovery
    
    /// Finds the driver's plugin object ID.
    /// Returns the AudioObjectID of the Equaliser HAL plugin, or nil if not found.
    private func findDriverPluginID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyPlugInList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size
        )
        
        guard status == noErr else {
            log.error("Failed to get plugin list size: \(status)")
            return nil
        }
        
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var pluginIDs = [AudioObjectID](repeating: 0, count: count)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &pluginIDs
        )
        
        guard status == noErr else {
            log.error("Failed to get plugin list: \(status)")
            return nil
        }
        
        log.debug("Found \(count) HAL plugins")
        
        for pluginID in pluginIDs {
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyCreator,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            
            status = AudioObjectGetPropertyData(
                pluginID,
                &bundleAddress,
                0, nil,
                &bundleSize,
                &bundleID
            )
            
            if status == noErr, let bundleString = bundleID?.takeRetainedValue() as String? {
                log.debug("Plugin \(pluginID) bundle ID: \(bundleString)")
                if bundleString == DRIVER_BUNDLE_ID {
                    log.info("Found Equaliser driver plugin: pluginID=\(pluginID)")
                    return pluginID
                }
            }
        }
        
        log.debug("Equaliser driver plugin not found in plugin list")
        return nil
    }
    
    /// Finds the driver device by querying the plugin directly.
    /// This bypasses CoreAudio's visibility filter, allowing hidden devices to be found.
    /// - Returns: The device ID if found, nil otherwise.
    private func findDeviceViaPlugin() -> AudioDeviceID? {
        guard let pluginID = findDriverPluginID() else {
            return nil
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioPlugInPropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let cfUid: CFString = DRIVER_DEVICE_UID as CFString
        let uidPtr = Unmanaged.passUnretained(cfUid).toOpaque()
        
        let status = AudioObjectGetPropertyData(
            pluginID,
            &address,
            UInt32(MemoryLayout<CFString>.size),
            uidPtr,
            &size,
            &deviceID
        )
        
        if status == noErr && deviceID != 0 {
            log.info("Found driver via plugin-level query: deviceID=\(deviceID)")
            return deviceID
        }
        
        log.debug("Plugin-level UID translation failed: status=\(status), deviceID=\(deviceID)")
        return nil
    }
    
    // MARK: - Device Discovery
    
    /// Finds the Equaliser driver device.
    /// Attempts discovery in this order:
    /// 1. Plugin-level UID translation (bypasses visibility filter)
    /// 2. Device enumeration by UID/name (visible devices only)
    /// 3. System-level UID translation (fallback for hidden devices)
    /// - Returns: The AudioDeviceID if found, nil otherwise.
    private func findDriverDevice() -> AudioObjectID? {
        // First: Try plugin-level query (bypasses CoreAudio visibility filter)
        if let deviceID = findDeviceViaPlugin() {
            return deviceID
        }
        
        // Second: Try device enumeration (visible devices only)
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
            log.error("Failed to get device count: \(status)")
            return nil
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        log.debug("Found \(deviceCount) audio devices")
        
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
            log.error("Failed to get device list: \(status)")
            return nil
        }
        
        // First pass: match by UID
        log.debug("Searching for driver with UID: \(DRIVER_DEVICE_UID)")
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
            
            if status == noErr, let uidString = uid?.takeRetainedValue() as String? {
                log.debug("Device \(deviceID) UID: \(uidString)")
                
                if uidString == DRIVER_DEVICE_UID {
                    log.info("Found Equaliser driver by UID match: \(uidString)")
                    return deviceID
                }
            }
        }
        
        log.debug("Driver not found by UID, trying fallback name matching")
        
        // Fallback: match by device name
        for deviceID in deviceIDs {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &name
            )
            
            if status == noErr, let nameString = name?.takeRetainedValue() as String? {
                log.debug("Device \(deviceID) name: \(nameString)")
                
                if nameString == "Equaliser" || nameString == DRIVER_DEFAULT_NAME {
                    log.info("Found Equaliser driver by name match: \(nameString)")
                    return deviceID
                }
            }
        }
        
        // Fallback: use TranslateUIDToDevice for hidden devices
        log.debug("Trying hidden device lookup via TranslateUIDToDevice")
         
         var translateAddress = AudioObjectPropertyAddress(
             mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var deviceID: AudioDeviceID = 0
         var translateSize = UInt32(MemoryLayout<AudioDeviceID>.size)
         
         let cfUid: CFString = DRIVER_DEVICE_UID as CFString
         let uidPtr = Unmanaged.passUnretained(cfUid).toOpaque()
         
         let translateStatus = AudioObjectGetPropertyData(
             AudioObjectID(kAudioObjectSystemObject),
             &translateAddress,
             UInt32(MemoryLayout<CFString>.size),
             uidPtr,
             &translateSize,
             &deviceID
         )
         
         if translateStatus == noErr, deviceID != 0 {
             log.info("Found hidden driver via TranslateUIDToDevice: deviceID=\(deviceID)")
             return deviceID
         }
         
         log.warning("Equaliser driver not found. Expected UID: \(DRIVER_DEVICE_UID)")
         return nil
    }
    
    /// Reads the current device name from the driver
    /// - Returns: The device name if successful, nil otherwise
    public func getDeviceName() -> String? {
        deviceID = findDriverDevice()
        
        guard let deviceID = deviceID else {
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
            log.error("Failed to get device name: \(status)")
            return nil
        }
        
        return nameRef?.takeRetainedValue() as String?
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
