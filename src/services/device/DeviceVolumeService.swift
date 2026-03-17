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
    
    private nonisolated(unsafe) var deviceVolumeListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private nonisolated(unsafe) var muteListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private nonisolated(unsafe) var virtualMuteListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private let listenerQueue = DispatchQueue(label: "net.knage.equaliser.DeviceVolumeService.listener")
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceVolumeService")
    
    // MARK: - Virtual Master Volume
    
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 1.0
        var size = UInt32(MemoryLayout<Float32>.size)
        
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
            return volume
        }
        
        // Fall back to getting volume from control objects
        return getVolumeFromControlObject(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput)
    }
    
    @discardableResult
    func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var vol = volume
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &vol
        )
        
        if status == noErr {
            return true
        }
        
        // Fall back to setting volume on control objects
        return setVolumeOnControlObject(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput, volume: volume)
    }
    
    // MARK: - Device-Level Volume
    
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        // Try VolumeScalar first
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
            return volume
        }
        
        // Fallback to VirtualMasterVolume (common for real audio output devices)
        if let vmv = getVirtualMasterVolume(deviceID: deviceID) {
            logger.debug("getDeviceVolumeScalar: using VirtualMasterVolume fallback for device \(deviceID)")
            return vmv
        }
        
        logger.warning("getDeviceVolumeScalar: failed for device \(deviceID)")
        return nil
    }
    
    @discardableResult
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
        // Try VolumeScalar first
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volumeValue = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        
        if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volumeValue) == noErr {
            return true
        }
        
        // Fallback to VirtualMasterVolume (common for real audio output devices)
        logger.debug("setDeviceVolumeScalar: VolumeScalar failed for device \(deviceID), trying VirtualMasterVolume")
        return setVirtualMasterVolume(deviceID: deviceID, volume: volume)
    }
    
    // MARK: - Volume Observation
    
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            if let volume = self.getDeviceVolumeScalar(deviceID: deviceID) {
                Task { @MainActor in
                    handler(volume)
                }
            }
        }
        
        deviceVolumeListenerBlocks[deviceID] = block
        
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, block)
        
        if status != noErr {
            logger.error("observeDeviceVolumeChanges: Failed to register listener on device \(deviceID): error \(status)")
        } else {
            logger.info("observeDeviceVolumeChanges: Registered listener on device \(deviceID)")
        }
    }
    
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID) {
        guard let block = deviceVolumeListenerBlocks.removeValue(forKey: deviceID) else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, listenerQueue, block)
    }
    
    // MARK: - Mute Control
    
    func getMute(deviceID: AudioDeviceID) -> Bool? {
        // Try virtual master mute property first
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        
        // Fall back to mute control object
        return getMuteFromControlObject(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput)
    }
    
    func getDeviceMute(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        
        return muted != 0
    }
    
    @discardableResult
    func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muteValue) == noErr
    }
    
    // MARK: - Mute Observation
    
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            if let muted = self.getMute(deviceID: deviceID) {
                Task { @MainActor in
                    handler(muted)
                }
            }
        }
        
        muteListenerBlocks[deviceID] = block
        
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            listenerQueue,
            block
        )
        
        if status != noErr {
            logger.warning("Failed to observe mute changes on device \(deviceID): \(status)")
        }
    }
    
    func stopObservingMuteChanges(on deviceID: AudioDeviceID) {
        guard let block = muteListenerBlocks.removeValue(forKey: deviceID) else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &address,
            listenerQueue,
            block
        )
    }
    
    // MARK: - Private Helpers - Volume Control Objects
    
    private func getVolumeFromControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyOwnedObjects,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var qualifier = AudioClassID(kAudioVolumeControlClassID)
        var size: UInt32 = 0
        
        // Get size first
        guard AudioObjectGetPropertyDataSize(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size) == noErr else {
            return nil
        }
        
        let controlCount = Int(size) / MemoryLayout<AudioObjectID>.size
        guard controlCount > 0 else { return nil }
        
        var controls = [AudioObjectID](repeating: 0, count: controlCount)
        guard AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size, &controls) == noErr else {
            return nil
        }
        
        // Get volume from the first volume control
        for controlID in controls {
            if let volume = getVolumeFromControl(controlID: controlID) {
                return volume
            }
        }
        
        return nil
    }
    
    private func getVolumeFromControl(controlID: AudioObjectID) -> Float? {
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioLevelControlPropertyScalarValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 1.0
        var size = UInt32(MemoryLayout<Float32>.size)
        
        guard AudioObjectGetPropertyData(controlID, &volumeAddress, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        
        return volume
    }
    
    private func setVolumeOnControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, volume: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyOwnedObjects,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var qualifier = AudioClassID(kAudioVolumeControlClassID)
        var size: UInt32 = 0
        
        guard AudioObjectGetPropertyDataSize(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size) == noErr else {
            return false
        }
        
        let controlCount = Int(size) / MemoryLayout<AudioObjectID>.size
        guard controlCount > 0 else { return false }
        
        var controls = [AudioObjectID](repeating: 0, count: controlCount)
        guard AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size, &controls) == noErr else {
            return false
        }
        
        // Set volume on all volume controls
        var success = false
        for controlID in controls {
            if setVolumeOnControl(controlID: controlID, volume: volume) {
                success = true
            }
        }
        
        return success
    }
    
    private func setVolumeOnControl(controlID: AudioObjectID, volume: Float) -> Bool {
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioLevelControlPropertyScalarValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var vol = volume
        let status = AudioObjectSetPropertyData(
            controlID,
            &volumeAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &vol
        )
        
        return status == noErr
    }
    
    // MARK: - Private Helpers - Mute Control Objects
    
    private func getMuteFromControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyOwnedObjects,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var qualifier = AudioClassID(kAudioMuteControlClassID)
        var size: UInt32 = 0
        
        guard AudioObjectGetPropertyDataSize(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size) == noErr else {
            return nil
        }
        
        let controlCount = Int(size) / MemoryLayout<AudioObjectID>.size
        guard controlCount > 0 else { return nil }
        
        var controls = [AudioObjectID](repeating: 0, count: controlCount)
        guard AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size, &controls) == noErr else {
            return nil
        }
        
        for controlID in controls {
            if let muted = getMuteFromControl(controlID: controlID) {
                return muted
            }
        }
        
        return nil
    }
    
    private func getMuteFromControl(controlID: AudioObjectID) -> Bool? {
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioBooleanControlPropertyValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        guard AudioObjectGetPropertyData(controlID, &muteAddress, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        
        return muted != 0
    }
}