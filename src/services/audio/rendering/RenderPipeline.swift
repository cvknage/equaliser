import AudioToolbox
import AVFoundation
import CoreAudio
import os.log

struct LevelMeterSnapshot {
    let inputDB: [Float]
    let outputDB: [Float]
    let inputRmsDB: [Float]
    let outputRmsDB: [Float]

    static let silent = LevelMeterSnapshot(
        inputDB: Array(repeating: -90, count: 2),
        outputDB: Array(repeating: -90, count: 2),
        inputRmsDB: Array(repeating: -90, count: 2),
        outputRmsDB: Array(repeating: -90, count: 2)
    )
}

/// Coordinates audio flow from HAL input through AVAudioEngine EQ to HAL output.
/// Uses two separate HAL audio units: one for input (capture) and one for output (playback).
/// Audio flows through a ring buffer to decouple the two device clocks.
///
/// Architecture:
/// ```
/// [BlackHole] → [Input HAL] → [Input Callback] → [Ring Buffer]
///                                                       ↓
/// [Output Callback] ← reads ← [Ring Buffer]
///        ↓
/// [AVAudioEngine EQ]
///        ↓
/// [Output HAL] → [Speakers]
/// ```
@MainActor
final class RenderPipeline {
    // MARK: - Properties

    /// HAL manager for input (capture from BlackHole or other input device).
    private var inputHALManager: HALIOManager?

    /// HAL manager for output (playback to speakers or other output device).
    private var outputHALManager: HALIOManager?

    private let eqConfiguration: EQConfiguration
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "RenderPipeline")

    /// The manual rendering engine (created with the correct format in start()).
    private var renderingEngine: ManualRenderingEngine?

    /// Whether the render pipeline is currently running.
    /// Marked nonisolated(unsafe) for access from deinit.
    private nonisolated(unsafe) var isRunning: Bool = false

    /// The callback context, retained while running.
    /// Marked nonisolated(unsafe) for access from the audio thread.
    private nonisolated(unsafe) var callbackContext: RenderCallbackContext?

    /// Most recent meter snapshot from the audio thread.
    private nonisolated(unsafe) var latestMeters: LevelMeterSnapshot = .silent

    /// Maximum frames per render callback.
    private let maxFrameCount: UInt32 = 4096

    /// Ring buffer capacity in samples per channel (~85ms at 96kHz).
    private let ringBufferCapacity: Int = 8192

    // MARK: - Static Logging (for audio thread)

    /// Input callback counter for periodic logging.
    private nonisolated(unsafe) static var inputCallCount: UInt64 = 0

    /// Output callback counter for periodic logging.
    private nonisolated(unsafe) static var outputCallCount: UInt64 = 0

    /// Logger for static/audio thread context.
    private static let staticLogger = Logger(subsystem: "net.knage.equaliser", category: "RenderCallback")

    // MARK: - Initialization

    /// Creates a new render pipeline.
    /// - Parameter eqConfiguration: The EQ configuration to apply.
    init(eqConfiguration: EQConfiguration) {
        self.eqConfiguration = eqConfiguration
    }

    deinit {
        // Perform synchronous cleanup directly since we can't call actor-isolated methods.
        // The HAL managers' deinit will handle stopping the audio units.
        callbackContext = nil
    }

    // MARK: - Configuration

    /// Configures the render pipeline with the specified input and output devices.
    /// Creates two separate HAL managers: one for input-only and one for output-only.
    /// - Parameters:
    ///   - inputDeviceID: The Core Audio device ID for audio input (e.g., BlackHole).
    ///   - outputDeviceID: The Core Audio device ID for audio output (e.g., speakers).
    /// - Returns: Success or an error describing the failure.
    func configure(
        inputDeviceID: AudioDeviceID,
        outputDeviceID: AudioDeviceID
    ) -> Result<Void, HALIOError> {
        logger.info("Configuring pipeline: input=\(inputDeviceID), output=\(outputDeviceID)")

        // Clean up any existing managers
        inputHALManager = nil
        outputHALManager = nil

        // Create and configure the input HAL manager (input-only mode)
        let inputManager = HALIOManager(mode: .inputOnly)
        if case .failure(let error) = inputManager.configure(deviceID: inputDeviceID) {
            logger.error("Input HAL configuration failed: \(error.localizedDescription)")
            return .failure(error)
        }
        inputHALManager = inputManager

        // Create and configure the output HAL manager (output-only mode)
        let outputManager = HALIOManager(mode: .outputOnly)
        if case .failure(let error) = outputManager.configure(deviceID: outputDeviceID) {
            logger.error("Output HAL configuration failed: \(error.localizedDescription)")
            inputHALManager = nil
            return .failure(error)
        }
        outputHALManager = outputManager

        // Validate sample rates match between input and output
        if case .failure(let error) = validateFormats() {
            inputHALManager = nil
            outputHALManager = nil
            return .failure(error)
        }

        logger.info("Pipeline configured successfully")
        return .success(())
    }

    /// Validates that input and output formats are compatible.
    private func validateFormats() -> Result<Void, HALIOError> {
        guard let inputManager = inputHALManager,
              let outputManager = outputHALManager else {
            return .failure(.unitNotAvailable)
        }

        // Get input format
        guard case .success(let inputFormat) = inputManager.getClientFormat() else {
            return .failure(.formatQueryFailed(0))
        }

        // Get output format
        guard case .success(let outputFormat) = outputManager.getClientFormat() else {
            return .failure(.formatQueryFailed(0))
        }

        logger.info("Input format: \(inputFormat.mSampleRate) Hz, \(inputFormat.mChannelsPerFrame) ch")
        logger.info("Output format: \(outputFormat.mSampleRate) Hz, \(outputFormat.mChannelsPerFrame) ch")

        // Check sample rates - they must match for our pipeline
        if inputFormat.mSampleRate != outputFormat.mSampleRate {
            logger.error("Sample rate mismatch: input=\(inputFormat.mSampleRate), output=\(outputFormat.mSampleRate)")
            return .failure(.sampleRateMismatch(
                inputRate: inputFormat.mSampleRate,
                outputRate: outputFormat.mSampleRate
            ))
        }

        // Check channel counts - warn but allow mismatch
        if inputFormat.mChannelsPerFrame != outputFormat.mChannelsPerFrame {
            logger.warning("Channel count mismatch: input=\(inputFormat.mChannelsPerFrame), output=\(outputFormat.mChannelsPerFrame)")
        }

        logger.info("Format validation passed: \(inputFormat.mSampleRate) Hz, \(inputFormat.mChannelsPerFrame) ch")
        return .success(())
    }

    // MARK: - Lifecycle

    /// Starts the render pipeline.
    /// - Returns: Success or an error describing the failure.
    func start() -> Result<Void, HALIOError> {
        guard !isRunning else {
            logger.info("Pipeline already running")
            return .success(())
        }

        guard let inputManager = inputHALManager,
              let outputManager = outputHALManager else {
            logger.error("Cannot start: HAL managers not configured")
            return .failure(.unitNotAvailable)
        }

        // Reset static counters
        Self.inputCallCount = 0
        Self.outputCallCount = 0

        logger.info("Starting render pipeline...")

        // Get the format from the input HAL manager (this determines our processing format)
        guard case .success(let streamFormat) = inputManager.getClientFormat() else {
            return .failure(.formatQueryFailed(0))
        }

        logger.info("Processing format: \(streamFormat.mSampleRate) Hz, \(streamFormat.mChannelsPerFrame) ch")

        // Create AVAudioFormat from the stream format
        guard let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamFormat.mSampleRate,
            channels: streamFormat.mChannelsPerFrame,
            interleaved: false
        ) else {
            return .failure(.manualRenderingFailed("Could not create AVAudioFormat"))
        }

        // Create the manual rendering engine with the correct format
        let engine: ManualRenderingEngine
        do {
            engine = try ManualRenderingEngine(
                format: avFormat,
                maxFrameCount: AVAudioFrameCount(maxFrameCount),
                eqConfiguration: eqConfiguration
            )
        } catch {
            logger.error("Failed to create rendering engine: \(error)")
            return .failure(.manualRenderingFailed(error.localizedDescription))
        }
        renderingEngine = engine

        // Create the callback context with ring buffers
        let context = RenderCallbackContext(
            inputHALUnit: inputManager.unsafeAudioUnit,
            renderContext: engine.renderContext,
            channelCount: streamFormat.mChannelsPerFrame,
            maxFrameCount: maxFrameCount,
            ringBufferCapacity: ringBufferCapacity
        )

        // Apply initial gains from EQConfiguration
        let inputGainLinear = AudioMath.dbToLinear(eqConfiguration.inputGain)
        let outputGainLinear = AudioMath.dbToLinear(eqConfiguration.outputGain)
        context.targetInputGainLinear = inputGainLinear
        context.targetOutputGainLinear = outputGainLinear
        context.inputGainLinear = inputGainLinear
        context.outputGainLinear = outputGainLinear

        callbackContext = context
        latestMeters = .silent

        let contextPtr = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(context).toOpaque()
        )

        // Register the INPUT callback on the input HAL unit
        if case .failure(let error) = inputManager.setInputCallback(
            Self.inputRenderCallback,
            context: contextPtr
        ) {
            logger.error("Failed to register input callback: \(error.localizedDescription)")
            callbackContext = nil
            renderingEngine?.shutdown()
            renderingEngine = nil
            return .failure(error)
        }

        // Register the OUTPUT callback on the output HAL unit
        if case .failure(let error) = outputManager.setOutputRenderCallback(
            Self.outputRenderCallback,
            context: contextPtr
        ) {
            logger.error("Failed to register output callback: \(error.localizedDescription)")
            _ = inputManager.clearInputCallback()
            callbackContext = nil
            renderingEngine?.shutdown()
            renderingEngine = nil
            return .failure(error)
        }

        // Initialize both HAL units
        if case .failure(let error) = inputManager.initialize() {
            logger.error("Failed to initialize input HAL unit: \(error.localizedDescription)")
            _ = inputManager.clearInputCallback()
            _ = outputManager.clearOutputRenderCallback()
            callbackContext = nil
            renderingEngine?.shutdown()
            renderingEngine = nil
            return .failure(error)
        }

        if case .failure(let error) = outputManager.initialize() {
            logger.error("Failed to initialize output HAL unit: \(error.localizedDescription)")
            inputManager.uninitialize()
            _ = inputManager.clearInputCallback()
            _ = outputManager.clearOutputRenderCallback()
            callbackContext = nil
            renderingEngine?.shutdown()
            renderingEngine = nil
            return .failure(error)
        }

        // Start the input HAL unit first (so it fills the ring buffer)
        if case .failure(let error) = inputManager.start() {
            logger.error("Failed to start input HAL unit: \(error.localizedDescription)")
            inputManager.uninitialize()
            outputManager.uninitialize()
            _ = inputManager.clearInputCallback()
            _ = outputManager.clearOutputRenderCallback()
            callbackContext = nil
            renderingEngine?.shutdown()
            renderingEngine = nil
            return .failure(error)
        }

        // Start the output HAL unit (this drives the output callback)
        if case .failure(let error) = outputManager.start() {
            logger.error("Failed to start output HAL unit: \(error.localizedDescription)")
            _ = inputManager.stop()
            inputManager.uninitialize()
            _ = inputManager.clearInputCallback()
            _ = outputManager.clearOutputRenderCallback()
            callbackContext = nil
            renderingEngine?.shutdown()
            renderingEngine = nil
            return .failure(error)
        }

        isRunning = true
        logger.info("Render pipeline started successfully")
        return .success(())
    }

    /// Stops the render pipeline.
    /// - Returns: Success or an error describing the failure.
    func stop() -> Result<Void, HALIOError> {
        guard isRunning else {
            logger.info("Pipeline not running")
            return .success(())
        }

        logger.info("Stopping render pipeline...")

        var lastError: HALIOError?

        // Stop the output HAL unit first (stops the output callback)
        if let outputManager = outputHALManager {
            if case .failure(let error) = outputManager.stop() {
                lastError = error
            }
            _ = outputManager.clearOutputRenderCallback()
            outputManager.uninitialize()
        }

        // Stop the input HAL unit
        if let inputManager = inputHALManager {
            if case .failure(let error) = inputManager.stop() {
                lastError = error
            }
            _ = inputManager.clearInputCallback()
            inputManager.uninitialize()
        }

        // Log ring buffer diagnostics
        if let context = callbackContext {
            let diag = context.getDiagnostics()
            logger.info("Ring buffer: available=\(diag.availableToRead), underruns=\(diag.underruns), overflows=\(diag.overflows)")
        }

        // Release the callback context
        callbackContext = nil

        // Shutdown the rendering engine
        renderingEngine?.shutdown()
        renderingEngine = nil

        latestMeters = .silent
        callbackContext = nil

        isRunning = false
        logger.info("Render pipeline stopped")

        if let error = lastError {
            return .failure(error)
        }
        return .success(())
    }

    // MARK: - Gain Control

    /// Updates the input gain applied before EQ processing.
    func updateInputGain(linear: Float) {
        callbackContext?.targetInputGainLinear = max(0, linear)
    }

    /// Updates the output gain applied after EQ processing.
    func updateOutputGain(linear: Float) {
        callbackContext?.targetOutputGainLinear = max(0, linear)
    }

    /// Updates the boost gain applied before input gain.
    /// Used for volume boost (>100%) when output device can't go higher.
    /// Linear scale: 1.0 = unity (no boost), 2.0 = 2x boost (6dB gain).
    func updateBoostGain(linear: Float) {
        let context = callbackContext
        logger.debug("updateBoostGain: linear=\(linear), callbackContext=\(context != nil ? "exists" : "nil")")
        context?.targetBoostGainLinear = max(1, linear)
    }

    // MARK: - EQ Control

    /// Updates the processing mode on the live engine and audio thread.
    func updateProcessingMode(systemEQOff: Bool, compareMode: CompareMode) {
        let mode: Int32
        if systemEQOff {
            mode = 0
        } else if compareMode == .flat {
            mode = 2
        } else {
            mode = 1
        }
        callbackContext?.processingMode = mode
        renderingEngine?.updateBypass(systemEQOff: systemEQOff, compareMode: compareMode)
    }

    /// Updates a band's gain on the live engine.
    func updateBandGain(index: Int) {
        renderingEngine?.updateBandGain(index: index)
    }

    /// Updates a band's bandwidth on the live engine.
    func updateBandBandwidth(index: Int) {
        renderingEngine?.updateBandBandwidth(index: index)
    }

    /// Updates a band's frequency on the live engine.
    func updateBandFrequency(index: Int) {
        renderingEngine?.updateBandFrequency(index: index)
    }

    /// Updates a band's filter type on the live engine.
    func updateBandFilterType(index: Int) {
        renderingEngine?.updateBandFilterType(index: index)
    }

    /// Updates a band's bypass state on the live engine.
    func updateBandBypass(index: Int) {
        renderingEngine?.updateBandBypass(index: index)
    }

    /// Reapplies the entire configuration (e.g., after band count changes).
    func reapplyConfiguration() {
        renderingEngine?.reapplyConfiguration()
    }

    /// Returns the most recent meter snapshot from the audio thread.
    func currentMeters() -> LevelMeterSnapshot {
        guard let context = callbackContext else { return latestMeters }
        let snapshot = context.meterSnapshot()
        let rmsSnapshot = context.rmsSnapshot()
        let meters = LevelMeterSnapshot(
            inputDB: snapshot.input,
            outputDB: snapshot.output,
            inputRmsDB: rmsSnapshot.input,
            outputRmsDB: rmsSnapshot.output
        )
        latestMeters = meters
        return meters
    }

    // MARK: - Input Callback

    /// The input render callback. Called by the INPUT HAL unit when it has captured audio.
    /// This callback pulls audio from the input device and writes it to the ring buffers.
    private static let inputRenderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        frameCount,
        ioData
    ) -> OSStatus in

        // Recover the callback context
        let context = Unmanaged<RenderCallbackContext>
            .fromOpaque(inRefCon)
            .takeUnretainedValue()

        guard let inputHALUnit = context.inputHALUnit else {
            // No input HAL unit - nothing to do
            return noErr
        }

        // Prepare the buffer list and pull audio from the input device
        let inputBufferList = context.prepareInputBufferList(frameCount: frameCount)
        var flags = AudioUnitRenderActionFlags()

        let pullStatus = AudioUnitRender(
            inputHALUnit,
            &flags,
            inTimeStamp,
            HALIOManager.inputElementID,
            frameCount,
            inputBufferList
        )

        if pullStatus != noErr {
            // Failed to get input audio - log and skip
            inputCallCount &+= 1
            if inputCallCount % 10000 == 1 {
                staticLogger.error("Input #\(inputCallCount): AudioUnitRender failed with \(pullStatus)")
            }
            return noErr
        }

        // Apply boost gain before input gain (for volume > 100%)
        // Boost compensates for driver volume attenuation and should always be applied.
        context.applyGain(
            to: context.inputSampleBuffers,
            frameCount: frameCount,
            currentGain: &context.boostGainLinear,
            targetGain: context.targetBoostGainLinear
        )

        // Apply input gain before writing to ring buffers (skip in full bypass mode)
        if context.processingMode != 0 {
            context.applyGain(
                to: context.inputSampleBuffers,
                frameCount: frameCount,
                currentGain: &context.inputGainLinear,
                targetGain: context.targetInputGainLinear
            )
        }

        // Write captured audio to ring buffers
        context.writeToRingBuffers(frameCount: frameCount)

        inputCallCount &+= 1

        return noErr
    }

    // MARK: - Output Callback

    /// The output render callback. Called by the OUTPUT HAL unit when it needs audio data.
    /// This callback reads from ring buffers, processes through EQ, and provides output.
    private static let outputRenderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        frameCount,
        ioData
    ) -> OSStatus in

        guard let ioData = ioData else {
            return noErr
        }

        // Recover the callback context
        let context = Unmanaged<RenderCallbackContext>
            .fromOpaque(inRefCon)
            .takeUnretainedValue()

        guard let renderCtx = context.renderContext else {
            // No render context - zero-fill output
            RenderCallbackContext.zeroFill(ioData, frameCount: frameCount)
            return noErr
        }

        // 1. Read audio from ring buffers
        let framesRead = context.readFromRingBuffers(frameCount: frameCount)

        outputCallCount &+= 1

        // If we got no samples, output is already zero-filled by readFromRingBuffers
        if framesRead == 0 {
            // Log underrun occasionally
            if outputCallCount % 1000 == 1 {
                staticLogger.warning("Output #\(outputCallCount): Ring buffer underrun")
            }
            RenderCallbackContext.zeroFill(ioData, frameCount: frameCount)
            context.updateOutputMeters(from: ioData, frameCount: frameCount)
            return noErr
        }

        // 2. Set the input buffers on the render context for the source node to read
        let inputBuffers = context.outputBufferPointers
        renderCtx.setInputBuffers(inputBuffers, frameCount: Int(frameCount))

        // 3. Render through the EQ chain
        let renderStatus = renderCtx.render(
            frameCount: AVAudioFrameCount(frameCount),
            outputBuffer: ioData
        )

        // 4. Clear the input buffer reference
        renderCtx.clearInputBuffer()

        // 5. Apply output gain after EQ rendering (skip in full bypass mode)
        if context.processingMode != 0 {
            context.applyGain(
                to: ioData,
                frameCount: frameCount,
                currentGain: &context.outputGainLinear,
                targetGain: context.targetOutputGainLinear
            )
        }

        // 6. Update output meters with rendered audio
        context.updateOutputMeters(from: ioData, frameCount: frameCount)

        return renderStatus
    }
}
