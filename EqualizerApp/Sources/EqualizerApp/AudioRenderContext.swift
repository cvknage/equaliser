import AVFoundation
import AudioToolbox

/// Holds state needed for real-time audio rendering via AVAudioEngine in manual mode.
/// This class is accessed from the audio render thread and must be lock-free.
///
/// - Important: This class is `@unchecked Sendable` because it is intentionally
///   accessed from multiple threads (main thread for setup, audio thread for rendering).
///   All mutable state uses `nonisolated(unsafe)` and all audio-thread methods are
///   marked `nonisolated` to avoid Swift 6 actor isolation checks on the audio thread.
final class AudioRenderContext: @unchecked Sendable {
    // MARK: - Properties

    /// The AVAudioEngine configured for manual rendering.
    let engine: AVAudioEngine

    /// The format used for rendering.
    let format: AVAudioFormat

    /// Number of audio channels.
    let channelCount: UInt32

    /// Maximum frames that can be rendered in one call.
    let maxFrameCount: AVAudioFrameCount

    /// Pointers to the current input buffers (one per channel, deinterleaved).
    /// Set before each render call. Marked nonisolated(unsafe) for audio thread access.
    private nonisolated(unsafe) var inputBufferPointers: [UnsafePointer<Float>] = []

    /// Number of frames available in each input buffer.
    /// Marked nonisolated(unsafe) for audio thread access.
    private nonisolated(unsafe) var inputFrameCount: Int = 0

    // MARK: - Initialization

    /// Creates a new render context with the given engine and format.
    /// - Parameters:
    ///   - engine: An AVAudioEngine already configured for manual rendering mode.
    ///   - format: The audio format for rendering.
    ///   - maxFrameCount: Maximum number of frames per render call.
    init(engine: AVAudioEngine, format: AVAudioFormat, maxFrameCount: AVAudioFrameCount) {
        self.engine = engine
        self.format = format
        self.channelCount = format.channelCount
        self.maxFrameCount = maxFrameCount
    }

    // MARK: - Input Buffer Management (Deinterleaved)
    // All methods in this section are nonisolated for audio thread access.

    /// Sets the deinterleaved input buffers for the next render call.
    /// Called from the audio thread before invoking `render()`.
    /// - Parameters:
    ///   - buffers: Array of pointers to float samples, one per channel.
    ///   - frameCount: Number of frames available in each buffer.
    nonisolated func setInputBuffers(_ buffers: [UnsafePointer<Float>], frameCount: Int) {
        inputBufferPointers = buffers
        inputFrameCount = frameCount
    }

    /// Clears the input buffer references after rendering.
    /// Called from the audio thread after rendering is complete.
    nonisolated func clearInputBuffer() {
        inputBufferPointers = []
        inputFrameCount = 0
    }

    /// Returns the current deinterleaved input buffers and frame count.
    /// Called from the source node's render block on the audio thread.
    nonisolated func getInputBuffers() -> (buffers: [UnsafePointer<Float>], frameCount: Int) {
        return (inputBufferPointers, inputFrameCount)
    }

    // MARK: - Legacy Single-Buffer API (Deprecated)

    /// Sets the input buffer for the next render call.
    /// - Note: This is a legacy API. Prefer `setInputBuffers(_:frameCount:)` for deinterleaved audio.
    /// - Parameters:
    ///   - buffer: Pointer to interleaved or non-interleaved float samples.
    ///   - frameCount: Number of samples (total, not per channel) available in the buffer.
    nonisolated func setInputBuffer(_ buffer: UnsafePointer<Float>, frameCount: Int) {
        // Legacy: treat as single channel or first channel only
        inputBufferPointers = [buffer]
        inputFrameCount = frameCount
    }

    /// Returns the current input buffer and frame count.
    /// - Note: This is a legacy API. Prefer `getInputBuffers()` for deinterleaved audio.
    nonisolated func getInputBuffer() -> (buffer: UnsafePointer<Float>?, frameCount: Int) {
        return (inputBufferPointers.first, inputFrameCount)
    }

    // MARK: - Static Logging State

    /// Counter for render calls to enable periodic logging
    private nonisolated(unsafe) static var renderResultCallCount: UInt64 = 0

    /// Flag to log the first render result
    private nonisolated(unsafe) static var didLogFirstRender: Bool = false

    // MARK: - Rendering

    /// Renders audio through the engine's processing chain.
    /// Called from the audio thread.
    /// - Parameters:
    ///   - frameCount: Number of frames to render.
    ///   - outputBuffer: The buffer to receive rendered audio.
    /// - Returns: `noErr` on success, or an error status code.
    nonisolated func render(
        frameCount: AVAudioFrameCount,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        var status: OSStatus = noErr
        let result = engine.manualRenderingBlock(frameCount, outputBuffer, &status)

        // One-time logging for first render
        if !Self.didLogFirstRender {
            Self.didLogFirstRender = true
            print("[AudioRenderContext] First render: result=\(result.rawValue), status=\(status), frameCount=\(frameCount)")
        }

        // Periodic logging for non-success results
        Self.renderResultCallCount &+= 1
        if result != .success {
            if Self.renderResultCallCount % 10000 == 1 {
                print("[AudioRenderContext] Render #\(Self.renderResultCallCount): result=\(result.rawValue), status=\(status)")
            }
        }

        switch result {
        case .success:
            return noErr
        case .error:
            return status
        case .insufficientDataFromInputNode:
            // Source node didn't provide enough data; output may be partially filled
            return noErr
        case .cannotDoInCurrentContext:
            // Real-time constraint violated; output unchanged
            return noErr
        @unknown default:
            return noErr
        }
    }
}
