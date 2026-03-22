import XCTest
@testable import Equaliser

// MARK: - MockDriverManager Tests

@MainActor
final class MockDriverManagerTests: XCTestCase {
    
    var mockDriver: MockDriverManager!
    
    override func setUp() async throws {
        try await super.setUp()
        mockDriver = MockDriverManager()
    }
    
    override func tearDown() async throws {
        mockDriver = nil
        try await super.tearDown()
    }
    
    // MARK: - isReady Property Tests
    
    func testIsReady_defaultValue_isFalse() {
        XCTAssertFalse(mockDriver.isReady)
    }
    
    func testIsReady_whenConfiguredAsReady_returnsTrue() {
        mockDriver.configureReadyDriver(deviceID: 1234)
        XCTAssertTrue(mockDriver.isReady)
    }
    
    func testIsReady_whenConfiguredAsNotInstalled_returnsFalse() {
        mockDriver.configureNotInstalled()
        XCTAssertFalse(mockDriver.isReady)
    }
    
    // MARK: - isDriverVisible Tests
    
    func testIsDriverVisible_tracksCalls() {
        _ = mockDriver.isDriverVisible()
        XCTAssertEqual(mockDriver.isDriverVisibleCallCount, 1)
    }
    
    func testIsDriverVisible_returnsStubbedValue() {
        mockDriver.stubbedIsDriverVisible = true
        XCTAssertTrue(mockDriver.isDriverVisible())
        
        mockDriver.stubbedIsDriverVisible = false
        XCTAssertFalse(mockDriver.isDriverVisible())
    }
    
    // MARK: - deviceID Property Tests
    
    func testDeviceID_defaultValue_isNil() {
        XCTAssertNil(mockDriver.deviceID)
    }
    
    func testDeviceID_whenConfigured_returnsValue() {
        mockDriver.configureReadyDriver(deviceID: 5678)
        XCTAssertEqual(mockDriver.deviceID, 5678)
    }
    
    // MARK: - findDriverDeviceWithRetry Tests
    
    func testFindDriverDeviceWithRetry_tracksCalls() async {
        mockDriver.stubbedDeviceID = 1234
        _ = await mockDriver.findDriverDeviceWithRetry()
        XCTAssertEqual(mockDriver.findDriverDeviceWithRetryCallCount, 1)
    }
    
    func testFindDriverDeviceWithRetry_tracksParameters() async {
        mockDriver.stubbedDeviceID = 1234
        _ = await mockDriver.findDriverDeviceWithRetry(initialDelayMs: 200, maxAttempts: 5)
        
        XCTAssertEqual(mockDriver.lastFindRetryParams?.initialDelayMs, 200)
        XCTAssertEqual(mockDriver.lastFindRetryParams?.maxAttempts, 5)
    }
    
    func testFindDriverDeviceWithRetry_returnsStubbedValue() async {
        mockDriver.stubbedDeviceID = 999
        
        let result = await mockDriver.findDriverDeviceWithRetry()
        XCTAssertEqual(result, 999)
    }
    
    func testFindDriverDeviceWithRetry_whenNotConfigured_returnsNil() async {
        let result = await mockDriver.findDriverDeviceWithRetry()
        XCTAssertNil(result)
    }
    
    // MARK: - setDeviceName Tests
    
    func testSetDeviceName_tracksCalls() {
        _ = mockDriver.setDeviceName("Speakers")
        XCTAssertEqual(mockDriver.setDeviceNameCallCount, 1)
    }
    
    func testSetDeviceName_tracksName() {
        _ = mockDriver.setDeviceName("Test Output")
        XCTAssertEqual(mockDriver.lastDeviceName, "Test Output")
    }
    
    func testSetDeviceName_returnsStubbedSuccess() {
        mockDriver.stubbedSetDeviceNameSuccess = true
        XCTAssertTrue(mockDriver.setDeviceName("Speakers"))
        
        mockDriver.stubbedSetDeviceNameSuccess = false
        XCTAssertFalse(mockDriver.setDeviceName("Speakers"))
    }
    
    // MARK: - setDriverSampleRate Tests
    
    func testSetDriverSampleRate_tracksCalls() {
        _ = mockDriver.setDriverSampleRate(matching: 48000.0)
        XCTAssertEqual(mockDriver.setDriverSampleRateCallCount, 1)
    }
    
    func testSetDriverSampleRate_tracksTargetRate() {
        _ = mockDriver.setDriverSampleRate(matching: 96000.0)
        XCTAssertEqual(mockDriver.lastTargetSampleRate, 96000.0)
    }
    
    func testSetDriverSampleRate_returnsStubbedValue() {
        mockDriver.stubbedSampleRate = 48000.0
        
        let result = mockDriver.setDriverSampleRate(matching: 44100.0)
        XCTAssertEqual(result, 48000.0)
    }
    
    func testSetDriverSampleRate_whenNotConfigured_returnsNil() {
        let result = mockDriver.setDriverSampleRate(matching: 48000.0)
        XCTAssertNil(result)
    }
    
    // MARK: - restoreToBuiltInSpeakers Tests
    
    func testRestoreToBuiltInSpeakers_tracksCalls() {
        _ = mockDriver.restoreToBuiltInSpeakers()
        XCTAssertEqual(mockDriver.restoreToBuiltInSpeakersCallCount, 1)
    }
    
    func testRestoreToBuiltInSpeakers_returnsStubbedValue() {
        mockDriver.stubbedRestoreSuccess = true
        XCTAssertTrue(mockDriver.restoreToBuiltInSpeakers())
        
        mockDriver.stubbedRestoreSuccess = false
        XCTAssertFalse(mockDriver.restoreToBuiltInSpeakers())
    }
    
    // MARK: - Convenience Configuration Tests
    
    func testConfigureReadyDriver_setsAllProperties() {
        mockDriver.configureReadyDriver(deviceID: 1234)
        
        XCTAssertTrue(mockDriver.isReady)
        XCTAssertTrue(mockDriver.isDriverVisible())
        XCTAssertEqual(mockDriver.deviceID, 1234)
        XCTAssertEqual(mockDriver.stubbedDeviceID, 1234)
        XCTAssertTrue(mockDriver.stubbedSetDeviceNameSuccess)
    }
    
    func testConfigureNotInstalled_clearsAllProperties() {
        mockDriver.configureReadyDriver(deviceID: 1234)
        mockDriver.configureNotInstalled()
        
        XCTAssertFalse(mockDriver.isReady)
        XCTAssertFalse(mockDriver.stubbedIsDriverVisible)
        XCTAssertNil(mockDriver.deviceID)
        XCTAssertNil(mockDriver.stubbedDeviceID)
    }
    
    func testConfigureInstalledNotVisible_setsCorrectState() {
        mockDriver.configureInstalledNotVisible()
        
        XCTAssertTrue(mockDriver.isReady)
        XCTAssertFalse(mockDriver.isDriverVisible())
        XCTAssertNil(mockDriver.deviceID)
    }
    
    // MARK: - Reset Tests
    
    func testReset_clearsAllState() {
        // Configure with values
        mockDriver.configureReadyDriver(deviceID: 1234)
        mockDriver.stubbedSampleRate = 48000.0
        _ = mockDriver.isDriverVisible()
        _ = mockDriver.setDeviceName("Test")
        _ = mockDriver.restoreToBuiltInSpeakers()
        
        // Reset
        mockDriver.reset()
        
        // Verify all state cleared
        XCTAssertFalse(mockDriver.isReady)
        XCTAssertFalse(mockDriver.stubbedIsDriverVisible)
        XCTAssertNil(mockDriver.deviceID)
        XCTAssertNil(mockDriver.stubbedDeviceID)
        XCTAssertNil(mockDriver.stubbedSampleRate)
        
        XCTAssertEqual(mockDriver.isDriverVisibleCallCount, 0)
        XCTAssertEqual(mockDriver.findDriverDeviceWithRetryCallCount, 0)
        XCTAssertEqual(mockDriver.setDeviceNameCallCount, 0)
        XCTAssertEqual(mockDriver.setDriverSampleRateCallCount, 0)
        XCTAssertEqual(mockDriver.restoreToBuiltInSpeakersCallCount, 0)
        
        XCTAssertNil(mockDriver.lastDeviceName)
        XCTAssertNil(mockDriver.lastTargetSampleRate)
        XCTAssertNil(mockDriver.lastFindRetryParams)
    }
}