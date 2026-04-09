// HeadphoneSwitchPolicy.swift
// Pure functions for determining headphone switch behaviour

import Foundation

/// Determines if headphone auto-switch should occur.
/// Pure function - no side effects, fully testable.
enum HeadphoneSwitchPolicy {
    
    /// Determines whether the app should switch to a new built-in device
    /// when headphones are plugged in.
    ///
    /// Switching only occurs when:
    /// - Not in manual mode (respects user's manual device selection)
    /// - Not currently reconfiguring the audio pipeline
    /// - Current output device is built-in (never steals from USB/Bluetooth/HDMI)
    ///
    /// - Parameters:
    ///   - currentOutput: The currently selected output device (if any)
    ///   - newDevice: The newly detected built-in device (headphones)
    ///   - isInManualMode: Whether manual mode is enabled
    ///   - isReconfiguring: Whether audio pipeline is being reconfigured
    /// - Returns: true if switch should occur, false otherwise
    static func shouldSwitch(
        currentOutput: AudioDevice?,
        newDevice: AudioDevice,
        isInManualMode: Bool,
        isReconfiguring: Bool
    ) -> Bool {
        // Don't switch in manual mode - user has explicit control
        guard !isInManualMode else { return false }
        
        // Don't switch during reconfiguration - could cause race conditions
        guard !isReconfiguring else { return false }
        
        // Only switch if current output is built-in
        // This matches macOS behaviour: only auto-switch from speakers to headphones,
        // never steal from USB/Bluetooth/HDMI
        guard let current = currentOutput,
              current.isBuiltIn else { return false }
        
        return true
    }
}