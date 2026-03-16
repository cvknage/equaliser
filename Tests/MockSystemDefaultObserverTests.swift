import XCTest
@testable import Equaliser

@MainActor
final class MockSystemDefaultObserverTests: XCTestCase {
    
    // MARK: - Start/Stop Observing Tests
    
    func test_startObserving_incrementsCallCount() {
        let observer = MockSystemDefaultObserver()
        
        XCTAssertEqual(observer.startObservingCallCount, 0)
        
        observer.startObserving()
        
        XCTAssertEqual(observer.startObservingCallCount, 1)
    }
    
    func test_stopObserving_incrementsCallCount() {
        let observer = MockSystemDefaultObserver()
        
        XCTAssertEqual(observer.stopObservingCallCount, 0)
        
        observer.stopObserving()
        
        XCTAssertEqual(observer.stopObservingCallCount, 1)
    }
    
    // MARK: - Get Default Device Tests
    
    func test_getCurrentSystemDefaultOutputUID_returnsStubbedValue() {
        let observer = MockSystemDefaultObserver()
        observer.stubbedDefaultUID = "test-device-uid"
        
        let result = observer.getCurrentSystemDefaultOutputUID()
        
        XCTAssertEqual(result, "test-device-uid")
        XCTAssertEqual(observer.getCurrentSystemDefaultOutputUIDCallCount, 1)
    }
    
    func test_getCurrentSystemDefaultOutputUID_returnsNilWhenNotSet() {
        let observer = MockSystemDefaultObserver()
        
        let result = observer.getCurrentSystemDefaultOutputUID()
        
        XCTAssertNil(result)
    }
    
    // MARK: - Restore Default Tests
    
    func test_restoreSystemDefaultOutput_storesLastRestoredUID() {
        let observer = MockSystemDefaultObserver()
        observer.stubbedRestoreSuccess = true
        
        let result = observer.restoreSystemDefaultOutput(to: "device-123")
        
        XCTAssertTrue(result)
        XCTAssertEqual(observer.lastRestoredUID, "device-123")
        XCTAssertEqual(observer.restoreSystemDefaultOutputCallCount, 1)
    }
    
    func test_restoreSystemDefaultOutput_returnsStubbedSuccess() {
        let observer = MockSystemDefaultObserver()
        observer.stubbedRestoreSuccess = false
        
        let result = observer.restoreSystemDefaultOutput(to: "device-123")
        
        XCTAssertFalse(result)
    }
    
    // MARK: - Set Driver As Default Tests
    
    func test_setDriverAsDefault_callsOnSuccess() {
        let observer = MockSystemDefaultObserver()
        observer.stubbedSetDriverAsDefaultSuccess = true
        var successCalled = false
        var failureCalled = false
        
        observer.setDriverAsDefault(
            onSuccess: { successCalled = true },
            onFailure: { failureCalled = true }
        )
        
        XCTAssertTrue(successCalled)
        XCTAssertFalse(failureCalled)
        XCTAssertEqual(observer.setDriverAsDefaultCallCount, 1)
    }
    
    func test_setDriverAsDefault_callsOnFailure() {
        let observer = MockSystemDefaultObserver()
        observer.stubbedSetDriverAsDefaultSuccess = false
        var successCalled = false
        var failureCalled = false
        
        observer.setDriverAsDefault(
            onSuccess: { successCalled = true },
            onFailure: { failureCalled = true }
        )
        
        XCTAssertFalse(successCalled)
        XCTAssertTrue(failureCalled)
    }
    
    // MARK: - Default Changed Callback Tests
    
    func test_simulateDefaultChange_callsCallback() {
        let observer = MockSystemDefaultObserver()
        var receivedDevice: AudioDevice?
        
        observer.onSystemDefaultChanged = { device in
            receivedDevice = device
        }
        
        let testDevice = AudioDevice(id: 42, uid: "test-uid", name: "Test Device", isInput: false, isOutput: true, transportType: 0)
        
        observer.simulateDefaultChange(testDevice)
        
        XCTAssertEqual(receivedDevice?.uid, "test-uid")
        XCTAssertEqual(receivedDevice?.id, 42)
    }
    
    // MARK: - Reset Tests
    
    func test_reset_clearsAllState() {
        let observer = MockSystemDefaultObserver()
        
        observer.startObserving()
        observer.stopObserving()
        observer.getCurrentSystemDefaultOutputUID()
        observer.restoreSystemDefaultOutput(to: "test")
        observer.setDriverAsDefault(onSuccess: nil, onFailure: nil)
        observer.clearAppSettingFlagAfterDelay()
        observer.isAppSettingSystemDefault = true
        
        observer.reset()
        
        XCTAssertEqual(observer.startObservingCallCount, 0)
        XCTAssertEqual(observer.stopObservingCallCount, 0)
        XCTAssertEqual(observer.getCurrentSystemDefaultOutputUIDCallCount, 0)
        XCTAssertEqual(observer.restoreSystemDefaultOutputCallCount, 0)
        XCTAssertEqual(observer.setDriverAsDefaultCallCount, 0)
        XCTAssertEqual(observer.clearAppSettingFlagAfterDelayCallCount, 0)
        XCTAssertNil(observer.lastRestoredUID)
        XCTAssertFalse(observer.isAppSettingSystemDefault)
        XCTAssertTrue(observer.stubbedRestoreSuccess)
        XCTAssertTrue(observer.stubbedSetDriverAsDefaultSuccess)
    }
}