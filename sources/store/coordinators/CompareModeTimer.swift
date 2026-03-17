// CompareModeTimer.swift
// Auto-revert timer for compare mode

import Combine
import Foundation

/// Manages the auto-revert timer for compare mode.
/// When compare mode is set to `.flat`, this timer automatically
/// reverts back to `.eq` after a configurable interval (default 5 minutes).
@MainActor
final class CompareModeTimer: CompareModeTimerControlling {
    
    // MARK: - Properties
    
    private var timer: AnyCancellable?
    private let interval: TimeInterval
    
    /// Callback invoked when timer fires (should set compareMode to .eq)
    var onRevert: (() -> Void)?
    
    // MARK: - Initialization
    
    init(interval: TimeInterval = 300) { // 5 minutes default
        self.interval = interval
    }
    
    // MARK: - Public Methods
    
    /// Starts the auto-revert timer.
    /// If already running, cancels and restarts.
    func start() {
        cancel()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.onRevert?()
                self?.cancel()
            }
    }
    
    /// Cancels the auto-revert timer.
    func cancel() {
        timer?.cancel()
        timer = nil
    }
}