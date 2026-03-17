// DriverDeviceDiscovering.swift
// Protocol for driver device discovery

import Foundation
import CoreAudio

/// Protocol for driver device discovery and caching.
@MainActor
protocol DriverDeviceDiscovering: ObservableObject {
    /// The cached device ID for the driver
    var deviceID: AudioObjectID? { get }
    
    /// Checks if driver is currently visible in CoreAudio
    func isDriverVisible() -> Bool
    
    /// Finds the driver device with retry logic for CoreAudio reconfiguration delays
    func findDriverDeviceWithRetry(initialDelayMs: Int, maxAttempts: Int) async -> AudioDeviceID?
    
    /// Refreshes and returns the cached device ID
    func refreshDeviceID() -> AudioObjectID?
    
    /// Sets the driver as the system default output device
    func setAsDefaultOutputDevice() -> Bool
    
    /// Restores system default to built-in speakers
    func restoreToBuiltInSpeakers() -> Bool
}