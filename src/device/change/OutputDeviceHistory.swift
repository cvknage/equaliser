// OutputDeviceHistory.swift
// Manages history of output devices for automatic reconnection

import Foundation
import OSLog

/// Manages a stack of previously used output devices.
/// Used to restore output when the current device disconnects.
/// Only used in automatic mode. Never contains the driver UID.
@MainActor
final class OutputDeviceHistory {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "OutputDeviceHistory")
    
    /// Stack of previous output device UIDs (most recent first).
    private(set) var devices: [String] = []
    
    /// Maximum number of devices to keep in history.
    private let maxHistoryCount = 10
    
    // MARK: - History Management
    
    /// Adds a device to history (removes older occurrences first).
    /// - Parameter uid: The device UID to add
    func add(_ uid: String) {
        devices.removeAll { $0 == uid }
        devices.insert(uid, at: 0)
        if devices.count > maxHistoryCount {
            devices.removeLast()
        }
        logger.debug("Added to output history, count: \(self.devices.count)")
    }
    
    /// Clears history (e.g., when switching to manual mode).
    func clear() {
        devices.removeAll()
    }
    
    /// Removes a device from history.
    /// - Parameter uid: The device UID to remove
    func remove(_ uid: String) {
        devices.removeAll { $0 == uid }
    }
    
    // MARK: - Device Lookup
    
    /// Checks if the currently selected device still exists.
    /// - Parameters:
    ///   - currentUID: The currently selected device UID
    ///   - availableDevices: The list of currently available devices
    /// - Returns: true if the device still exists
    func deviceStillExists(_ currentUID: String?, in availableDevices: [AudioDevice]) -> Bool {
        guard let uid = currentUID else { return false }
        return availableDevices.contains { $0.uid == uid }
    }
    
    /// Finds a replacement device from history or available devices.
    /// Fallback order:
    /// 1. History (user's choice, only excludes driver)
    /// 2. Built-in speakers
    /// 3. Any real device
    /// - Parameters:
    ///   - currentUID: The currently selected device UID (may be disconnected)
    ///   - deviceManager: The device manager for device lookup
    /// - Returns: A replacement device, or nil if current device is still valid
    func findReplacementDevice(currentUID: String?, deviceManager: DeviceManager) -> AudioDevice? {
        // Use cached device list - never call CoreAudio with a potentially-stale UID string
        // that could reference a deallocated device (causes use-after-free crash)
        let availableDevices = deviceManager.outputDevices
        
        // 1. Current device still valid - no replacement needed
        if let uid = currentUID,
           availableDevices.contains(where: { $0.uid == uid }) {
            return nil
        }
        
        // 2. History - check against cached list (not CoreAudio)
        //    History retains UIDs for reconnection, but we only use them if device is currently available
        for uid in devices {
            if let device = availableDevices.first(where: { $0.uid == uid }),
               device.isValidForSelection {
                devices.removeAll { $0 == uid }
                return device
            }
        }
        
        // 3. Built-in speakers → any real device
        return deviceManager.selectFallbackOutputDevice()
    }
}