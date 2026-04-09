// DriverPropertyAccessing.swift
// Protocol for driver property access

import Foundation
import CoreAudio

/// Protocol for driver property access (name, sample rate).
@MainActor
protocol DriverPropertyAccessing: AnyObject {
    /// The current sample rate of the driver, if known.
    var driverSampleRate: Float64? { get }
    
    /// Sets the driver's device name.
    /// - Parameter name: The name to set.
    /// - Returns: `true` if the name was set and verified, `false` otherwise.
    @discardableResult
    func setDeviceName(_ name: String) -> Bool
    
    /// Gets the driver's current device name.
    func getDeviceName() -> String?
    
    /// Sets the driver's nominal sample rate to the closest supported rate.
    /// - Parameter targetRate: The desired sample rate (e.g., from output device).
    /// - Returns: The actual rate set, or nil on failure.
    @discardableResult
    func setDriverSampleRate(matching targetRate: Float64) -> Float64?

    /// Checks if the driver supports shared memory capture.
    /// Returns true if the shared memory path property is implemented by the driver.
    /// Old driver versions don't support this property.
    func hasSharedMemoryCapability() -> Bool
}