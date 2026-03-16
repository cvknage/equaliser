// SystemDefaultObserving.swift
// Protocol for observing macOS system default output device

import CoreAudio
import Foundation

/// Protocol for observing macOS system default output device changes.
/// Allows mocking in tests without real CoreAudio calls.
///
/// This protocol handles:
/// - Observing when macOS changes the default output device
/// - Setting the driver as default (with loop prevention)
/// - Restoring the previous default when the app quits
///
/// Example usage:
/// ```swift
/// class SystemDefaultObserver: SystemDefaultObserving {
///     var onSystemDefaultChanged: ((AudioDevice) -> Void)?
///     func startObserving() { /* CoreAudio setup */ }
///     func getCurrentSystemDefaultOutputUID() -> String? { /* ... */ }
///     // ...
/// }
///
/// // In tests:
/// let mockObserver = MockSystemDefaultObserver()
/// mockObserver.stubbedDefaultUID = "test-device"
/// mockObserver.simulateDefaultChange(testDevice)
/// ```
@MainActor
protocol SystemDefaultObserving: AnyObject {
    /// Whether the app is currently setting the system default (loop prevention).
    var isAppSettingSystemDefault: Bool { get }
    
    /// Callback invoked when system default changes (not caused by app).
    var onSystemDefaultChanged: ((AudioDevice) -> Void)? { get set }
    
    /// Starts observing system default output changes.
    func startObserving()
    
    /// Stops observing.
    func stopObserving()
    
    /// Gets the current system default output device UID.
    /// - Returns: The UID of the current default output device, or nil if not available.
    func getCurrentSystemDefaultOutputUID() -> String?
    
    /// Restores the system default output device to the specified UID.
    /// - Parameter uid: The UID of the device to set as default.
    /// - Returns: true if successful, false otherwise.
    @discardableResult
    func restoreSystemDefaultOutput(to uid: String) -> Bool
    
    /// Sets driver as system default with loop prevention.
    /// - Parameters:
    ///   - onSuccess: Called when driver is successfully set as default
    ///   - onFailure: Called when setting driver as default fails
    func setDriverAsDefault(onSuccess: (() -> Void)?, onFailure: (() -> Void)?)
    
    /// Clears the app-setting-default flag after a delay.
    func clearAppSettingFlagAfterDelay()
}