import AVFoundation
import AudioToolbox
import os.log

/// Logger for source node callbacks (module-level to avoid actor isolation).
private let sourceNodeLogger = Logger(subsystem: "net.knage.equaliser", category: "SourceNode")

/// Errors that can occur when creating a ManualRenderingEngine.
enum ManualRenderingError: Error, LocalizedError {
    case invalidFormat(String)
    case manualRenderingFailed(String)
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid format: \(message)"
        case .manualRenderingFailed(let message):
            return "Manual rendering failed: \(message)"
        case .engineStartFailed(let message):
            return "Engine start failed: \(message)"
        }
    }
}

/// An AVAudioEngine configured for manual rendering mode with EQ processing.
/// Created on-demand with a specific format, avoiding early hardware initialization.
///
/// This class is created fresh each time the render pipeline starts,
/// ensuring the engine is configured with the correct sample rate and format.
@MainActor
final class ManualRenderingEngine {
    // MARK: - Properties

    /// The AVAudioEngine in manual rendering mode.
    /// Marked nonisolated(unsafe) to allow cleanup in deinit.
    private nonisolated(unsafe) var engine: AVAudioEngine?

    /// EQ units in the chain (enough to cover the active band count).
    private let eqUnits: [AVAudioUnitEQ]

    /// Source node that injects audio into the engine.
    private let sourceNode: AVAudioSourceNode

    /// The audio format used for rendering.
    let format: AVAudioFormat

    /// Maximum frames per render call.
    let maxFrameCount: AVAudioFrameCount

    /// The render context for real-time audio processing.
    /// Accessed from the audio thread via nonisolated property.
    private let _renderContext: AudioRenderContext

    /// Reference to the EQ configuration for live updates.
    private let eqConfiguration: EQConfiguration

    /// Logger for this engine instance.
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "ManualRenderingEngine")

    // MARK: - Static State (for audio thread)

    /// Source node callback counter for periodic logging.
    private nonisolated(unsafe) static var sourceNodeCallCount: UInt64 = 0

    // MARK: - Public Accessors

    /// Provides access to the render context for real-time audio processing.
    /// Safe to access from the audio render thread.
    nonisolated var renderContext: AudioRenderContext {
        _renderContext
    }

    // MARK: - Initialization

    /// Creates a new manual rendering engine with the specified format and EQ configuration.
    /// - Parameters:
    ///   - format: The audio format for rendering (must match HAL format).
    ///   - maxFrameCount: Maximum number of frames per render call.
    ///   - eqConfiguration: The EQ settings to apply.
    /// - Throws: `ManualRenderingError` if setup fails.
    init(
        format: AVAudioFormat,
        maxFrameCount: AVAudioFrameCount,
        eqConfiguration: EQConfiguration
    ) throws {
        self.format = format
        self.maxFrameCount = maxFrameCount
        self.eqConfiguration = eqConfiguration

        // Validate format
        guard format.sampleRate > 0 else {
            throw ManualRenderingError.invalidFormat("Sample rate must be positive")
        }
        guard format.channelCount > 0 else {
            throw ManualRenderingError.invalidFormat("Channel count must be positive")
        }

        logger.info("Creating engine: \(format.sampleRate) Hz, \(format.channelCount) ch, max \(maxFrameCount) frames")

        // 1. Create a fresh engine
        let engine = AVAudioEngine()
        self.engine = engine

        // 2. Enable manual rendering mode FIRST - before ANY node access
        //    This prevents the engine from querying hardware devices
        do {
            try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: maxFrameCount)
        } catch {
            throw ManualRenderingError.manualRenderingFailed(error.localizedDescription)
        }

        // 3. Create EQ units with full 32-band capacity each (max 32 bands per unit)
        //    This avoids pipeline reconfigure when increasing band count within capacity.
        //    Unused bands are bypassed in apply(to:) to prevent stale settings.
        let activeBandCount = eqConfiguration.activeBandCount
        let bandsPerUnit = 32
        let unitCount = Int(ceil(Float(activeBandCount) / Float(bandsPerUnit)))
        let units: [AVAudioUnitEQ] = (0..<unitCount).map { _ in
            AVAudioUnitEQ(numberOfBands: bandsPerUnit)  // Always full capacity
        }
        self.eqUnits = units

        // 4. Create the render context (will be accessed from audio thread)
        let context = AudioRenderContext(
            engine: engine,
            format: format,
            maxFrameCount: maxFrameCount
        )
        self._renderContext = context

        // 5. Create source node with the specified format
        //    Use nonisolated static method to avoid actor isolation in render block
        let source = Self.createSourceNode(format: format, context: context)
        self.sourceNode = source

        // 6. Attach nodes to the engine
        engine.attach(source)
        eqUnits.forEach { engine.attach($0) }

        // 7. Connect the graph: source -> EQ units chain -> outputNode
        var previousNode: AVAudioNode = source
        for unit in eqUnits {
            engine.connect(previousNode, to: unit, format: format)
            previousNode = unit
        }
        engine.connect(previousNode, to: engine.outputNode, format: format)

        // 8. Apply EQ configuration
        eqConfiguration.apply(to: eqUnits)

        // 9. Start the engine
        do {
            try engine.start()
        } catch {
            throw ManualRenderingError.engineStartFailed(error.localizedDescription)
        }

        logger.info("Engine started in manual rendering mode")
    }

    deinit {
        // Stop and clean up the engine
        // Engine is nonisolated(unsafe) to allow access from deinit
        if let eng = engine {
            eng.stop()
            eng.disableManualRenderingMode()
        }
        engine = nil
    }

    // MARK: - Source Node Creation

    /// Creates an AVAudioSourceNode with a render block that reads from the given context.
    /// This function is `nonisolated` to prevent the closure from inheriting `@MainActor`
    /// isolation, which would cause a crash when called from the audio render thread.
    private nonisolated static func createSourceNode(
        format: AVAudioFormat,
        context: AudioRenderContext
    ) -> AVAudioSourceNode {
        return AVAudioSourceNode(format: format) { [weak context] _, _, frameCount, audioBufferList -> OSStatus in
            guard let ctx = context else {
                zeroFillBufferList(audioBufferList, frameCount: frameCount)
                return noErr
            }

            let (inputBuffers, inputFrameCount) = ctx.getInputBuffers()

            // Periodic logging (every 10k callbacks to minimize overhead)
            sourceNodeCallCount &+= 1
            if sourceNodeCallCount % 10000 == 1 {
                let hasInput = !inputBuffers.isEmpty && inputFrameCount > 0
                sourceNodeLogger.info("SourceNode #\(sourceNodeCallCount): frames=\(frameCount), hasInput=\(hasInput), inputFrameCount=\(inputFrameCount)")
            }

            guard !inputBuffers.isEmpty, inputFrameCount > 0 else {
                zeroFillBufferList(audioBufferList, frameCount: frameCount)
                return noErr
            }

            // Copy deinterleaved input samples to the source node's output
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let framesToCopy = min(Int(frameCount), inputFrameCount)

            for (channelIndex, buffer) in abl.enumerated() {
                if let destData = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    if channelIndex < inputBuffers.count {
                        let srcBuffer = inputBuffers[channelIndex]
                        memcpy(destData, srcBuffer, framesToCopy * MemoryLayout<Float>.size)
                    } else {
                        memset(destData, 0, framesToCopy * MemoryLayout<Float>.size)
                    }
                }
            }

            return noErr
        }
    }

    /// Zero-fills an AudioBufferList.
    private nonisolated static func zeroFillBufferList(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: UInt32
    ) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in abl {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    // MARK: - EQ Control

    /// Updates the bypass state from the current EQ configuration.
    func updateBypass(systemEQOff: Bool, compareMode: CompareMode) {
        let shouldBypassEQ = systemEQOff || compareMode == .flat
        for unit in eqUnits {
            unit.bypass = shouldBypassEQ
        }
    }

    /// Updates a band's gain from the current EQ configuration.
    func updateBandGain(index: Int) {
        eqConfiguration.applyBandGain(index: index, to: eqUnits)
    }

    /// Updates a band's bandwidth from the current EQ configuration.
    func updateBandBandwidth(index: Int) {
        eqConfiguration.applyBandBandwidth(index: index, to: eqUnits)
    }

    /// Updates a band's frequency from the current EQ configuration.
    func updateBandFrequency(index: Int) {
        eqConfiguration.applyBandFrequency(index: index, to: eqUnits)
    }

    /// Updates a band's filter type from the current EQ configuration.
    func updateBandFilterType(index: Int) {
        eqConfiguration.applyBandFilterType(index: index, to: eqUnits)
    }

    /// Updates a band's bypass state from the current EQ configuration.
    func updateBandBypass(index: Int) {
        eqConfiguration.applyBandBypass(index: index, to: eqUnits)
    }

    /// Returns the total band capacity (sum of all EQ unit bands).
    var bandCapacity: Int {
        eqUnits.reduce(0) { $0 + $1.bands.count }
    }

    /// Reapplies the full EQ configuration.
    func reapplyConfiguration() {
        eqConfiguration.apply(to: eqUnits)
    }

    // MARK: - Shutdown

    /// Stops and cleans up the engine.
    func shutdown() {
        logger.info("Shutting down manual rendering engine")
        engine?.stop()
        engine?.disableManualRenderingMode()
    }
}
