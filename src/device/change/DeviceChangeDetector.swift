// DeviceChangeDetector.swift
// Pure functions for detecting audio device changes

import Foundation

/// Detects audio device changes for headphone plug/unplug events.
/// Pure functions - no side effects, fully testable.
enum DeviceChangeDetector {
    
    // MARK: - Built-in Device Detection
    
    /// Detects built-in device additions and removals.
    /// Used for Apple Silicon headphone detection (device count changes).
    ///
    /// - Parameters:
    ///   - previousUIDs: Previously known built-in device UIDs
    ///   - currentDevices: Current list of all output devices
    /// - Returns: Tuple of (added devices, removed UIDs)
    static func diffBuiltInDevices(
        previousUIDs: Set<String>,
        currentDevices: [AudioDevice]
    ) -> (added: [AudioDevice], removed: Set<String>) {
        // Get current built-in device UIDs
        let currentBuiltInUIDs = Set(currentDevices.filter { $0.isBuiltIn }.map { $0.uid })
        
        // Calculate diffs
        let addedUIDs = currentBuiltInUIDs.subtracting(previousUIDs)
        let removedUIDs = previousUIDs.subtracting(currentBuiltInUIDs)
        
        // Get full device info for added devices
        let addedDevices = currentDevices.filter { addedUIDs.contains($0.uid) }
        
        return (addedDevices, removedUIDs)
    }
    
    /// Determines if a built-in device addition should trigger headphone switch.
    /// Only exactly ONE built-in device added indicates headphones plugged in.
    /// Multiple additions are ignored (could be aggregate device creation, etc).
    ///
    /// - Parameter addedDevices: List of added built-in devices
    /// - Returns: The single added device if exactly one, nil otherwise
    static func shouldTriggerHeadphoneSwitch(addedDevices: [AudioDevice]) -> AudioDevice? {
        // Only trigger if exactly one built-in device was added
        // Multiple additions could be aggregate device creation, USB hub, etc.
        guard addedDevices.count == 1,
              let device = addedDevices.first,
              device.isBuiltIn else {
            return nil
        }
        return device
    }
    
    // MARK: - Missing Device Detection
    
    /// Checks if a device is currently available.
    /// Uses the provided device list (not CoreAudio) to avoid stale UID crashes.
    ///
    /// - Parameters:
    ///   - uid: Device UID to check
    ///   - availableDevices: List of currently available devices
    /// - Returns: true if device exists in available list
    static func deviceExists(
        uid: String?,
        in availableDevices: [AudioDevice]
    ) -> Bool {
        guard let uid = uid else { return false }
        return availableDevices.contains { $0.uid == uid }
    }
}