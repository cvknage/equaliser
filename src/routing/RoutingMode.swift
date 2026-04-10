// RoutingMode.swift
// Strategy for mode-specific device resolution and event handling

import CoreAudio
import Foundation

/// Result of resolving devices for a routing mode.
enum DeviceResolution {
    /// Devices resolved successfully.
    case resolved(inputUID: String, outputUID: String)
    /// Resolution failed with an error message.
    case failed(String)
}

/// Protocol for routing mode behaviour.
/// Encapsulates mode-specific device resolution and event handling decisions.
@MainActor
protocol RoutingMode {
    /// Whether this mode uses manual device selection.
    var isManual: Bool { get }

    /// Whether this mode requires the driver to be visible before routing.
    var requiresDriverVisibility: Bool { get }

    /// Whether this mode should sync driver sample rate to output device.
    var requiresSampleRateSync: Bool { get }

    /// Whether this mode should handle system default change events.
    var handlesSystemDefaultChanges: Bool { get }

    /// Whether this mode should handle built-in device change events.
    var handlesBuiltInDeviceChanges: Bool { get }

    /// Whether this mode needs microphone permission before routing.
    var needsMicPermission: Bool { get }

    /// Resolves input/output device UIDs for this mode.
    /// - Parameters:
    ///   - selectedInputDeviceID: Currently selected input device UID
    ///   - selectedOutputDeviceID: Currently selected output device UID
    ///   - deviceProvider: Device lookup and enumeration
    ///   - systemDefaultObserver: System default output observer
    ///   - driverAccess: Driver access for visibility checks
    ///   - captureMode: Capture mode preference (automatic mode only)
    func resolveDevices(
        selectedInputDeviceID: String?,
        selectedOutputDeviceID: String?,
        deviceProvider: DeviceProviding,
        systemDefaultObserver: SystemDefaultObserving,
        driverAccess: DriverAccessing,
        captureMode: CaptureMode
    ) -> DeviceResolution
}