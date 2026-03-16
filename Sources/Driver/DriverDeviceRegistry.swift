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
    /// During device reconfiguration (AirPods connect/disconnect), CoreAudio may
    /// temporarily exclude devices from enumeration.
    /// - Parameters:
    ///   - initialDelayMs: Initial delay before first attempt (default: 100ms)
    ///   - maxAttempts: Maximum number of poll attempts (default: 6)
    /// - Returns: The AudioDeviceID if found, nil otherwise.
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
    
    /// Refreshes and returns the cached device ID.
    public func refreshDeviceID() -> AudioObjectID? {
        deviceID = findDriverDevice()
        return deviceID
    }
    
    // MARK: - System Default Device
    
    /// Sets the driver as the system default output device.
    /// - Returns: true if successful, false otherwise.
    @discardableResult
    public func setAsDefaultOutputDevice() -> Bool {
        // Store the current system default BEFORE we modify it
        previousSystemDefaultDeviceID = getCurrentDefaultOutputDeviceID()
        
        // Refresh device ID in case CoreAudio re-enumerated devices
        deviceID = findDriverDevice()
        
        guard let deviceID = deviceID else {
            logger.error("Cannot set default output: driver device not found in CoreAudio")
            return false
        }
        
        // Validate device still exists and responds to queries
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
    
    /// Restores system default to a known-good device (built-in speakers).
    /// Called when the stored previous default no longer exists.
    /// - Returns: true if successful, false otherwise.
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
            logger.error("Failed to get device count: \(status)")
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
            logger.error("Failed to get device list: \(status)")
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
                        logger.info("Restored system default to built-in speakers (ID: \(deviceID))")
                        return true
                    }
                }
            }
        }
        
        logger.error("No built-in output device found to restore")
        return false
    }
    
    // MARK: - Private Methods
    
    /// Finds the Equaliser driver device by UID.
    /// - Returns: The AudioObjectID if found, nil otherwise.
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
    
    /// Validates that a device ID still exists and responds to CoreAudio queries.
    /// - Parameter deviceID: The device ID to validate.
    /// - Returns: true if device is valid and responsive.
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
    
    /// Gets the current system default output device ID.
    /// - Returns: The device ID, or nil if none set or error.
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
}