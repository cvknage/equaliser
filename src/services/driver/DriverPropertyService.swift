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
    
    private let registry: DriverDeviceRegistry
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverPropertyService")
    
    // MARK: - Initialization
    
    public init(registry: DriverDeviceRegistry) {
        self.registry = registry
    }
    
    // MARK: - Device Name
    
    @discardableResult
    public func setDeviceName(_ name: String) -> Bool {
        // Refresh device ID in case CoreAudio re-enumerated
        _ = registry.refreshDeviceID()

        guard let deviceID = registry.deviceID else {
            logger.warning("setDeviceName: driver device not found")
            return false
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
            logger.error("Failed to set device name: \(status)")
            return false
        }

        // Verify by reading back
        guard let verifiedName = getDeviceName() else {
            logger.warning("Could not verify device name after setting")
            return false
        }

        if verifiedName != name {
            logger.warning("Device name mismatch: set '\(name)', got '\(verifiedName)'")
            return false
        }

        logger.info("Device name verified: '\(name)'")

        return true
    }
    
    public func getDeviceName() -> String? {
        _ = registry.refreshDeviceID()
        
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
    
    @discardableResult
    public func setDriverSampleRate(matching targetRate: Float64) -> Float64? {
        _ = registry.refreshDeviceID()
        
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