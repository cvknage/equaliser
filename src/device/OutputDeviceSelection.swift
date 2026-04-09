// OutputDeviceSelection.swift
// Automatic output device selection logic

import Foundation

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