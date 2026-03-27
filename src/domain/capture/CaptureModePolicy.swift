// CaptureModePolicy.swift
// Pure functions for determining capture mode

import Foundation

/// Determines capture mode based on capabilities and preferences.
/// Pure functions - no side effects, fully testable.
enum CaptureModePolicy {
    
    /// Determines which capture mode to use based on capabilities and preferences.
    ///
    /// Decision logic:
    /// - Manual mode always uses HAL input (user explicitly selected devices)
    /// - HAL input preference is used directly
    /// - Shared memory preference requires capability check
    /// - If shared memory unavailable, falls back to HAL input
    ///
    /// - Parameters:
    ///   - preference: User's preferred capture mode
    ///   - isManualMode: Whether manual mode is enabled
    ///   - supportsSharedMemory: Whether driver supports shared memory capture
    /// - Returns: Decision indicating which mode to use
    static func determineMode(
        preference: CaptureMode,
        isManualMode: Bool,
        supportsSharedMemory: Bool
    ) -> CaptureModeDecision {
        // Manual mode always uses HAL input
        if isManualMode {
            return .useMode(.halInput)
        }
        
        // HAL input preference - use directly
        if preference == .halInput {
            return .useMode(.halInput)
        }
        
        // Shared memory preference - check capability
        if supportsSharedMemory {
            return .useMode(.sharedMemory)
        }
        
        // Fallback: shared memory requested but unavailable
        return .fallbackToHALInput
    }
}