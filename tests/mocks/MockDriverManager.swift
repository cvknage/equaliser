@testable import Equaliser
import CoreAudio
import Foundation

/// Mock driver manager for testing.
/// Provides controllable driver behaviour without real CoreAudio calls.
@MainActor
final class MockDriverManager: DriverAccessing {
    
    // MARK: - DriverAccessing Protocol
    
    var isReady: Bool {
        get { _isReady }
        set { _isReady = newValue }
    }
    
    private var _isReady = false
    
    var deviceID: AudioObjectID? {
        get { _deviceID }
        set { _deviceID = newValue }
    }
    
    private var _deviceID: AudioObjectID? = nil
    
    func isDriverVisible() -> Bool {
        isDriverVisibleCallCount += 1
        return stubbedIsDriverVisible
    }
    
    func findDriverDeviceWithRetry(
        initialDelayMs: Int = 100,
        maxAttempts: Int = 6
    ) async -> AudioDeviceID? {
        findDriverDeviceWithRetryCallCount += 1
        lastFindRetryParams = (initialDelayMs, maxAttempts)
        return stubbedDeviceID
    }
    
    func setDeviceName(_ name: String) -> Bool {
        setDeviceNameCallCount += 1
        lastDeviceName = name
        return stubbedSetDeviceNameSuccess
    }
    
    func setDriverSampleRate(matching targetRate: Float64) -> Float64? {
        setDriverSampleRateCallCount += 1
        lastTargetSampleRate = targetRate
        return stubbedSampleRate
    }
    
    func restoreToBuiltInSpeakers() -> Bool {
        restoreToBuiltInSpeakersCallCount += 1
        return stubbedRestoreSuccess
    }
    
    // MARK: - Test Helpers
    
    /// Number of times isDriverVisible() was called.
    var isDriverVisibleCallCount = 0
    
    /// Number of times findDriverDeviceWithRetry() was called.
    var findDriverDeviceWithRetryCallCount = 0
    
    /// Number of times setDeviceName() was called.
    var setDeviceNameCallCount = 0
    
    /// Number of times setDriverSampleRate() was called.
    var setDriverSampleRateCallCount = 0
    
    /// Number of times restoreToBuiltInSpeakers() was called.
    var restoreToBuiltInSpeakersCallCount = 0
    
    /// The last device name passed to setDeviceName.
    var lastDeviceName: String?
    
    /// The last target sample rate passed to setDriverSampleRate.
    var lastTargetSampleRate: Float64?
    
    /// The last retry parameters used.
    var lastFindRetryParams: (initialDelayMs: Int, maxAttempts: Int)?
    
    // MARK: - Stubbed Values
    
    /// Whether the driver is ready (isReady property).
    private(set) var stubbedIsReady = false
    
    /// Whether isDriverVisible() returns true.
    var stubbedIsDriverVisible = false
    
    /// The device ID returned by findDriverDeviceWithRetry() and deviceID property.
    var stubbedDeviceID: AudioObjectID? = nil
    
    /// Whether setDeviceName() succeeds.
    var stubbedSetDeviceNameSuccess = true
    
    /// The sample rate returned by setDriverSampleRate().
    var stubbedSampleRate: Float64? = nil
    
    /// Whether restoreToBuiltInSpeakers() succeeds.
    var stubbedRestoreSuccess = true
    
    // MARK: - Convenience Methods
    
    /// Configures the mock for a successful driver state.
    /// - Parameter deviceID: The device ID to return (default: 1).
    func configureReadyDriver(deviceID: AudioDeviceID = 1) {
        _isReady = true
        stubbedIsDriverVisible = true
        _deviceID = deviceID
        stubbedDeviceID = deviceID
        stubbedSetDeviceNameSuccess = true
        stubbedSampleRate = 48000.0
        stubbedRestoreSuccess = true
    }
    
    /// Configures the mock for a not-installed driver state.
    func configureNotInstalled() {
        _isReady = false
        stubbedIsDriverVisible = false
        _deviceID = nil
        stubbedDeviceID = nil
    }
    
    /// Configures the mock for driver installed but not visible.
    func configureInstalledNotVisible() {
        _isReady = true
        stubbedIsDriverVisible = false
        _deviceID = nil
        stubbedDeviceID = nil
    }
    
    /// Resets all call counts and stubbed values.
    func reset() {
        _isReady = false
        stubbedIsDriverVisible = false
        _deviceID = nil
        stubbedDeviceID = nil
        stubbedSetDeviceNameSuccess = true
        stubbedSampleRate = nil
        stubbedRestoreSuccess = true
        
        isDriverVisibleCallCount = 0
        findDriverDeviceWithRetryCallCount = 0
        setDeviceNameCallCount = 0
        setDriverSampleRateCallCount = 0
        restoreToBuiltInSpeakersCallCount = 0
        
        lastDeviceName = nil
        lastTargetSampleRate = nil
        lastFindRetryParams = nil
    }
}