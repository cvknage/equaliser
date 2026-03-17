// DeviceEnumerating.swift
// Protocol for device enumeration services

import Foundation
import CoreAudio

/// Protocol for audio device enumeration services.
/// Provides cached lists of audio input/output devices and device lookup.
@MainActor
protocol DeviceEnumerating: ObservableObject {
    /// Currently available input devices
    var inputDevices: [AudioDevice] { get }
    
    /// Currently available output devices
    var outputDevices: [AudioDevice] { get }
    
    /// Refreshes the device lists from CoreAudio
    func refreshDevices()
    
    /// Finds a device by UID, even if hidden from enumeration
    func findDeviceByUID(_ uid: String) -> AudioDevice?
    
    /// Returns the device for a given UID
    func device(forUID uid: String) -> AudioDevice?
    
    /// Returns the device ID for a given UID
    func deviceID(forUID uid: String) -> AudioDeviceID?
    
    /// Returns the system default output device, excluding virtual devices
    func defaultOutputDevice() -> AudioDevice?
    
    /// Returns the current system default output device (convenience)
    func currentSystemDefaultOutputDevice() -> AudioDevice?
    
    /// Finds the Equaliser driver device among input devices
    func findEqualiserDriverDevice() -> AudioDevice?
    
    /// Filters a name to check if device should be included in enumeration
    func shouldIncludeDevice(name: String) -> Bool
    
    /// Selects the best fallback output device from available devices
    static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice?
}