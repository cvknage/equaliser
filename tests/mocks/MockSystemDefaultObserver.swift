@testable import Equaliser
import CoreAudio
import Foundation

/// Mock system default observer for testing.
/// Provides controllable device behavior without real CoreAudio calls.
@MainActor
final class MockSystemDefaultObserver: SystemDefaultObserving {
    
    // MARK: - SystemDefaultObserving
    
    var isAppSettingSystemDefault = false
    
    var onSystemDefaultChanged: ((AudioDevice) -> Void)?
    
    func startObserving() {
        startObservingCallCount += 1
    }
    
    func stopObserving() {
        stopObservingCallCount += 1
    }
    
    func getCurrentSystemDefaultOutputUID() -> String? {
        getCurrentSystemDefaultOutputUIDCallCount += 1
        return stubbedDefaultUID
    }
    
    func restoreSystemDefaultOutput(to uid: String) -> Bool {
        restoreSystemDefaultOutputCallCount += 1
        lastRestoredUID = uid
        return stubbedRestoreSuccess
    }
    
    func setDriverAsDefault(onSuccess: (() -> Void)?, onFailure: (() -> Void)?) {
        setDriverAsDefaultCallCount += 1
        if stubbedSetDriverAsDefaultSuccess {
            onSuccess?()
        } else {
            onFailure?()
        }
    }
    
    func clearAppSettingFlagAfterDelay() {
        clearAppSettingFlagAfterDelayCallCount += 1
    }
    
    // MARK: - Test Helpers
    
    /// Number of times startObserving() was called.
    var startObservingCallCount = 0
    
    /// Number of times stopObserving() was called.
    var stopObservingCallCount = 0
    
    /// Number of times getCurrentSystemDefaultOutputUID() was called.
    var getCurrentSystemDefaultOutputUIDCallCount = 0
    
    /// Number of times restoreSystemDefaultOutput(to:) was called.
    var restoreSystemDefaultOutputCallCount = 0
    
    /// Number of times setDriverAsDefault was called.
    var setDriverAsDefaultCallCount = 0
    
    /// Number of times clearAppSettingFlagAfterDelay was called.
    var clearAppSettingFlagAfterDelayCallCount = 0
    
    /// The UID passed to restoreSystemDefaultOutput.
    var lastRestoredUID: String?
    
    // MARK: - Stubbed Values
    
    /// The UID returned by getCurrentSystemDefaultOutputUID().
    var stubbedDefaultUID: String?
    
    /// Whether restoreSystemDefaultOutput succeeds.
    var stubbedRestoreSuccess = true
    
    /// Whether setDriverAsDefault succeeds.
    var stubbedSetDriverAsDefaultSuccess = true
    
    // MARK: - Simulation Helpers
    
    /// Simulates a system default change notification.
    func simulateDefaultChange(_ device: AudioDevice) {
        onSystemDefaultChanged?(device)
    }
    
    /// Resets all call counts and stubbed values.
    func reset() {
        startObservingCallCount = 0
        stopObservingCallCount = 0
        getCurrentSystemDefaultOutputUIDCallCount = 0
        restoreSystemDefaultOutputCallCount = 0
        setDriverAsDefaultCallCount = 0
        clearAppSettingFlagAfterDelayCallCount = 0
        lastRestoredUID = nil
        stubbedDefaultUID = nil
        stubbedRestoreSuccess = true
        stubbedSetDriverAsDefaultSuccess = true
        isAppSettingSystemDefault = false
    }
}