// AudioConstants.swift
// Centralized constants for audio pipeline configuration

import Foundation

/// Constants for audio rendering pipeline configuration.
///
/// These values were chosen based on:
/// - Real-time safety requirements
/// - Memory constraints
/// - Latency vs. stability tradeoffs
enum AudioConstants {
    // MARK: - Render Pipeline
    
    /// Maximum frames per render callback.
    ///
    /// This is the worst-case frame count that CoreAudio may request.
    /// Setting this too low causes buffer overflows on high sample rates.
    /// Setting too high wastes memory.
    ///
    /// - 16384 frames = ~341ms at 48kHz, ~170ms at 96kHz, ~21ms at 768kHz
    /// - Matches driver's kDevice_RingBufferSize (16384) for 768kHz support
    static let maxFrameCount: UInt32 = 16384
    
    /// Ring buffer capacity in sample frames per channel.
    ///
    /// Must be a power of 2 for efficient modulo arithmetic.
    /// Larger values provide more resilience against clock drift but increase latency.
    ///
    /// - 32768 samples = ~682ms at 48kHz, ~341ms at 96kHz, ~43ms at 768kHz
    /// - Chosen to handle reasonable clock drift between devices at all supported rates
    static let ringBufferCapacity: Int = 32768
    
    // MARK: - EQ Band Limits
    
    /// Minimum allowed EQ frequency in Hz.
    static let minEQFrequency: Float = 1

    /// Maximum allowed EQ frequency in Hz.
    /// Fixed at 22000 Hz to cover the audible spectrum and ensure cross-rate preset compatibility.
    /// Presets saved at high sample rates remain valid on lower-rate devices.
    static let maxEQFrequency: Float = 22000
    
    /// Minimum gain in dB for EQ bands.
    /// Matches the UI slider range in EqualiserStore.
    static let minGain: Float = -36
    
    /// Maximum gain in dB for EQ bands.
    /// Matches the UI slider range in EqualiserStore.
    static let maxGain: Float = 36
    
    // MARK: - Computed Properties
    
    /// Valid gain range for EQ band sliders.
    /// Used by UI components and preset validation.
    static var gainRange: ClosedRange<Float> { minGain...maxGain }
    
    // MARK: - Validation Helpers
    
    /// Clamps frequency to valid EQ range.
    static func clampFrequency(_ value: Float) -> Float {
        max(minEQFrequency, min(maxEQFrequency, value))
    }
    
    /// Clamps gain to valid EQ range.
    static func clampGain(_ value: Float) -> Float {
        max(minGain, min(maxGain, value))
    }
}