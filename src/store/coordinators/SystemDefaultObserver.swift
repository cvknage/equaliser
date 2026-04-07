// SystemDefaultObserver.swift
// Observes and manages macOS system default output device

import CoreAudio
import Foundation
import OSLog

/// Observes macOS system default output device changes.
/// Manages the complexity of setting/restoring default output
/// and prevents infinite loops when the app sets the driver as default.
@MainActor
final class SystemDefaultObserver: SystemDefaultObserving {
    
    // MARK: - Properties

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "SystemDefaultObserver")
    private let deviceManager: DeviceManager

    /// Prevents infinite loop when app sets driver as default
    private(set) var isAppSettingSystemDefault = false

    /// Callback invoked when system default changes (not caused by app)
    /// Parameter is the new default output device
    var onSystemDefaultChanged: ((AudioDevice) -> Void)?

    // MARK: - Constants

    private enum Constants {
        /// Standard timeout for suppressing default change notifications (300ms).
        /// Used for normal device switches where the app sets both output and driver as default.
        static let standardSuppressTimeout: TimeInterval = 0.3
        /// Short timeout for immediate same-device restoration (50ms).
        /// Used when user clicks the same device - just need to restore driver quickly.
        static let shortSuppressTimeout: TimeInterval = 0.05
    }
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
    }
    
    // MARK: - Lifecycle
    
    /// Starts observing system default output changes.
    func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemDefaultOutputChange),
            name: .systemDefaultOutputDidChange,
            object: nil
        )
    }
    
    /// Stops observing.
    func stopObserving() {
        NotificationCenter.default.removeObserver(self, name: .systemDefaultOutputDidChange, object: nil)
    }
    
    // MARK: - System Default Management
    
    /// Gets the current system default output device UID.
    /// - Returns: The UID of the current default output device, or nil if not available.
    func getCurrentSystemDefaultOutputUID() -> String? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }
        
        // Get UID for this device
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        guard AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &uid
        ) == noErr else {
            return nil
        }
        
        guard let uidString = uid?.takeRetainedValue() as String? else {
            return nil
        }
        
        return uidString
    }
    
    /// Restores the system default output device to the specified UID.
    /// - Parameter uid: The UID of the device to set as default.
    /// - Returns: true if successful, false otherwise.
    @discardableResult
    func restoreSystemDefaultOutput(to uid: String) -> Bool {
        // Find device ID for UID
        guard let deviceID = deviceManager.deviceID(forUID: uid) else {
            logger.warning("Device not found for UID: \(uid)")
            return false
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceIDValue = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDValue
        )
        
        if status != noErr {
            logger.error("Failed to restore system default: status \(status)")
            return false
        }
        
        logger.info("Restored system default output to device with UID: \(uid)")
        return true
    }
    
    /// Sets driver as system default with loop prevention.
    /// - Parameters:
    ///   - shortTimeout: If true, use 50ms timeout instead of 300ms.
    ///       Use true for immediate same-device restoration (user clicked same device).
    ///       Use false for normal device switches (default).
    ///   - onSuccess: Called when driver is successfully set as default
    ///   - onFailure: Called when setting driver as default fails
    func setDriverAsDefault(shortTimeout: Bool = false, onSuccess: (() -> Void)? = nil, onFailure: (() -> Void)? = nil) {
        isAppSettingSystemDefault = true

        guard DriverManager.shared.setAsDefaultOutputDevice() else {
            isAppSettingSystemDefault = false
            onFailure?()
            return
        }

        // Use shorter timeout for immediate restoration (50ms vs 300ms)
        // The notification from setting driver as default typically arrives within a few milliseconds.
        // 50ms is sufficient to suppress this notification while allowing subsequent user clicks through quickly.
        let timeout: TimeInterval = shortTimeout ? Constants.shortSuppressTimeout : Constants.standardSuppressTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.isAppSettingSystemDefault = false
        }

        onSuccess?()
    }
    
    /// Clears the app-setting-default flag after a delay.
    /// Call this when setting default via another path.
    func clearAppSettingFlagAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAppSettingSystemDefault = false
        }
    }
    
    // MARK: - Notification Handler
    
    @objc private func handleSystemDefaultOutputChange() {
        // Get the new default device
        guard let newDefault = deviceManager.defaultOutputDevice() else {
            logger.warning("No default output device found")
            return
        }

        // Ignore if app is setting default (prevents feedback loop)
        // Note: The app generates notifications about BOTH the driver AND the output device
        // during reconfiguration (via restoreSystemDefaultOutput and setDriverAsDefault).
        // We must suppress ALL notifications during this window, not just driver notifications.
        guard !isAppSettingSystemDefault else {
            logger.debug("App is setting system default, ignoring notification")
            return
        }

        // Ignore if it's our driver
        guard newDefault.uid != DRIVER_DEVICE_UID else {
            logger.debug("New default is our driver, ignoring")
            return
        }

        onSystemDefaultChanged?(newDefault)
    }
}