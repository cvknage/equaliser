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
    ///   - preferMacDefault: Prefer the macOS default over a valid current selection
    /// - Returns: Selection decision indicating which device to use
    static func determine(
        currentSelected: String?,
        macDefault: String?,
        availableDevices: [AudioDevice],
        preferMacDefault: Bool = false
    ) -> OutputDeviceSelection {
        let currentSelection = availableDevices.first {
            $0.uid == currentSelected && $0.isValidForSelection
        }.map {
            OutputDeviceSelection.preserveCurrent($0.uid)
        }
        let defaultSelection = availableDevices.first {
            $0.uid == macDefault && $0.isValidForSelection
        }.map {
            OutputDeviceSelection.useMacDefault($0.uid)
        }

        // If macOS still points to the Equaliser driver after a crash,
        // ignore it as an output destination and restore the saved output
        // if available, regardless of the startup preference.
        if preferMacDefault {
            return defaultSelection ?? currentSelection ?? .useFallback
        }
        return currentSelection ?? defaultSelection ?? .useFallback
    }
}
