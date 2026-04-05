// Enumerating.swift
// Protocol for device enumeration services

import Foundation
import CoreAudio
import Combine

/// Protocol for audio device enumeration services.
/// Provides cached lists of audio input/output devices and device lookup.
@MainActor
protocol Enumerating: ObservableObject {
    /// Currently available input devices
    var inputDevices: [AudioDevice] { get }
    
    /// Currently available output devices
    var outputDevices: [AudioDevice] { get }
    
    /// Latest device change event (nil if no event pending)
    var changeEvent: DeviceChangeEvent? { get }
    
    /// Refreshes the device lists from CoreAudio
    func refreshDevices()

    /// Returns the device for a given UID
    func device(forUID uid: String) -> AudioDevice?
    
    /// Returns the device ID for a given UID
    func deviceID(forUID uid: String) -> AudioDeviceID?
    
    /// Returns the system default output device, excluding virtual devices
    func defaultOutputDevice() -> AudioDevice?
    
    /// Returns the current system default output device (convenience)
    func currentSystemDefaultOutputDevice() -> AudioDevice?

    /// Finds the built-in audio device among output devices.
    /// Used for headphone jack detection and data source discovery.
    func findBuiltInAudioDevice() -> AudioDevice?
    
    /// Sets up a listener for jack connection changes on the specified built-in audio device.
    /// Emits .builtInDeviceAdded/.builtInDevicesRemoved events when jack state changes (Intel Macs only).
    func setupJackConnectionListener(for deviceID: AudioDeviceID)
    
    /// Cleans up the jack connection listener.
    func cleanupJackConnectionListener()
    
    /// Clears tracking for missing selected device.
    /// Call when device is restored or headphones unplugged.
    func clearMissingTracking()

    /// Filters a name to check if device should be included in enumeration
    func shouldIncludeDevice(name: String) -> Bool
}