// VolumeControlling.swift
// Protocol for volume and mute control services

import Foundation
import CoreAudio

/// Protocol for device volume and mute control services.
@MainActor
protocol VolumeControlling: AnyObject {
    /// Gets the virtual master volume for a device (0.0 - 1.0)
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float?

    /// Sets the virtual master volume for a device (0.0 - 1.0)
    @discardableResult
    func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool

    /// Gets the device-level volume scalar (0.0 - 1.0)
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float?

    /// Sets the device-level volume scalar (0.0 - 1.0).
    /// Nonisolated: CoreAudio calls are thread-safe, allows background queue dispatch.
    @discardableResult
    nonisolated func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool

    /// Gets the mute state for a device (via virtual master mute)
    func getMute(deviceID: AudioDeviceID) -> Bool?

    /// Gets the device-level mute state (via kAudioDevicePropertyMute)
    func getDeviceMute(deviceID: AudioDeviceID) -> Bool?

    /// Sets the mute state for a device
    @discardableResult
    func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool

    /// Observes volume changes on a device
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void)

    /// Stops observing volume changes on a device
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID)

    /// Observes mute state changes on a device
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void)

    /// Stops observing mute changes on a device
    func stopObservingMuteChanges(on deviceID: AudioDeviceID)
}