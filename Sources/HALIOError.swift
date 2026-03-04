import Foundation
import CoreAudio

/// Errors that can occur during HAL I/O unit operations.
enum HALIOError: Error, LocalizedError, Sendable {
    /// The HAL output audio component was not found on this system.
    case componentNotFound

    /// Failed to create an instance of the HAL output audio unit.
    case instanceCreationFailed(OSStatus)

    /// Failed to initialize the audio unit.
    case initializationFailed(OSStatus)

    /// Failed to start the audio unit.
    case startFailed(OSStatus)

    /// Failed to stop the audio unit.
    case stopFailed(OSStatus)

    /// Failed to enable I/O on the specified scope.
    case enableIOFailed(scope: String, OSStatus)

    /// Failed to set the current device for the specified scope.
    case deviceSetFailed(scope: String, OSStatus)

    /// Failed to query the stream format from the audio unit.
    case formatQueryFailed(OSStatus)

    /// Failed to set the stream format on the audio unit.
    case formatSetFailed(OSStatus)

    /// Operation requires the audio unit to be initialized first.
    case notInitialized

    /// The audio unit is already running.
    case alreadyRunning

    /// The audio unit instance is nil (not created or already disposed).
    case unitNotAvailable

    /// Failed to register a render callback on the specified scope.
    case callbackRegistrationFailed(scope: String, OSStatus)

    /// Audio rendering failed with the given status.
    case renderFailed(OSStatus)

    /// Input and output sample rates do not match.
    case sampleRateMismatch(inputRate: Double, outputRate: Double)

    /// Input and output channel counts do not match.
    case channelCountMismatch(inputChannels: UInt32, outputChannels: UInt32)

    /// Failed to enable manual rendering mode on the audio engine.
    case manualRenderingFailed(String)

    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            "HAL output audio component not found"
        case .instanceCreationFailed(let status):
            "Failed to create audio unit instance (OSStatus: \(status))"
        case .initializationFailed(let status):
            "Failed to initialize audio unit (OSStatus: \(status))"
        case .startFailed(let status):
            "Failed to start audio unit (OSStatus: \(status))"
        case .stopFailed(let status):
            "Failed to stop audio unit (OSStatus: \(status))"
        case .enableIOFailed(let scope, let status):
            "Failed to enable I/O on \(scope) scope (OSStatus: \(status))"
        case .deviceSetFailed(let scope, let status):
            "Failed to set device on \(scope) scope (OSStatus: \(status))"
        case .formatQueryFailed(let status):
            "Failed to query stream format (OSStatus: \(status))"
        case .formatSetFailed(let status):
            "Failed to set stream format (OSStatus: \(status))"
        case .notInitialized:
            "Audio unit is not initialized"
        case .alreadyRunning:
            "Audio unit is already running"
        case .unitNotAvailable:
            "Audio unit instance is not available"
        case .callbackRegistrationFailed(let scope, let status):
            "Failed to register callback on \(scope) scope (OSStatus: \(status))"
        case .renderFailed(let status):
            "Audio rendering failed (OSStatus: \(status))"
        case .sampleRateMismatch(let inputRate, let outputRate):
            "Sample rate mismatch: input \(inputRate) Hz, output \(outputRate) Hz"
        case .channelCountMismatch(let inputChannels, let outputChannels):
            "Channel count mismatch: input \(inputChannels), output \(outputChannels)"
        case .manualRenderingFailed(let reason):
            "Failed to enable manual rendering: \(reason)"
        }
    }
}
