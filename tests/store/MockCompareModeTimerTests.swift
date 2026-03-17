import XCTest
@testable import Equaliser

@MainActor
final class MockCompareModeTimerTests: XCTestCase {
    
    // MARK: - Start/Cancel Tests
    
    func test_start_incrementsCallCount() {
        let timer = MockCompareModeTimer()
        
        XCTAssertEqual(timer.startCallCount, 0)
        XCTAssertFalse(timer.isStarted)
        
        timer.start()
        
        XCTAssertEqual(timer.startCallCount, 1)
        XCTAssertTrue(timer.isStarted)
    }
    
    func test_start_canBeCalledMultipleTimes() {
        let timer = MockCompareModeTimer()
        
        timer.start()
        timer.start()
        timer.start()
        
        XCTAssertEqual(timer.startCallCount, 3)
    }
    
    func test_cancel_incrementsCallCount() {
        let timer = MockCompareModeTimer()
        
        XCTAssertEqual(timer.cancelCallCount, 0)
        
        timer.cancel()
        
        XCTAssertEqual(timer.cancelCallCount, 1)
        XCTAssertFalse(timer.isStarted)
    }
    
    func test_cancel_canBeCalledMultipleTimes() {
        let timer = MockCompareModeTimer()
        
        timer.cancel()
        timer.cancel()
        
        XCTAssertEqual(timer.cancelCallCount, 2)
    }
    
    // MARK: - Callback Tests
    
    func test_simulateRevert_callsOnRevert() {
        let timer = MockCompareModeTimer()
        var reverted = false
        
        timer.onRevert = {
            reverted = true
        }
        
        XCTAssertFalse(reverted)
        
        timer.simulateRevert()
        
        XCTAssertTrue(reverted)
    }
    
    func test_simulateRevert_canBeCalledMultipleTimes() {
        let timer = MockCompareModeTimer()
        var revertCount = 0
        
        timer.onRevert = {
            revertCount += 1
        }
        
        timer.simulateRevert()
        timer.simulateRevert()
        timer.simulateRevert()
        
        XCTAssertEqual(revertCount, 3)
    }
    
    // MARK: - Reset Tests
    
    func test_reset_clearsState() {
        let timer = MockCompareModeTimer()
        
        timer.start()
        timer.cancel()
        
        XCTAssertEqual(timer.startCallCount, 1)
        XCTAssertEqual(timer.cancelCallCount, 1)
        
        timer.reset()
        
        XCTAssertEqual(timer.startCallCount, 0)
        XCTAssertEqual(timer.cancelCallCount, 0)
        XCTAssertFalse(timer.isStarted)
    }
}