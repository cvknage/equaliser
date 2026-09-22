// DevicePresetMap.swift
// Maps output devices to the EQ preset last used on them

import Foundation

/// Maps output device UIDs to EQ preset names.
/// Pure model - no I/O, fully testable.
/// Used for automatic per-device EQ preset switching.
struct DevicePresetMap: Codable, Sendable {

    // MARK: - Properties

    /// Device UID → preset name entries.
    private(set) var entries: [String: String]

    // MARK: - Initialization

    init(entries: [String: String] = [:]) {
        self.entries = entries
    }

    // MARK: - Lookup

    /// Returns the preset name mapped to a device, if any.
    /// - Parameter uid: The device UID
    /// - Returns: The mapped preset name, or nil
    func presetFor(device uid: String) -> String? {
        entries[uid]
    }

    // MARK: - Mutation

    /// Records the preset used on a device.
    /// - Parameters:
    ///   - uid: The device UID
    ///   - presetName: The preset name to associate
    mutating func record(device uid: String, presetName: String) {
        entries[uid] = presetName
    }

    /// Removes the mapping for a device, if any.
    /// - Parameter uid: The device UID
    mutating func remove(device uid: String) {
        entries.removeValue(forKey: uid)
    }

    /// Removes mappings whose preset no longer exists.
    /// Keeps the mapping self-healing when presets are deleted.
    /// - Parameter availablePresetNames: The set of currently valid preset names
    mutating func prune(invalidFor availablePresetNames: Set<String>) {
        entries = entries.filter { availablePresetNames.contains($0.value) }
    }
}