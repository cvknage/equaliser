// SampleRateObserving.swift
// Protocol for sample rate query and observation services

import Foundation
import CoreAudio

/// Protocol for device sample rate services.
@MainActor
protocol SampleRateObserving: AnyObject {
    /// Returns the actual (running) sample rate of a device
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64?
    
    /// Returns the nominal sample rate of a device
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64?
    
    /// Observes sample rate changes on a device
    func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void)
    
    /// Stops observing sample rate changes on a device
    func stopObservingSampleRateChanges(on deviceID: AudioDeviceID)
}