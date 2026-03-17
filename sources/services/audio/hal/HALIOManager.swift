import AudioToolbox
import CoreAudio
import Foundation
import os.log

/// Specifies whether a HAL audio unit should be configured for input-only or output-only operation.
/// A single HAL unit can only connect to one physical device, so we need separate units for
/// routing audio between different input and output devices.
enum HALIOMode: Sendable {
    /// Input-only mode: Enables element 1 (input) for capturing audio from a device like BlackHole.
    case inputOnly
    /// Output-only mode: Enables element 0 (output) for playing audio to a device like speakers.
    case outputOnly
}

/// Manages a HAL (Hardware Abstraction Layer) output audio unit for low-level
/// device routing. Each instance operates in either input-only or output-only mode,
/// allowing separate units to connect to different physical devices.
@MainActor
final class HALIOManager {
    // MARK: - Properties

    /// The I/O mode this manager was configured with.
    private let ioMode: HALIOMode

    /// The underlying HAL output audio unit instance.
    /// Marked nonisolated(unsafe) to allow cleanup in deinit.
    private nonisolated(unsafe) var audioUnit: AudioComponentInstance?

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "HALIO")

    /// The currently configured device ID, or 0 if not set.
    private(set) var currentDeviceID: AudioDeviceID = 0

    /// Whether the audio unit has been initialized via `AudioUnitInitialize`.
    /// Marked nonisolated(unsafe) to allow cleanup in deinit.
    private nonisolated(unsafe) var isInitialized: Bool = false

    /// Whether the audio unit is currently running (started).
    /// Marked nonisolated(unsafe) to allow cleanup in deinit.
    private nonisolated(unsafe) var isRunning: Bool = false

    /// Whether the audio unit has been configured with a device.
    private var isConfigured: Bool = false

    // MARK: - Constants

    /// Input element (bus) for HAL output unit - used for capturing audio.
    private let inputElement: AudioUnitElement = 1

    /// Output element (bus) for HAL output unit - used for playback.
    private let outputElement: AudioUnitElement = 0

    // MARK: - Initialization

    /// Creates a new HAL I/O manager for the specified mode.
    /// - Parameter mode: Whether this manager should operate in input-only or output-only mode.
    init(mode: HALIOMode) {
        self.ioMode = mode
    }

    deinit {
        // Cleanup must happen synchronously in deinit.
        if let unit = audioUnit {
            if isRunning {
                AudioOutputUnitStop(unit)
            }
            if isInitialized {
                AudioUnitUninitialize(unit)
            }
            AudioComponentInstanceDispose(unit)
        }
    }

    // MARK: - Configuration (Main Entry Point)

    /// Configures the HAL audio unit with the specified device.
    /// This is the main entry point for setting up the audio unit. It performs
    /// all necessary steps in the correct order:
    /// 1. Creates the audio unit instance
    /// 2. Enables I/O on the appropriate element based on mode
    /// 3. Sets the device on the appropriate element
    /// 4. Configures stream formats
    ///
    /// - Parameter deviceID: The Core Audio device ID to use.
    /// - Returns: Success or an error describing the failure.
    func configure(deviceID: AudioDeviceID) -> Result<Void, HALIOError> {
        logger.info("Configuring HAL unit (\(String(describing: self.ioMode))): device=\(deviceID)")

        // If already configured, dispose the old unit first
        if audioUnit != nil {
            dispose()
        }

        // Step 1: Create the audio unit instance
        if case .failure(let error) = createAudioUnit() {
            return .failure(error)
        }

        // Step 2: Enable I/O on the appropriate element based on mode
        if case .failure(let error) = enableIO() {
            dispose()
            return .failure(error)
        }

        // Step 3: Set the device on the appropriate element
        if case .failure(let error) = setDevice(id: deviceID) {
            dispose()
            return .failure(error)
        }

        // Step 4: Configure stream formats
        if case .failure(let error) = configureFormats() {
            dispose()
            return .failure(error)
        }

        isConfigured = true
        logger.info("HAL unit configured successfully (\(String(describing: self.ioMode)))")
        return .success(())
    }

    // MARK: - Audio Unit Creation (Private)

    /// Creates the HAL output audio unit instance.
    /// - Returns: Success or an error describing the failure.
    private func createAudioUnit() -> Result<Void, HALIOError> {
        // Find the HAL output component
        guard let component = findHALOutputComponent() else {
            logger.error("HAL output component not found")
            return .failure(.componentNotFound)
        }

        // Create an instance
        var instance: AudioComponentInstance?
        let status = AudioComponentInstanceNew(component, &instance)

        guard status == noErr, let unit = instance else {
            logger.error("Failed to create audio unit instance: \(status)")
            return .failure(.instanceCreationFailed(status))
        }

        audioUnit = unit
        logger.debug("Audio unit instance created")
        return .success(())
    }

    /// Finds the HAL output audio component.
    private func findHALOutputComponent() -> AudioComponent? {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AudioComponentFindNext(nil, &description)
    }

    // MARK: - Device Selection (Private)

    /// Sets the device on the appropriate element based on the I/O mode.
    private func setDevice(id: AudioDeviceID) -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        // Determine which element to use based on mode
        let element: AudioUnitElement
        let scopeName: String

        switch ioMode {
        case .inputOnly:
            element = inputElement
            scopeName = "input"
        case .outputOnly:
            element = outputElement
            scopeName = "output"
        }

         var deviceID = id
         let status = AudioUnitSetProperty(
             unit,
             kAudioOutputUnitProperty_CurrentDevice,
             kAudioUnitScope_Global,
             element,
             &deviceID,
             UInt32(MemoryLayout<AudioDeviceID>.size)
         )

        if status != noErr {
            logger.error("Failed to set \(scopeName) device \(id): \(status)")
            return .failure(.deviceSetFailed(scope: scopeName, status))
        }

        currentDeviceID = id
        logger.debug("\(scopeName.capitalized) device set to ID: \(id)")
        return .success(())
    }

    // MARK: - I/O Configuration (Private)

    /// Enables I/O on the appropriate element based on the I/O mode.
    /// For inputOnly mode: enables input element (1) and disables output element (0).
    /// For outputOnly mode: enables output element (0) - input is disabled by default.
    private func enableIO() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        var enableFlag: UInt32 = 1
        var disableFlag: UInt32 = 0

        switch ioMode {
        case .inputOnly:
            // Enable input on element 1 (input scope)
            let inputStatus = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                inputElement,
                &enableFlag,
                UInt32(MemoryLayout<UInt32>.size)
            )

            if inputStatus != noErr {
                logger.error("Failed to enable input I/O: \(inputStatus)")
                return .failure(.enableIOFailed(scope: "input", inputStatus))
            }

            // Disable output on element 0 (output scope) - we only want input
            let outputStatus = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                outputElement,
                &disableFlag,
                UInt32(MemoryLayout<UInt32>.size)
            )

            if outputStatus != noErr {
                logger.error("Failed to disable output I/O: \(outputStatus)")
                return .failure(.enableIOFailed(scope: "output", outputStatus))
            }

            logger.debug("I/O enabled on input element only")

        case .outputOnly:
            // Output is enabled by default for HAL output units, but let's be explicit
            let outputStatus = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                outputElement,
                &enableFlag,
                UInt32(MemoryLayout<UInt32>.size)
            )

            if outputStatus != noErr {
                logger.error("Failed to enable output I/O: \(outputStatus)")
                return .failure(.enableIOFailed(scope: "output", outputStatus))
            }

            logger.debug("I/O enabled on output element only")
        }

        return .success(())
    }

    // MARK: - Format Configuration (Private)

    /// Configures stream formats on the audio unit based on the I/O mode.
    /// Sets up non-interleaved Float32 format for compatibility with AVAudioEngine.
    private func configureFormats() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        switch ioMode {
        case .inputOnly:
            // Get the hardware format from the input element's input scope (what the device provides)
            var hardwareFormat = AudioStreamBasicDescription()
            let queryStatus = AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                inputElement,
                &hardwareFormat,
                &size
            )

            if queryStatus != noErr {
                logger.error("Failed to get input hardware format: \(queryStatus)")
                return .failure(.formatQueryFailed(queryStatus))
            }

            logger.debug(
                "Input hardware format: \(hardwareFormat.mSampleRate) Hz, \(hardwareFormat.mChannelsPerFrame) ch"
            )

            // Set the output scope of input element (what we read in our callback)
            // Use non-interleaved format for AVAudioEngine compatibility
            var clientFormat = createNonInterleavedFormat(
                sampleRate: hardwareFormat.mSampleRate,
                channelCount: hardwareFormat.mChannelsPerFrame
            )

            let setStatus = AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                inputElement,
                &clientFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )

            if setStatus != noErr {
                logger.error("Failed to set input client format: \(setStatus)")
                return .failure(.formatSetFailed(setStatus))
            }

            logger.info(
                "Input format configured: \(clientFormat.mSampleRate) Hz, \(clientFormat.mChannelsPerFrame) ch, non-interleaved"
            )

        case .outputOnly:
            // Get the hardware format from the output element's output scope (what the device expects)
            var hardwareFormat = AudioStreamBasicDescription()
            let queryStatus = AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                outputElement,
                &hardwareFormat,
                &size
            )

            if queryStatus != noErr {
                logger.error("Failed to get output hardware format: \(queryStatus)")
                return .failure(.formatQueryFailed(queryStatus))
            }

            logger.debug(
                "Output hardware format: \(hardwareFormat.mSampleRate) Hz, \(hardwareFormat.mChannelsPerFrame) ch"
            )

            // Set the input scope of output element (what we provide in our callback)
            // Use non-interleaved format for AVAudioEngine compatibility
            var clientFormat = createNonInterleavedFormat(
                sampleRate: hardwareFormat.mSampleRate,
                channelCount: hardwareFormat.mChannelsPerFrame
            )

            let setStatus = AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                outputElement,
                &clientFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )

            if setStatus != noErr {
                logger.error("Failed to set output client format: \(setStatus)")
                return .failure(.formatSetFailed(setStatus))
            }

            logger.info(
                "Output format configured: \(clientFormat.mSampleRate) Hz, \(clientFormat.mChannelsPerFrame) ch, non-interleaved"
            )
        }

        return .success(())
    }

    /// Creates a non-interleaved (deinterleaved) Float32 audio stream format.
    /// - Parameters:
    ///   - sampleRate: The sample rate in Hz.
    ///   - channelCount: The number of audio channels.
    /// - Returns: An AudioStreamBasicDescription configured for non-interleaved Float32.
    private func createNonInterleavedFormat(
        sampleRate: Float64,
        channelCount: UInt32
    ) -> AudioStreamBasicDescription {
        // Non-interleaved format flags:
        // - kAudioFormatFlagIsFloat: samples are floating point
        // - kAudioFormatFlagIsPacked: samples are packed (no padding)
        // - kAudioFormatFlagIsNonInterleaved: each channel in its own buffer
        let formatFlags: AudioFormatFlags =
            kAudioFormatFlagIsFloat |
            kAudioFormatFlagIsPacked |
            kAudioFormatFlagIsNonInterleaved

        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: formatFlags,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size),
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: UInt32(MemoryLayout<Float32>.size * 8),
            mReserved: 0
        )
    }

    // MARK: - Stream Format Query (Public)

    /// Returns the current stream format for the specified scope and element.
    /// - Parameters:
    ///   - scope: The audio unit scope (input or output).
    ///   - element: The element (bus) number.
    /// - Returns: The stream format or an error.
    func getStreamFormat(
        scope: AudioUnitScope,
        element: AudioUnitElement
    ) -> Result<AudioStreamBasicDescription, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            scope,
            element,
            &format,
            &size
        )

        if status != noErr {
            return .failure(.formatQueryFailed(status))
        }

        return .success(format)
    }

    /// Returns the client format for this HAL manager (the format used for audio processing).
    /// For inputOnly mode, returns the output scope of the input element.
    /// For outputOnly mode, returns the input scope of the output element.
    func getClientFormat() -> Result<AudioStreamBasicDescription, HALIOError> {
        switch ioMode {
        case .inputOnly:
            return getStreamFormat(scope: kAudioUnitScope_Output, element: inputElement)
        case .outputOnly:
            return getStreamFormat(scope: kAudioUnitScope_Input, element: outputElement)
        }
    }

    /// The I/O mode this manager was configured with.
    var mode: HALIOMode { ioMode }

    // MARK: - Lifecycle Controls

    /// Initializes the audio unit. Must be called after configure(), before start().
    /// - Returns: Success or an error describing the failure.
    func initialize() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        guard isConfigured else {
            logger.error("Cannot initialize: audio unit not configured")
            return .failure(.notInitialized)
        }

        guard !isInitialized else {
            logger.debug("Audio unit already initialized")
            return .success(())
        }

        let status = AudioUnitInitialize(unit)

        if status != noErr {
            logger.error("Failed to initialize audio unit: \(status)")
            return .failure(.initializationFailed(status))
        }

        isInitialized = true
        logger.info("Audio unit initialized")
        return .success(())
    }

    /// Starts the audio unit, beginning audio processing.
    /// - Returns: Success or an error describing the failure.
    func start() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        guard isInitialized else {
            logger.error("Cannot start: audio unit not initialized")
            return .failure(.notInitialized)
        }

        guard !isRunning else {
            logger.debug("Audio unit already running")
            return .failure(.alreadyRunning)
        }

        let status = AudioOutputUnitStart(unit)

        if status != noErr {
            logger.error("Failed to start audio unit: \(status)")
            return .failure(.startFailed(status))
        }

        isRunning = true
        logger.info("Audio unit started (\(String(describing: self.ioMode)))")
        return .success(())
    }

    /// Stops the audio unit, halting audio processing.
    /// - Returns: Success or an error describing the failure.
    func stop() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        guard isRunning else {
            logger.debug("Audio unit not running")
            return .success(())
        }

        let status = AudioOutputUnitStop(unit)

        if status != noErr {
            logger.error("Failed to stop audio unit: \(status)")
            return .failure(.stopFailed(status))
        }

        isRunning = false
        logger.info("Audio unit stopped")
        return .success(())
    }

    /// Uninitializes the audio unit.
    func uninitialize() {
        guard let unit = audioUnit else { return }

        if isRunning {
            _ = stop()
        }

        if isInitialized {
            AudioUnitUninitialize(unit)
            isInitialized = false
            logger.debug("Audio unit uninitialized")
        }
    }

    /// Disposes of the audio unit, releasing all resources.
    private func dispose() {
        uninitialize()

        if let unit = audioUnit {
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }

        currentDeviceID = 0
        isConfigured = false
        logger.debug("Audio unit disposed")
    }

    // MARK: - Status

    /// Returns whether the audio unit is configured and ready for initialization.
    var isReady: Bool {
        audioUnit != nil && isConfigured
    }

    // MARK: - Callback Registration

    /// Sets the render callback for the output element.
    /// This callback is invoked when the HAL unit needs audio data to play.
    /// - Parameters:
    ///   - callback: The render callback function (C function pointer).
    ///   - context: An opaque pointer passed to the callback as `inRefCon`.
    /// - Returns: Success or an error describing the failure.
    func setOutputRenderCallback(
        _ callback: @escaping AURenderCallback,
        context: UnsafeMutableRawPointer
    ) -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: callback,
            inputProcRefCon: context
        )

        let status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            outputElement,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to set output render callback: \(status)")
            return .failure(.callbackRegistrationFailed(scope: "output", status))
        }

        logger.info("Output render callback registered")
        return .success(())
    }

    /// Clears the render callback for the output element.
    /// - Returns: Success or an error describing the failure.
    func clearOutputRenderCallback() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: nil,
            inputProcRefCon: nil
        )

        let status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            outputElement,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to clear output render callback: \(status)")
            return .failure(.callbackRegistrationFailed(scope: "output", status))
        }

        logger.debug("Output render callback cleared")
        return .success(())
    }

    /// Sets the input callback for capturing audio from the input device.
    /// This callback is invoked when the HAL unit has captured audio data.
    /// Only valid for `.inputOnly` mode.
    ///
    /// - Parameters:
    ///   - callback: The input callback function (C function pointer).
    ///   - context: An opaque pointer passed to the callback as `inRefCon`.
    /// - Returns: Success or an error describing the failure.
    func setInputCallback(
        _ callback: @escaping AURenderCallback,
        context: UnsafeMutableRawPointer
    ) -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        guard ioMode == .inputOnly else {
            logger.error("Input callback can only be set on inputOnly mode HAL units")
            return .failure(.callbackRegistrationFailed(scope: "input", -50))
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: callback,
            inputProcRefCon: context
        )

        // For input capture, we use kAudioOutputUnitProperty_SetInputCallback
        // on the output scope of element 0.
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to set input callback: \(status)")
            return .failure(.callbackRegistrationFailed(scope: "input", status))
        }

        logger.info("Input callback registered")
        return .success(())
    }

    /// Clears the input callback.
    /// - Returns: Success or an error describing the failure.
    func clearInputCallback() -> Result<Void, HALIOError> {
        guard let unit = audioUnit else {
            return .failure(.unitNotAvailable)
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: nil,
            inputProcRefCon: nil
        )

        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to clear input callback: \(status)")
            return .failure(.callbackRegistrationFailed(scope: "input", status))
        }

        logger.debug("Input callback cleared")
        return .success(())
    }

    // MARK: - Unsafe Access for Callbacks

    /// Provides direct access to the audio unit for use in render callbacks.
    /// - Warning: Only access this from the audio render thread. Do not store
    ///   or use outside the callback context.
    nonisolated var unsafeAudioUnit: AudioComponentInstance? {
        audioUnit
    }

    /// The input element constant, accessible from callbacks.
    nonisolated static let inputElementID: AudioUnitElement = 1

    /// The output element constant, accessible from callbacks.
    nonisolated static let outputElementID: AudioUnitElement = 0
}
