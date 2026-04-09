// AutomaticRoutingMode.swift
// Automatic routing mode — uses Equaliser driver, derives devices from macOS default

import Foundation
import OSLog

/// Automatic routing mode: uses the Equaliser driver and derives output device from macOS default.
@MainActor
final class AutomaticRoutingMode: RoutingMode {

    let isManual = false
    let requiresDriverVisibility = true
    let requiresSampleRateSync = true
    let handlesSystemDefaultChanges = true
    let handlesBuiltInDeviceChanges = true
    let needsMicPermission = false  // Only needs permission if using HAL input capture

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AutomaticRoutingMode")

    func resolveDevices(
        selectedInputDeviceID: String?,
        selectedOutputDeviceID: String?,
        deviceProvider: DeviceProviding,
        systemDefaultObserver: SystemDefaultObserving,
        driverAccess: DriverAccessing,
        captureMode: CaptureMode
    ) -> DeviceResolution {
        // Input is always driver in automatic mode
        let inputUID = DRIVER_DEVICE_UID

        // Determine output device using pure selection logic
        let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID()
        let selection = OutputDeviceSelection.determine(
            currentSelected: selectedOutputDeviceID,
            macDefault: macDefault,
            availableDevices: deviceProvider.outputDevices
        )

        let outputUID: String
        switch selection {
        case .preserveCurrent(let uid):
            outputUID = uid
            logger.debug("Preserving selected output")
        case .useMacDefault(let uid):
            outputUID = uid
            logger.debug("Using macOS default output: \(uid)")
        case .useFallback:
            guard let fallback = deviceProvider.selectFallbackOutputDevice() else {
                return .failed("No output device available")
            }
            outputUID = fallback.uid
            logger.debug("Using fallback output: \(fallback.uid)")
        }

        return .resolved(inputUID: inputUID, outputUID: outputUID)
    }
}