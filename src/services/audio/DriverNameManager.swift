// DriverNameManager.swift
// Manages driver device naming with CoreAudio refresh workaround

import Foundation
import OSLog

/// Manages the Equaliser driver's display name.
///
/// The driver name is updated to reflect the current output device:
/// - Automatic mode: "{OutputDeviceName} (Equaliser)"
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
    private let deviceManager: DeviceManager
    
    private let logger = Logger(
        subsystem: "net.knage.equaliser",
        category: "DriverNameManager"
    )
    
    // MARK: - Initialization
    
    init(
        driverAccess: DriverAccessing,
        systemDefaultObserver: SystemDefaultObserver,
        deviceManager: DeviceManager
    ) {
        self.driverAccess = driverAccess
        self.systemDefaultObserver = systemDefaultObserver
        self.deviceManager = deviceManager
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
        
        let driverName = "\(outputDevice.name) (Equaliser)"
        return setDriverName(driverName, outputUID: outputUID)
    }
    
    // MARK: - Private Implementation
    
    /// Resets driver name to "Equaliser" (manual mode).
    private func resetDriverName(outputUID: String?) -> Bool {
        let success = driverAccess.setDeviceName("Equaliser")
        
        guard success, let outputUID = outputUID else {
            return success
        }
        
        // Trigger macOS Control Center refresh
        // When switching from automatic to manual mode:
        // - Driver is already default (from automatic mode)
        // - Setting driver as default again is a no-op (no notification)
        // - Toggle to output device and back to trigger CoreAudio notifications
        
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
        
        // Schedule UI refresh for 100ms later (fire-and-forget)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.systemDefaultObserver.setDriverAsDefault()
            self?.deviceManager.refreshDevices()
            self?.logger.debug("Device list refreshed after driver name reset")
        }
        
        return success
    }
    
    /// Sets driver name to reflect output device (automatic mode).
    private func setDriverName(_ name: String, outputUID: String) -> Bool {
        let success = driverAccess.setDeviceName(name)
        
        guard success, driverAccess.deviceID != nil else {
            return success
        }
        
        // Trigger macOS Control Center refresh
        // When switching devices in automatic mode:
        // - Toggle to output device to ensure CoreAudio notifications fire
        // - Then schedule driver default toggle for UI refresh
        
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
        
        // Schedule UI refresh for 100ms later (fire-and-forget)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.systemDefaultObserver.setDriverAsDefault()
            self?.deviceManager.refreshDevices()
            self?.logger.debug("Device list refreshed after driver name change to '\(name)'")
        }
        
        return success
    }
}