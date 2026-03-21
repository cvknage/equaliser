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

// MARK: - Jack Connection Helper (Intel Macs)

/// Checks if a jack (headphone/audio port) is connected for a device.
/// Used on Intel Macs to detect headphone connection on built-in audio.
/// - Parameter deviceID: The audio device ID
/// - Returns: true if connected, false if disconnected, nil if property not supported
func isJackConnected(_ deviceID: AudioDeviceID) -> Bool? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyJackIsConnected,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    
    guard AudioObjectHasProperty(deviceID, &address) else {
        return nil
    }
    
    var connected: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &connected) == noErr else {
        return nil
    }
    
    return connected != 0
}