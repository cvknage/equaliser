// DeviceConstants.swift
// Shared constants for device configuration

import Foundation

/// Sample rates supported by the Equaliser driver.
/// Must match kDevice_SampleRates in EqualiserDriver.c
public let DRIVER_SUPPORTED_SAMPLE_RATES: [Float64] = [
    8000, 16000, 24000, 44100, 48000, 88200, 96000,
    176400, 192000, 352800, 384000, 705600, 768000
]

/// Finds the closest supported sample rate to a target rate.
/// - Parameter targetRate: The desired sample rate in Hz.
/// - Returns: The closest supported rate from DRIVER_SUPPORTED_SAMPLE_RATES.
public func closestSupportedSampleRate(to targetRate: Float64) -> Float64 {
    guard let closest = DRIVER_SUPPORTED_SAMPLE_RATES.min(by: { 
        abs($0 - targetRate) < abs($1 - targetRate) 
    }) else {
        return 48000.0
    }
    return closest
}