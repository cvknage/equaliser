// ManualRoutingMode.swift
// Manual routing mode — user-selected input and output devices

import Foundation
import OSLog

/// Manual routing mode: user explicitly selects input and output devices.
@MainActor
final class ManualRoutingMode: RoutingMode {

    let isManual = true
    let requiresDriverVisibility = false
    let requiresSampleRateSync = false
    let handlesSystemDefaultChanges = false
    let handlesBuiltInDeviceChanges = false
    let needsMicPermission = true  // Manual mode always uses HAL input capture

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "ManualRoutingMode")

    func resolveDevices(
        selectedInputDeviceID: String?,
        selectedOutputDeviceID: String?,
        deviceProvider: DeviceProviding,
        systemDefaultObserver: SystemDefaultObserving,
        driverAccess: DriverAccessing,
        captureMode: CaptureMode
    ) -> DeviceResolution {
        guard let selectedInput = selectedInputDeviceID else {
            return .failed("No input device selected")
        }
        guard let selectedOutput = selectedOutputDeviceID else {
            return .failed("No output device selected")
        }

        // Validate devices exist
        guard deviceProvider.device(forUID: selectedInput) != nil else {
            return .failed("Input device not found")
        }
        guard deviceProvider.device(forUID: selectedOutput) != nil else {
            return .failed("Output device not found")
        }

        logger.debug("Manual mode: input=\(selectedInput), output=\(selectedOutput)")
        return .resolved(inputUID: selectedInput, outputUID: selectedOutput)
    }
}