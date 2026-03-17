// DeviceManager.swift
// Facade for device-related services - maintains backward compatibility

import Combine
import Foundation
import CoreAudio
import os.log

// MARK: - Notification Extension

extension Notification.Name {
    static let systemDefaultOutputDidChange = Notification.Name("net.knage.equaliser.systemDefaultOutputDidChange")
}

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool
    let transportType: UInt32

    var displayName: String { name }
    
    /// Returns true if this device is a virtual device (not physical hardware).
    /// Uses transport type when available, falls back to UID prefix for known virtual drivers.
    var isVirtual: Bool {
        // Primary: Check transport type
        if transportType == kAudioDeviceTransportTypeVirtual {
            return true
        }
        // Fallback: Known virtual device UIDs (for drivers that don't set transport type)
        return uid.hasPrefix("Equaliser") || uid.hasPrefix("BlackHole")
    }
    
    /// Returns true if this device is an aggregate or multi-output device.
    /// Uses CoreAudio transport type for reliable detection.
    var isAggregate: Bool {
        transportType == kAudioDeviceTransportTypeAggregate
    }
}

// MARK: - Device Manager Facade

/// Facade for device-related services.
/// Maintains backward compatibility while delegating to specialised services.
@MainActor
final class DeviceManager: ObservableObject {
    
    // MARK: - Services
    
    /// Device enumeration service (internal for Combine forwarding)
    private let _enumerator: DeviceEnumerator
    
    /// Device enumeration service
    var enumerator: any DeviceEnumerating { _enumerator }
    
    /// Volume and mute control service
    let volume: VolumeControlling
    
    /// Sample rate service
    let sampleRate: SampleRateObserving
    
    // MARK: - Published Properties (forwarded from enumerator)
    
    /// Currently available input devices
    @Published var inputDevices: [AudioDevice] = []
    
    /// Currently available output devices
    @Published var outputDevices: [AudioDevice] = []
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceManager")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        enumerator: DeviceEnumerator? = nil,
        volume: VolumeControlling? = nil,
        sampleRate: SampleRateObserving? = nil
    ) {
        // Create default services if not provided
        self._enumerator = enumerator ?? DeviceEnumerator()
        self.volume = volume ?? DeviceVolumeService()
        self.sampleRate = sampleRate ?? DeviceSampleRateService()
        
        // Forward published properties from enumerator for SwiftUI
        self._enumerator.$inputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$inputDevices)
        
        self._enumerator.$outputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$outputDevices)
    }
    
    // MARK: - Device Enumeration (pass-through)
    
    func refreshDevices() {
        (enumerator as? DeviceEnumerator)?.refreshDevices()
    }
    
    func shouldIncludeDevice(name: String) -> Bool {
        (enumerator as? DeviceEnumerator)?.shouldIncludeDevice(name: name) ?? true
    }
    
    func findDeviceByUID(_ uid: String) -> AudioDevice? {
        enumerator.findDeviceByUID(uid)
    }
    
    func device(forUID uid: String) -> AudioDevice? {
        enumerator.device(forUID: uid)
    }
    
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        enumerator.deviceID(forUID: uid)
    }
    
    func findEqualiserDriverDevice() -> AudioDevice? {
        enumerator.findEqualiserDriverDevice()
    }
    
    func findBlackHoleDevice() -> AudioDevice? {
        (enumerator as? DeviceEnumerator)?.findBlackHoleDevice()
    }
    
    func bestInputDeviceForEQ() -> AudioDevice? {
        (enumerator as? DeviceEnumerator)?.bestInputDeviceForEQ()
    }
    
    func defaultOutputDevice() -> AudioDevice? {
        enumerator.defaultOutputDevice()
    }
    
    func currentSystemDefaultOutputDevice() -> AudioDevice? {
        enumerator.currentSystemDefaultOutputDevice()
    }
    
    static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice? {
        DeviceEnumerator.selectFallbackOutputDevice(from: devices)
    }
    
    // MARK: - Volume Control (pass-through)
    
    func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float? {
        volume.getVirtualMasterVolume(deviceID: deviceID)
    }
    
    @discardableResult
    func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool {
        self.volume.setVirtualMasterVolume(deviceID: deviceID, volume: volume)
    }
    
    func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        volume.getDeviceVolumeScalar(deviceID: deviceID)
    }
    
    @discardableResult
    func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
        self.volume.setDeviceVolumeScalar(deviceID: deviceID, volume: volume)
    }
    
    func getMute(deviceID: AudioDeviceID) -> Bool? {
        volume.getMute(deviceID: deviceID)
    }
    
    func getDeviceMute(deviceID: AudioDeviceID) -> Bool? {
        volume.getDeviceMute(deviceID: deviceID)
    }
    
    @discardableResult
    func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        volume.setDeviceMute(deviceID: deviceID, muted: muted)
    }
    
    func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void) {
        volume.observeDeviceVolumeChanges(deviceID: deviceID, handler: handler)
    }
    
    func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID) {
        volume.stopObservingDeviceVolumeChanges(deviceID: deviceID)
    }
    
    func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void) {
        volume.observeMuteChanges(on: deviceID, handler: handler)
    }
    
    func stopObservingMuteChanges(on deviceID: AudioDeviceID) {
        volume.stopObservingMuteChanges(on: deviceID)
    }
    
    // MARK: - Sample Rate (pass-through)
    
    func getActualSampleRate(deviceID: AudioDeviceID) -> Float64? {
        sampleRate.getActualSampleRate(deviceID: deviceID)
    }
    
    func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64? {
        sampleRate.getNominalSampleRate(deviceID: deviceID)
    }
    
    func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void) {
        sampleRate.observeSampleRateChanges(on: deviceID, handler: handler)
    }
    
    func stopObservingSampleRateChanges(on deviceID: AudioDeviceID) {
        sampleRate.stopObservingSampleRateChanges(on: deviceID)
    }
}