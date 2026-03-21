// DeviceChangeCoordinator.swift
// Handles device enumeration change events and history management

import Combine
import CoreAudio
import Foundation
import OSLog

/// Coordinates device change events from DeviceEnumerationService.
/// Manages output device history and emits events for parent coordinator.
///
/// ## Responsibilities
/// - Subscribe to DeviceEnumerationService change events
/// - Manage OutputDeviceHistory for reconnection
/// - Handle headphone detection (built-in device changes)
/// - Report missing output devices
/// - Manage jack connection listener lifecycle (Intel Macs)
///
/// ## Usage
/// The parent coordinator sets callback handlers:
/// ```swift
/// deviceChangeCoordinator.onBuiltInDeviceAdded = { [weak self] device in
///     self?.handleHeadphonesPluggedIn(device)
/// }
/// ```
@MainActor
final class DeviceChangeCoordinator: ObservableObject {
    
    // MARK: - Event Callbacks
    
    /// Called when headphones are plugged in (built-in device added on Apple Silicon).
    /// Parent coordinator should switch output to the new device if appropriate.
    var onBuiltInDeviceAdded: ((AudioDevice) -> Void)?
    
    /// Called when headphones are unplugged (built-in devices removed on Apple Silicon).
    /// Parent coordinator should clear missing device tracking.
    var onBuiltInDevicesRemoved: (() -> Void)?
    
    /// Called when the currently selected output device goes missing.
    /// Parent coordinator should find a replacement device.
    var onSelectedOutputMissing: ((String) -> Void)?
    
    // MARK: - Dependencies
    
    private let deviceEnumerator: DeviceEnumerationService
    
    // MARK: - State
    
    /// Manages history of output devices for restoration on disconnect.
    /// Only used in automatic mode - clears when switching to manual mode.
    let outputDeviceHistory = OutputDeviceHistory()
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceChangeCoordinator")
    
    // MARK: - Initialization
    
    /// Creates a new device change coordinator.
    /// - Parameter deviceEnumerator: The enumeration service to subscribe to
    init(deviceEnumerator: DeviceEnumerationService) {
        self.deviceEnumerator = deviceEnumerator
        setupEventSubscription()
    }
    
    // MARK: - Public Methods
    
    /// Clears missing device tracking.
    /// Called when device is restored or headphones unplugged.
    func clearMissingTracking() {
        deviceEnumerator.clearMissingTracking()
    }
    
    /// Sets up jack connection listener for Intel Mac headphone detection.
    /// Has no effect on Apple Silicon (uses device enumeration changes instead).
    /// - Parameter deviceID: The built-in audio device ID to monitor
    func setupJackConnectionListener(for deviceID: AudioDeviceID) {
        deviceEnumerator.setupJackConnectionListener(for: deviceID)
    }
    
    /// Cleans up jack connection listener.
    func cleanupJackConnectionListener() {
        deviceEnumerator.cleanupJackConnectionListener()
    }
    
    /// Finds a replacement device from history or available devices.
    /// Uses cached device list to avoid CoreAudio use-after-free.
    /// - Parameter currentUID: The currently selected device UID (may be disconnected)
    /// - Returns: A replacement device, or nil if no replacement available
    func findReplacementDevice(for currentUID: String?) -> AudioDevice? {
        // Use history-aware replacement logic
        for uid in outputDeviceHistory.devices {
            if let device = deviceEnumerator.outputDevices.first(where: { $0.uid == uid }),
               device.isValidForSelection {
                outputDeviceHistory.remove(uid)
                return device
            }
        }
        
        // Fall back to first real device
        return deviceEnumerator.outputDevices.first { $0.isRealDevice }
    }
    
    /// Adds a device to history.
    /// Called by parent coordinator when saving current output for restoration.
    /// - Parameter uid: The device UID to add
    func addToHistory(_ uid: String) {
        outputDeviceHistory.add(uid)
    }
    
    /// Clears device history.
    /// Called when switching from automatic to manual mode.
    func clearHistory() {
        outputDeviceHistory.clear()
    }
    
    /// Sets up provider callbacks on the device enumerator.
    /// These enable missing device detection.
    /// - Parameters:
    ///   - selectedOutputProvider: Returns current selected output UID
    ///   - manualModeProvider: Returns true if manual mode is enabled
    ///   - isReconfiguringProvider: Returns true if routing is reconfiguring
    func setProviders(
        selectedOutputProvider: @escaping () -> String?,
        manualModeProvider: @escaping () -> Bool,
        isReconfiguringProvider: @escaping () -> Bool
    ) {
        deviceEnumerator.selectedOutputUIDProvider = selectedOutputProvider
        deviceEnumerator.manualModeProvider = manualModeProvider
        deviceEnumerator.isReconfiguringProvider = isReconfiguringProvider
    }
    
    // MARK: - Private Methods
    
    private func setupEventSubscription() {
        deviceEnumerator.$changeEvent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleDeviceChangeEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleDeviceChangeEvent(_ event: DeviceChangeEvent) {
        switch event {
        case .builtInDeviceAdded(let device):
            logger.info("Built-in device added: '\(device.name)'")
            onBuiltInDeviceAdded?(device)
            
        case .builtInDevicesRemoved:
            logger.info("Built-in devices removed")
            clearMissingTracking()
            onBuiltInDevicesRemoved?()
            
        case .selectedOutputMissing(let uid):
            logger.info("Selected output device missing: \(uid)")
            onSelectedOutputMissing?(uid)
        }
    }
}