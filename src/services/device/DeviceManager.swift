// DeviceManager.swift
// Facade for device-related services - maintains backward compatibility

import Combine
import Foundation
import CoreAudio
import OSLog

// MARK: - Notification Extension

extension Notification.Name {
    static let systemDefaultOutputDidChange = Notification.Name("net.knage.equaliser.systemDefaultOutputDidChange")
}

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
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
    
    /// Returns true if this device is the Equaliser driver.
    var isDriver: Bool {
        uid.hasPrefix("Equaliser")
    }
    
    /// Returns true if this device is valid for selection.
    /// Only excludes the driver - trust user's choices for everything else.
    var isValidForSelection: Bool {
        !isDriver
    }
    
    /// Returns true if this is a real physical device (not driver, virtual, or aggregate).
    /// Used for fallback selection when no user preference exists.
    var isRealDevice: Bool {
        !isDriver && !isVirtual && !isAggregate
    }
    
    /// Returns true if this device has built-in transport type.
    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }
}

// MARK: - Output Device Selection

/// Represents the result of automatic output device selection.
enum OutputDeviceSelection: Equatable {
    /// Use the existing selected device (it's still valid)
    case preserveCurrent(String)
    /// Use the current macOS default output device
    case useMacDefault(String)
    /// Need to find a fallback device (no valid selection available)
    case useFallback
    
    /// Determines which output device to use.
    /// Pure function — no side effects, testable with any inputs.
    ///
    /// - Parameters:
    ///   - currentSelected: Currently selected output device UID (if any)
    ///   - macDefault: Current macOS default output device UID (if any)
    ///   - availableDevices: List of available output devices
    /// - Returns: Selection decision indicating which device to use
    static func determine(
        currentSelected: String?,
        macDefault: String?,
        availableDevices: [AudioDevice]
    ) -> OutputDeviceSelection {
        // If current selection exists and isn't the driver, preserve it
        if let current = currentSelected,
           let device = availableDevices.first(where: { $0.uid == current }),
           device.isValidForSelection {
            return .preserveCurrent(current)
        }
        
        // If macOS default exists and isn't the driver, use it
        if let defaultUID = macDefault,
           let device = availableDevices.first(where: { $0.uid == defaultUID }),
           device.isValidForSelection {
            return .useMacDefault(defaultUID)
        }
        
        // Otherwise need fallback
        return .useFallback
    }
}

// MARK: - Device Manager Facade

/// Facade for device-related services.
/// Maintains backward compatibility while delegating to specialised services.
@MainActor
final class DeviceManager: ObservableObject {

    // MARK: - Services

    /// Device enumeration service
    let enumerator: DeviceEnumerationService

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
        enumerator: DeviceEnumerationService? = nil,
        volume: VolumeControlling? = nil,
        sampleRate: SampleRateObserving? = nil,
        driverAccess: DriverAccessing? = nil
    ) {
        // Create default services if not provided
        // Pass driverAccess to enable driver device lookup without TCC permission
        let resolvedDriverAccess = driverAccess ?? DriverManager.shared
        let newEnumerator = enumerator ?? DeviceEnumerationService(driverAccess: resolvedDriverAccess)
        self.enumerator = newEnumerator
        self.volume = volume ?? DeviceVolumeService()
        self.sampleRate = sampleRate ?? DeviceSampleRateService()
        
        // Populate synchronously - ensures inputDevices/outputDevices are ready immediately after init.
        // DeviceEnumerationService.init() calls refreshDevices() synchronously.
        // We're on MainActor, so synchronous access is safe.
        // Must use local variable since self.enumerator isn't set yet.
        self.inputDevices = newEnumerator.inputDevices
        self.outputDevices = newEnumerator.outputDevices
        
        // Set up async updates for future CoreAudio callbacks (which fire on background threads)
        self.enumerator.$inputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$inputDevices)
        
        self.enumerator.$outputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$outputDevices)
    }
    
    // MARK: - Device Enumeration (pass-through)

    func refreshDevices() {
        enumerator.refreshDevices()
    }

    /// Enumerates input devices only.
    /// May trigger TCC permission dialog for microphone access.
    /// Should be called after microphone permission is granted or when switching to manual mode.
    func enumerateInputDevices() {
        enumerator.refreshInputDevices()
    }
    
    func shouldIncludeDevice(name: String) -> Bool {
        enumerator.shouldIncludeDevice(name: name)
    }

    func device(forUID uid: String) -> AudioDevice? {
        enumerator.device(forUID: uid)
    }
    
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        enumerator.deviceID(forUID: uid)
    }
    
    func findBlackHoleDevice() -> AudioDevice? {
        enumerator.findBlackHoleDevice()
    }
    
    func defaultOutputDevice() -> AudioDevice? {
        enumerator.defaultOutputDevice()
    }
    
    func currentSystemDefaultOutputDevice() -> AudioDevice? {
        enumerator.currentSystemDefaultOutputDevice()
    }
    
    // MARK: - Device Selection
    
    /// Finds a suitable fallback output device.
    /// Order: built-in speakers → any real device
    /// - Parameter excludeUID: Optional UID to exclude from selection
    /// - Returns: A valid fallback device, or nil if none available
    func selectFallbackOutputDevice(excluding excludeUID: String? = nil) -> AudioDevice? {
        // First: built-in speakers (most common fallback)
        let builtIn = outputDevices.first { device in
            device.isBuiltIn && device.isRealDevice && device.uid != excludeUID
        }
        if let builtIn = builtIn {
            return builtIn
        }
        
        // Last resort: any real device
        return outputDevices.first { device in
            device.isRealDevice && device.uid != excludeUID
        }
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
    
    // MARK: - Device Change Events
    
    /// Publisher for device change events.
    /// Emits when built-in devices are added/removed or selected device goes missing.
    var changeEventPublisher: AnyPublisher<DeviceChangeEvent?, Never> {
        enumerator.$changeEvent.eraseToAnyPublisher()
    }
    
    /// Sets the closure that provides the current selected output UID.
    /// Used for missing device detection.
    func setSelectedOutputUIDProvider(_ provider: @escaping () -> String?) {
        enumerator.selectedOutputUIDProvider = provider
    }
    
    /// Sets the closure that indicates if manual mode is enabled.
    /// When true, device change events are not emitted.
    func setManualModeProvider(_ provider: @escaping () -> Bool) {
        enumerator.manualModeProvider = provider
    }
    
    /// Sets the closure that indicates if routing is reconfiguring.
    /// When true, device change events are not emitted.
    func setReconfiguringProvider(_ provider: @escaping () -> Bool) {
        enumerator.isReconfiguringProvider = provider
    }
    
    /// Clears tracking for missing selected device.
    /// Call when device is restored or headphones unplugged.
    func clearMissingTracking() {
        enumerator.clearMissingTracking()
    }
}