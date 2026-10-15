// DriverNameManager.swift
// Manages driver device naming with CoreAudio refresh workaround

import Foundation
import OSLog

/// Manages the Equaliser driver's display name.
///
/// The driver name is updated to reflect the current output device:
/// - Automatic mode: rendered from the user's `DriverNameFormat`, e.g. "Speakers (Equaliser)"
/// - Manual mode: "Equaliser"
///
/// ## CoreAudio Refresh Workaround
///
/// After renaming the driver, CoreAudio caches the old name. This manager
/// implements a workaround pattern that forces macOS to notice the change:
///
/// 1. Set driver name via CoreAudio property
/// 2. Set output device as default (triggers notification)
/// 3. After delay, set driver as default again (triggers notification)
/// 4. Refresh device list to get updated name
///
/// ## Important: Call Site Responsibility
///
/// This class only handles the UI refresh toggle (steps 2-4). The caller
/// (AudioRoutingCoordinator) is responsible for calling `setDriverAsDefault()`
/// synchronously before starting the audio pipeline to ensure correct routing.
///
/// The delay is necessary because CoreAudio notifications are asynchronous.
@MainActor
final class DriverNameManager {
    
    // MARK: - Dependencies
    
    private let driverAccess: DriverAccessing
    private let systemDefaultObserver: SystemDefaultObserver
    private let deviceProvider: DeviceProviding

    private let logger = Logger(
        subsystem: "net.knage.equaliser",
        category: "DriverNameManager"
    )

    /// Last name successfully set, to skip redundant renames.
    private var lastName: String?

    /// Last name set with the Control Center refresh toggle.
    private(set) var lastRefreshedName: String?

    /// Template for the automatic-mode name.
    var format: DriverNameFormat = .default

    /// Supplies the current preset name and EQ state for the format's tokens.
    var currentValues: (_ device: String) -> DriverNameFormat.Values = {
        DriverNameFormat.Values(device: $0, preset: nil, eqEnabled: true)
    }

    // MARK: - Initialization

    init(
        driverAccess: DriverAccessing,
        systemDefaultObserver: SystemDefaultObserver,
        deviceProvider: DeviceProviding
    ) {
        self.driverAccess = driverAccess
        self.systemDefaultObserver = systemDefaultObserver
        self.deviceProvider = deviceProvider
    }
    
    // MARK: - Public API
    
    /// Updates the driver name based on current routing state.
    ///
    /// This method is **synchronous** and returns immediately. It handles:
    /// 1. Setting the driver name
    /// 2. Triggering macOS Control Center refresh (async, scheduled)
    ///
    /// The caller must call `systemDefaultObserver.setDriverAsDefault()` synchronously
    /// after this method returns, before starting the audio pipeline.
    ///
    /// - Parameters:
    ///   - manualMode: Whether manual mode is active
    ///   - selectedOutputUID: The currently selected output device UID
    ///   - selectedOutputDevice: The output device (if available)
    /// - Returns: `true` if name was set successfully, `false` otherwise
    @discardableResult
    func updateDriverName(
        manualMode: Bool,
        selectedOutputUID: String?,
        selectedOutputDevice: AudioDevice?
    ) -> Bool {
        // Manual mode: reset to default name
        guard !manualMode else {
            return resetDriverName(outputUID: selectedOutputUID)
        }
        
        // Automatic mode: need output device and visible driver
        guard let outputUID = selectedOutputUID,
              let outputDevice = selectedOutputDevice,
              driverAccess.isDriverVisible() else {
            logger.warning("updateDriverName: cannot update - no output device or driver not visible")
            return false
        }
        
        let driverName = format.render(currentValues(outputDevice.name))
        return setDriverName(driverName, outputUID: outputUID)
    }

    /// Re-renders the name after a preset, EQ state or format change, without the
    /// default-output toggle so audio is not interrupted. System Settings shows the new
    /// name right away; Control Center keeps its cached name until the next output change.
    @discardableResult
    func refreshDriverName(selectedOutputDevice: AudioDevice?) -> Bool {
        guard let outputDevice = selectedOutputDevice, driverAccess.isDriverVisible() else { return false }
        let driverName = format.render(currentValues(outputDevice.name))
        guard driverName != lastName else { return true }
        let success = driverAccess.setDeviceName(driverName)
        if success {
            lastName = driverName
            deviceProvider.refreshDevices()
        }
        return success
    }

    // MARK: - Private Implementation
    
    /// Resets driver name to "Equaliser" (manual mode).
    private func resetDriverName(outputUID: String?) -> Bool {
        let success = driverAccess.setDeviceName("Equaliser")
        if success { lastName = "Equaliser" }
        
        guard success, let outputUID = outputUID else {
            return success
        }
        
        // Trigger macOS Control Center refresh
        // When switching from automatic to manual mode:
        // - Driver is already default (from automatic mode)
        // - Setting driver as default again is a no-op (no notification)
        // - Toggle to output device and back to trigger CoreAudio notifications
        // Note: Driver must be set as default for audio routing to work in manual mode

        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)

        // Schedule UI refresh for 100ms later (fire-and-forget)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.systemDefaultObserver.setDriverAsDefault(shortTimeout: true)
            self?.deviceProvider.refreshDevices()
            self?.logger.debug("Device list refreshed after driver name reset")
        }
        
        return success
    }
    
    /// Sets driver name to reflect output device (automatic mode).
    /// The automatic-mode name for an output device with the current format and values.
    func renderedName(for outputDevice: AudioDevice) -> String {
        format.render(currentValues(outputDevice.name))
    }

    private func setDriverName(_ name: String, outputUID: String) -> Bool {
        let success = driverAccess.setDeviceName(name)
        if success {
            lastName = name
            lastRefreshedName = name
        }
        
        guard success, driverAccess.deviceID != nil else {
            return success
        }
        
        // Trigger macOS Control Center refresh
        // When switching devices in automatic mode:
        // - Toggle to output device to ensure CoreAudio notifications fire
        // Note: setDriverAsDefault() is called by AudioRoutingCoordinator.reconfigureRouting()
        // synchronously after this method returns, before starting the pipeline.
        // We only need to refresh the device list here for the updated name.

        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)

        // Schedule UI refresh for 100ms later (fire-and-forget)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.deviceProvider.refreshDevices()
            self?.logger.debug("Device list refreshed after driver name change to '\(name)'")
        }
        
        return success
    }
}