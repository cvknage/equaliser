// CompareModeTimerControlling.swift
// Protocol for compare mode auto-revert timer

import Foundation

/// Protocol for compare mode auto-revert timer.
/// Allows mocking in tests without waiting for real timers.
///
/// The compare mode timer reverts the EQ back to normal mode after
/// a timeout when the user enables "Flat" mode for comparison.
///
/// Example usage:
/// ```swift
/// class CompareModeTimer: CompareModeTimerControlling {
///     var onRevert: (() -> Void)?
///     func start() { /* start timer */ }
///     func cancel() { /* stop timer */ }
/// }
///
/// // In tests:
/// let mockTimer = MockCompareModeTimer()
/// mockTimer.start()
/// mockTimer.simulateRevert() // Instantly fire callback
/// ```
@MainActor
protocol CompareModeTimerControlling: AnyObject {
    /// Callback invoked when the timer fires.
    /// Set this to handle the auto-revert action.
    var onRevert: (() -> Void)? { get set }
    
    /// Starts the auto-revert timer.
    /// If already running, cancels and restarts.
    func start()
    
    /// Cancels the auto-revert timer.
    func cancel()
}