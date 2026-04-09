import Foundation

/// Capture mode for automatic routing with the Equaliser driver.
///
/// - halInput: Uses HAL input stream (AudioUnitRender). Triggers macOS TCC
///   microphone indicator. Works with any virtual driver in manual mode.
/// - sharedMemory: Uses lock-free shared memory ring buffer. No TCC indicator.
///   No glitches on volume change. Preferred when available.
enum CaptureMode: Int, Codable, CaseIterable, Sendable {
    case halInput = 0
    case sharedMemory = 1

    var displayName: String {
        switch self {
        case .halInput:
            return "HAL Input"
        case .sharedMemory:
            return "Shared Memory"
        }
    }

    var description: String {
        switch self {
        case .halInput:
            return "Uses input stream capture. May show microphone indicator in Control Center."
        case .sharedMemory:
            return "Uses shared memory for lock-free capture. No microphone indicator. Requires Equaliser driver."
        }
    }
}

/// Result of capture mode determination.
/// Indicates which mode to use and whether permission is needed.
enum CaptureModeDecision: Equatable {
    /// Use this capture mode directly (no permission check needed for this step).
    case useMode(CaptureMode)
    /// Shared memory unavailable - fall back to HAL input (requires mic permission).
    case fallbackToHALInput
}