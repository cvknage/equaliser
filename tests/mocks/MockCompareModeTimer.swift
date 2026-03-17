@testable import Equaliser
import Foundation

/// Mock compare mode timer for testing.
/// Provides controllable, instantaneous timer behavior without real delays.
@MainActor
final class MockCompareModeTimer: CompareModeTimerControlling {
    
    // MARK: - CompareModeTimerControlling
    
    var onRevert: (() -> Void)?
    
    func start() {
        startCallCount += 1
        isStarted = true
    }
    
    func cancel() {
        cancelCallCount += 1
        isStarted = false
    }
    
    // MARK: - Test Helpers
    
    /// Number of times start() was called.
    var startCallCount = 0
    
    /// Number of times cancel() was called.
    var cancelCallCount = 0
    
    /// Whether the timer is currently "started".
    var isStarted = false
    
    /// Simulates the timer firing (calls onRevert callback).
    func simulateRevert() {
        onRevert?()
    }
    
    /// Resets all call counts and state.
    func reset() {
        startCallCount = 0
        cancelCallCount = 0
        isStarted = false
    }
}