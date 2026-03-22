// DriverAccessing.swift
// Protocol for driver access operations used by coordinators

import CoreAudio
import Foundation

/// Protocol for accessing driver state and operations.
/// Used to decouple coordinators from DriverManager singleton,
/// enabling dependency injection and testability.
@MainActor
protocol DriverAccessing: AnyObject {
    /// Whether the driver is installed and ready for use.
    var isReady: Bool { get }
    
    /// The driver's device ID if currently visible in CoreAudio.
    var deviceID: AudioObjectID? { get }
    
    /// Checks if the driver is currently visible in CoreAudio.
    /// - Returns: True if the driver device is visible.
    func isDriverVisible() -> Bool
    
    /// Finds the driver device with retry logic.
    /// - Parameters:
    ///   - initialDelayMs: Initial delay before first check (default 100ms)
    ///   - maxAttempts: Maximum number of retry attempts (default 6)
    /// - Returns: The driver device ID if found, nil otherwise.
    func findDriverDeviceWithRetry(
        initialDelayMs: Int,
        maxAttempts: Int
    ) async -> AudioDeviceID?
    
    /// Sets the driver's device name to reflect the output device.
    /// - Parameter name: The name to set.
    /// - Returns: Whether the operation succeeded.
    @discardableResult
    func setDeviceName(_ name: String) -> Bool
    
    /// Sets the driver sample rate to match the target rate.
    /// - Parameter targetRate: The target sample rate.
    /// - Returns: The actual sample rate set, or nil if failed.
    @discardableResult
    func setDriverSampleRate(matching targetRate: Float64) -> Float64?
    
    /// Restores the system default output to built-in speakers.
    /// - Returns: Whether the operation succeeded.
    @discardableResult
    func restoreToBuiltInSpeakers() -> Bool
}