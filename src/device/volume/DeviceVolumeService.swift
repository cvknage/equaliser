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
    private nonisolated(unsafe) var deviceVolumePropertySelectors: [AudioDeviceID: AudioObjectPropertySelector] = [:]
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

        return status == noErr
    }

    /// Nonisolated version for background queue volume forwarding.
    @discardableResult
    nonisolated func setVirtualMasterVolumeNonisolated(deviceID: AudioDeviceID, volume: Float) -> Bool {
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

        return status == noErr
    }
    
    // MARK: - Device-Level Volume
    
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        // 1. Try VolumeScalar on main element
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

        // 2. Try VirtualMasterVolume (common for real audio output devices)
        if let vmv = getVirtualMasterVolume(deviceID: deviceID) {
            return vmv
        }

        // 3. Try per-channel volume (Bluetooth devices)
        if let channelVolume = getDeviceVolumeOnChannels(deviceID: deviceID) {
            return channelVolume
        }

        // No volume method worked - this is unexpected
        logger.warning("getDeviceVolumeScalar: No volume property available for device \(deviceID)")
        return nil
    }
    
    @discardableResult
    nonisolated func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
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
        if setVirtualMasterVolumeNonisolated(deviceID: deviceID, volume: volume) {
            return true
        }

        // Fallback to per-channel volume (Bluetooth devices)
        return setDeviceVolumeOnChannelsNonisolated(deviceID: deviceID, volume: volume)
    }

    // MARK: - Per-Channel Volume Control

    /// Sets volume on individual channels (left/right) instead of master.
    /// Some Bluetooth devices only support channel-level volume control, not master volume.
    /// Uses kAudioDevicePropertyPreferredChannelsForStereo to determine actual channel numbers.
    @discardableResult
    private func setDeviceVolumeOnChannels(deviceID: AudioDeviceID, volume: Float) -> Bool {
        // Get preferred channels for stereo
        var preferredAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var preferredSize = UInt32(MemoryLayout<UInt32>.size * 2)
        var channels: [UInt32] = [1, 2]  // Default left/right

        let getStatus = AudioObjectGetPropertyData(deviceID, &preferredAddress, 0, nil, &preferredSize, &channels)
        if getStatus != noErr {
            channels = [1, 2]
        }

        // Set volume on each channel (skip element 0 which is invalid)
        var success = false
        for channel in channels where channel != 0 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(channel)
            )

            var volumeValue = volume
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volumeValue) == noErr {
                success = true
            }
        }

        return success
    }

    /// Nonisolated version for background queue volume forwarding.
    @discardableResult
    nonisolated private func setDeviceVolumeOnChannelsNonisolated(deviceID: AudioDeviceID, volume: Float) -> Bool {
        // Get preferred channels for stereo
        var preferredAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var preferredSize = UInt32(MemoryLayout<UInt32>.size * 2)
        var channels: [UInt32] = [1, 2]  // Default left/right

        let getStatus = AudioObjectGetPropertyData(deviceID, &preferredAddress, 0, nil, &preferredSize, &channels)
        if getStatus != noErr {
            channels = [1, 2]
        }

        // Set volume on each channel (skip element 0 which is invalid)
        var success = false
        for channel in channels where channel != 0 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(channel)
            )

            var volumeValue = volume
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volumeValue) == noErr {
                success = true
            }
        }

        return success
    }

    /// Gets volume from per-channel control (for Bluetooth devices).
    /// Returns average of left/right channel volumes, or nil if not supported.
    private func getDeviceVolumeOnChannels(deviceID: AudioDeviceID) -> Float? {
        // Get preferred channels for stereo
        var preferredAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var preferredSize = UInt32(MemoryLayout<UInt32>.size * 2)
        var channels: [UInt32] = [0, 0]

        guard AudioObjectGetPropertyData(deviceID, &preferredAddress, 0, nil, &preferredSize, &channels) == noErr else {
            return nil
        }

        // Read volume from each channel and average
        var totalVolume: Float = 0
        var channelCount: Int = 0

        for channel in channels where channel != 0 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(channel)
            )

            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)

            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
                totalVolume += volume
                channelCount += 1
            }
        }

        guard channelCount > 0 else { return nil }
        return totalVolume / Float(channelCount)
    }

    // MARK: - Volume Observation
    
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void) {
        // Try VolumeScalar first (works for most devices)
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

        if status == noErr {
            deviceVolumePropertySelectors[deviceID] = kAudioDevicePropertyVolumeScalar
            logger.info("observeDeviceVolumeChanges: Registered VolumeScalar listener on device \(deviceID)")
            return
        }

        // VolumeScalar failed, try VirtualMasterVolume (Bluetooth devices like AirPods)
        logger.debug("observeDeviceVolumeChanges: VolumeScalar not available on device \(deviceID), trying VirtualMasterVolume")

        address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume
        let vmvStatus = AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, block)

        if vmvStatus == noErr {
            deviceVolumePropertySelectors[deviceID] = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume
            logger.info("observeDeviceVolumeChanges: Registered VirtualMasterVolume listener on device \(deviceID)")
        } else {
            // Both registrations failed - clean up the block
            deviceVolumeListenerBlocks.removeValue(forKey: deviceID)
            logger.error("observeDeviceVolumeChanges: Failed to register listener on device \(deviceID): VolumeScalar error \(status), VirtualMasterVolume error \(vmvStatus)")
        }
    }
    
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID) {
        guard let block = deviceVolumeListenerBlocks.removeValue(forKey: deviceID) else { return }

        let selector = deviceVolumePropertySelectors.removeValue(forKey: deviceID) ?? kAudioDevicePropertyVolumeScalar

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
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