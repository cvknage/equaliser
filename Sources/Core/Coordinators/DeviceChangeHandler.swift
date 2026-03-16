// DeviceChangeHandler.swift
// Handles device connect/disconnect events

import Combine
import Foundation
import OSLog

/// Handles device enumeration changes (connect/disconnect).
/// Manages output device history for automatic reconnection when devices disconnect.
@MainActor
final class DeviceChangeHandler {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceChangeHandler")
    private let deviceManager: DeviceManager
    
    /// Stack of previous output device UIDs (most recent first).
    /// Used to restore output when current device disconnects.
    /// Only used in automatic mode. Never contains the driver UID.
    private var outputDeviceHistory: [String] = []
    
    /// Callback invoked when device list changes and current device is disconnected.
    /// Parameter is a replacement device, or nil if no replacement found.
    var onDeviceDisconnected: ((AudioDevice?) -> Void)?
    
    /// Callback to check if routing is in progress.
    var isReconfiguring: (() -> Bool)?
    
    /// Callback to check if in manual mode.
    var isManualMode: (() -> Bool)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        
        // Observe output device list changes
        deviceManager.$outputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleOutputDevicesChanged()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - History Management
    
    /// Adds a device to history (removes older occurrences first).
    /// - Parameter uid: The device UID to add
    func addToHistory(_ uid: String) {
        outputDeviceHistory.removeAll { $0 == uid }
        outputDeviceHistory.insert(uid, at: 0)
        if outputDeviceHistory.count > 10 {
            outputDeviceHistory.removeLast()
        }
        logger.debug("Added to output history, count: \(self.outputDeviceHistory.count)")
    }
    
    /// Clears history (e.g., when switching to manual mode).
    func clearHistory() {
        outputDeviceHistory.removeAll()
    }
    
    // MARK: - Device Change Handling
    
    private func handleOutputDevicesChanged() {
        // In manual mode, let user handle device selection
        guard isManualMode?() == false else {
            logger.debug("Manual mode: ignoring device list change")
            return
        }
        
        // Don't react during reconfiguration
        guard isReconfiguring?() == false else {
            logger.debug("Reconfiguring: ignoring device list change")
            return
        }
        
        // Callback will handle the rest
        onDeviceDisconnected?(nil)
    }
    
    /// Finds a replacement device from history or available devices.
    /// - Parameter currentUID: The currently selected device UID (may be disconnected)
    /// - Returns: A replacement device, or nil if current device is still valid
    func findReplacementDevice(currentUID: String?) -> AudioDevice? {
        // Check if current device still exists
        if let uid = currentUID,
           deviceManager.outputDevices.contains(where: { $0.uid == uid }) {
            return nil // Current device still valid
        }
        
        // Search history for first available device
        for uid in outputDeviceHistory {
            if let device = deviceManager.device(forUID: uid),
               !device.isVirtual {
                outputDeviceHistory.removeAll { $0 == uid }
                return device
            }
        }
        
        // Fall back to macOS default
        if let newDefault = deviceManager.defaultOutputDevice(),
           newDefault.uid != DRIVER_DEVICE_UID,
           !newDefault.isVirtual {
            return newDefault
        }
        
        // Last resort: first non-virtual output
        return deviceManager.outputDevices.first(where: { !$0.isVirtual })
    }
    
    /// Checks if the currently selected device still exists.
    /// - Parameter currentUID: The currently selected device UID
    /// - Returns: true if the device still exists in the device list
    func deviceStillExists(_ currentUID: String?) -> Bool {
        guard let uid = currentUID else { return false }
        return deviceManager.outputDevices.contains { $0.uid == uid }
    }
}