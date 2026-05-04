import AudioToolbox
import Atomics
import CoreAudio
import os.log

/// Context passed to both the input and output HAL render callbacks.
/// Contains ring buffers for inter-callback communication and all state
/// needed for real-time audio processing without requiring any allocations or locks.
///
/// Data flow (HAL input mode — ring buffers):
/// 1. Input callback captures audio from device → writes to ring buffers
/// 2. Output callback reads from ring buffers → processes through EQ → outputs
///
/// Data flow (shared memory capture mode — direct):
/// 1. Output callback polls driver shared memory → writes directly to inputBuffers
/// 2. Output callback processes inputBuffers through EQ → outputs
///    (bypasses intermediate AudioRingBuffer since both steps run on the same thread)
///
/// - Important: This class is `@unchecked Sendable` because it is accessed from
///   both the main thread (for setup) and the audio render thread (for processing).
///   All mutable state is designed for single-writer/single-reader access patterns.
final class RenderCallbackContext: @unchecked Sendable {
    // MARK: - Properties

    private static let maxMeterChannels = MeterConstants.maxMeterChannels
    private static let silenceDB: Float = MeterConstants.silenceDB

    /// Ring buffers for audio samples (one per channel).
    /// Written by input callback, read by output callback.
    let ringBuffers: [AudioRingBuffer]

    /// The INPUT HAL audio unit for pulling audio in the input callback.
    /// The input callback uses AudioUnitRender on this unit to get captured samples.
    let inputHALUnit: AudioComponentInstance?

    /// Per-channel EQ chain arrays. Index = layer (0 = user EQ, 1+ = future layers).
    /// Pre-allocated at init. Unused layers are passthrough (0 active bands).
    /// Left channel chains for left speaker, right channel chains for right speaker.
    let leftEQChains: [EQChain]
    let rightEQChains: [EQChain]

    /// Number of audio channels.
    let channelCount: UInt32

    /// Maximum number of frames per callback.
    let maxFrameCount: UInt32

    /// Driver capture for shared memory polling (optional, only in shared memory mode).
    /// When set, the output callback will poll the driver before reading from ring buffers.
    private nonisolated(unsafe) var driverCapture: DriverCapture?

    /// Pre-allocated buffers for input audio samples (one per channel for deinterleaved layout).
    /// Used by the input callback when pulling audio from the input HAL unit.
    private let inputBuffers: [UnsafeMutablePointer<Float>]

    /// Size of each channel buffer in samples (frames per channel).
    private let framesPerBuffer: Int

    /// Pre-allocated AudioBufferList with proper memory layout for multiple buffers.
    /// Used by the input callback to receive audio from AudioUnitRender.
    private let inputBufferListPtr: UnsafeMutablePointer<AudioBufferList>

    /// Size of the allocated AudioBufferList in bytes.
    private let inputBufferListSize: Int

    /// Pre-allocated buffers for reading from ring buffers (output callback).
    /// One per channel.
    private let outputReadBuffers: [UnsafeMutablePointer<Float>]

    /// The buffers that EQ and output copy operate on.
    /// In direct capture mode: inputBuffers (no intermediate ring buffer).
    /// In ring buffer mode: outputReadBuffers (read from AudioRingBuffer).
    private nonisolated(unsafe) var processingBuffers: [UnsafeMutablePointer<Float>]!

    /// Immutable pointers to processingBuffers (avoids array allocation in hot paths).
    private nonisolated(unsafe) var processingBufferPointers: [UnsafePointer<Float>]!

    // MARK: - Atomic Target Gains
    // Target gains are written by the main thread and read by the audio thread.
    // We use atomic Int32 storage with Float bit-casting for thread-safe access.
    // Float is not directly supported by Swift Atomics, so we use Int32 bit patterns.
    // Relaxed memory ordering is sufficient for single-writer/single-reader scenarios
    // where slight staleness is acceptable for audio processing.

    /// Target linear gain for input (stored as Int32 bit pattern of Float).
    /// Written by main thread, read by audio thread.
    private let targetInputGainAtomic: ManagedAtomic<Int32> = ManagedAtomic(1065353216) // Float 1.0 as Int32 bits (0x3F800000)

    /// Target linear gain for output (stored as Int32 bit pattern of Float).
    /// Written by main thread, read by audio thread.
    private let targetOutputGainAtomic: ManagedAtomic<Int32> = ManagedAtomic(1065353216) // Float 1.0 as Int32 bits (0x3F800000)

    /// Target boost gain (stored as Int32 bit pattern of Float).
    /// Written by main thread, read by audio thread.
    private let targetBoostGainAtomic: ManagedAtomic<Int32> = ManagedAtomic(1065353216) // Float 1.0 as Int32 bits (0x3F800000)

    /// Stopping flag (stored as Int32 for atomic access).
    /// Set to 1 by main thread before stopping HAL units. Read by audio thread.
    /// When true, callbacks zero-fill output and return immediately — prevents
    /// use-after-free if HAL calls the callback between AudioOutputUnitStop and
    /// callbackContext deallocation.
    private let isStoppingAtomic: ManagedAtomic<Int32> = ManagedAtomic(0) // false

    /// Meters enabled flag (stored as Int32 for atomic access).
    /// Written by main thread, read by audio thread.
    /// When false, meter calculations are skipped entirely.
    private let metersEnabledAtomic: ManagedAtomic<Int32> = ManagedAtomic(0) // false

    // MARK: - Current Gains (Audio Thread Only)
    // Current gains are ONLY written by the audio thread during gain ramping.
    // They can be read for diagnostics, but should not be written from any other thread.

    /// Current linear gain for input (audio thread only).
    nonisolated(unsafe) var inputGainLinear: Float = 1.0

    /// Current linear gain for output (audio thread only).
    nonisolated(unsafe) var outputGainLinear: Float = 1.0

    /// Current boost gain (audio thread only).
    nonisolated(unsafe) var boostGainLinear: Float = 1.0

    // MARK: - Gain Update API (Main Thread)

    /// Updates the target input gain (called from main thread).
    /// - Parameter linear: Linear gain value (will be clamped to >= 0).
    func setTargetInputGain(_ linear: Float) {
        let clamped = max(0, linear)
        let bits = Int32(bitPattern: clamped.bitPattern)
        targetInputGainAtomic.store(bits, ordering: .relaxed)
    }

    /// Updates the target output gain (called from main thread).
    /// - Parameter linear: Linear gain value (will be clamped to >= 0).
    func setTargetOutputGain(_ linear: Float) {
        let clamped = max(0, linear)
        let bits = Int32(bitPattern: clamped.bitPattern)
        targetOutputGainAtomic.store(bits, ordering: .relaxed)
    }

    /// Updates the target boost gain (called from main thread).
    /// - Parameter linear: Linear gain value (will be clamped to >= 1).
    func setTargetBoostGain(_ linear: Float) {
        let clamped = max(1, linear)
        let bits = Int32(bitPattern: clamped.bitPattern)
        targetBoostGainAtomic.store(bits, ordering: .relaxed)
    }

    /// Updates the meters enabled state (called from main thread).
    /// When disabled, meter calculations are skipped on the audio thread.
    func setMetersEnabled(_ enabled: Bool) {
        metersEnabledAtomic.store(enabled ? 1 : 0, ordering: .relaxed)
    }

    /// Sets the stopping flag (called from main thread before HAL stop).
    /// When true, render callbacks output silence and return early.
    func setIsStopping(_ stopping: Bool) {
        isStoppingAtomic.store(stopping ? 1 : 0, ordering: .relaxed)
    }

    /// Checks if the pipeline is stopping (called from audio thread).
    /// Returns true if callbacks should output silence and return early.
    var isStopping: Bool {
        isStoppingAtomic.load(ordering: .relaxed) != 0
    }

    // MARK: - Gain Read API (Audio Thread or Diagnostics)

    /// Returns the current target input gain.
    func getTargetInputGain() -> Float {
        Float(bitPattern: UInt32(bitPattern: targetInputGainAtomic.load(ordering: .relaxed)))
    }

    /// Returns the current target output gain.
    func getTargetOutputGain() -> Float {
        Float(bitPattern: UInt32(bitPattern: targetOutputGainAtomic.load(ordering: .relaxed)))
    }

    /// Returns the current target boost gain.
    func getTargetBoostGain() -> Float {
        Float(bitPattern: UInt32(bitPattern: targetBoostGainAtomic.load(ordering: .relaxed)))
    }

    /// Processing mode for audio thread:
    /// 0 = full bypass (System EQ OFF) - skip gains, bypass EQ
    /// 1 = normal (EQ + gains)
    /// 2 = gains only (Compare Flat mode) - apply gains, bypass EQ
    nonisolated(unsafe) var processingMode: Int32 = 1

    /// Number of channels exposed to the level meters (up to two for stereo visualization).
    private let meterChannelCount: Int

    /// Storage for latest input peak levels per channel (in dBFS).
    private let inputMeterStorage: UnsafeMutablePointer<Float>

    /// Storage for latest output peak levels per channel (in dBFS).
    private let outputMeterStorage: UnsafeMutablePointer<Float>

    /// Storage for latest input RMS levels per channel (in dBFS).
    private let inputRmsStorage: UnsafeMutablePointer<Float>

    /// Storage for latest output RMS levels per channel (in dBFS).
    private let outputRmsStorage: UnsafeMutablePointer<Float>

    /// Pre-allocated arrays for audio thread (avoid heap allocation in hot paths).
    /// Reused in applyGain(to: UnsafeMutablePointer<AudioBufferList>...) and updateOutputMeters.
    private var gainBuffers: [UnsafeMutablePointer<Float>] = []
    private var meterChannelPointers: [UnsafePointer<Float>] = []

    /// Pre-computed output buffer pointers (immutable, avoids array allocation on every callback).
    private let outputBufferPointersPrecomputed: [UnsafePointer<Float>]

    /// Pre-computed input buffer pointers (immutable, avoids array allocation in provideFrames).
    private let inputBufferPointers: [UnsafePointer<Float>]

    /// Pre-computed input buffer mutable pointers (immutable, avoids array allocation in provideFrames).
    private let inputBufferMutablePointers: [UnsafeMutablePointer<Float>]

    // MARK: - Driver Capture

    /// Sets the driver capture instance for polling.
    /// When set, the output callback uses direct capture mode: shared memory is polled
    /// directly into inputBuffers, bypassing the intermediate AudioRingBuffer.
    /// When cleared, reverts to ring buffer mode for HAL input capture.
    func setDriverCapture(_ capture: DriverCapture?) {
        driverCapture = capture
        if capture != nil {
            // Direct capture: EQ and output operate on inputBuffers directly,
            // avoiding two unnecessary memcpy operations through the ring buffer.
            processingBuffers = inputBuffers
            processingBufferPointers = inputBufferPointers
        } else {
            // Ring buffer mode: EQ and output operate on outputReadBuffers
            // (filled from AudioRingBuffer by readFromRingBuffers).
            processingBuffers = outputReadBuffers
            processingBufferPointers = outputBufferPointersPrecomputed
        }
    }

    // MARK: - Initialization

    /// Creates a new callback context with ring buffers and pre-allocated audio buffers.
    /// - Parameters:
    ///   - inputHALUnit: The INPUT HAL audio unit instance for capturing audio.
    ///   - channelCount: Number of audio channels.
    ///   - maxFrameCount: Maximum frames per callback (used for buffer sizing).
    ///   - ringBufferCapacity: Capacity of each ring buffer in samples (default from AudioConstants).
    init(
        inputHALUnit: AudioComponentInstance?,
        channelCount: UInt32,
        maxFrameCount: UInt32,
        ringBufferCapacity: Int = AudioConstants.ringBufferCapacity
    ) {
        self.inputHALUnit = inputHALUnit
        self.channelCount = channelCount
        self.maxFrameCount = maxFrameCount
        self.framesPerBuffer = Int(maxFrameCount)
        self.meterChannelCount = min(Int(channelCount), Self.maxMeterChannels)

        // Create EQ chains (one per layer per channel)
        let layerCount = EQLayerConstants.maxLayerCount
        self.leftEQChains = (0..<layerCount).map { _ in EQChain(maxFrameCount: maxFrameCount) }
        self.rightEQChains = (0..<layerCount).map { _ in EQChain(maxFrameCount: maxFrameCount) }

        // Create ring buffers (one per channel)
        var rings: [AudioRingBuffer] = []
        for _ in 0..<channelCount {
            rings.append(AudioRingBuffer(capacity: ringBufferCapacity))
        }
        self.ringBuffers = rings

        // Pre-allocate one buffer per channel for input callback (deinterleaved layout)
        var inputBufs: [UnsafeMutablePointer<Float>] = []
        for _ in 0..<channelCount {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: framesPerBuffer)
            buffer.initialize(repeating: 0, count: framesPerBuffer)
            inputBufs.append(buffer)
        }
        self.inputBuffers = inputBufs

        // Pre-allocate one buffer per channel for output callback reads
        var outputBufs: [UnsafeMutablePointer<Float>] = []
        for _ in 0..<channelCount {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: framesPerBuffer)
            buffer.initialize(repeating: 0, count: framesPerBuffer)
            outputBufs.append(buffer)
        }
        self.outputReadBuffers = outputBufs

        // Pre-compute output buffer pointers (avoid array allocation on every callback)
        self.outputBufferPointersPrecomputed = outputBufs.map { UnsafePointer($0) }

        // Pre-compute input buffer pointer arrays (avoid array allocation in provideFrames)
        self.inputBufferPointers = inputBufs.map { UnsafePointer($0) }
        self.inputBufferMutablePointers = inputBufs

        // Default processing buffers to outputReadBuffers (HAL input / ring buffer mode).
        // Switched to inputBuffers when setDriverCapture() enables direct capture mode.
        self.processingBuffers = outputReadBuffers
        self.processingBufferPointers = outputBufferPointersPrecomputed

        self.inputMeterStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        self.outputMeterStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        self.inputRmsStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        self.outputRmsStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        inputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        outputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        inputRmsStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        outputRmsStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)

        // Pre-allocate arrays for audio thread hot paths
        gainBuffers.reserveCapacity(Int(channelCount))
        meterChannelPointers.reserveCapacity(Int(channelCount))

        // Calculate size for AudioBufferList with `channelCount` buffers
        // AudioBufferList has 1 AudioBuffer inline, so we need space for (channelCount - 1) additional
        let additionalBuffers = max(0, Int(channelCount) - 1)
        self.inputBufferListSize = MemoryLayout<AudioBufferList>.size
            + additionalBuffers * MemoryLayout<AudioBuffer>.size

        // Allocate and initialize the AudioBufferList
        self.inputBufferListPtr = UnsafeMutableRawPointer
            .allocate(byteCount: inputBufferListSize, alignment: MemoryLayout<AudioBufferList>.alignment)
            .assumingMemoryBound(to: AudioBufferList.self)

        // Set up the buffer list structure
        inputBufferListPtr.pointee.mNumberBuffers = channelCount

        // Get pointer to the mBuffers array
        let buffersPtr = UnsafeMutableAudioBufferListPointer(inputBufferListPtr)
        for (index, buffer) in buffersPtr.enumerated() {
            // Each buffer holds one channel
            var mutableBuffer = buffer
            mutableBuffer.mNumberChannels = 1
            mutableBuffer.mDataByteSize = UInt32(framesPerBuffer * MemoryLayout<Float>.size)
            mutableBuffer.mData = UnsafeMutableRawPointer(inputBuffers[index])
            buffersPtr[index] = mutableBuffer
        }
    }

    deinit {
        // Deallocate input channel buffers
        for buffer in inputBuffers {
            buffer.deinitialize(count: framesPerBuffer)
            buffer.deallocate()
        }

        // Deallocate output read buffers
        for buffer in outputReadBuffers {
            buffer.deinitialize(count: framesPerBuffer)
            buffer.deallocate()
        }

        inputMeterStorage.deinitialize(count: meterChannelCount)
        inputMeterStorage.deallocate()
        outputMeterStorage.deinitialize(count: meterChannelCount)
        outputMeterStorage.deallocate()
        inputRmsStorage.deinitialize(count: meterChannelCount)
        inputRmsStorage.deallocate()
        outputRmsStorage.deinitialize(count: meterChannelCount)
        outputRmsStorage.deallocate()

        // Deallocate the AudioBufferList
        inputBufferListPtr.deallocate()
    }

    // MARK: - Input Callback Support

    /// Returns a pointer to the pre-allocated input buffer list, sized for the given frame count.
    /// Used by the input callback to receive audio from AudioUnitRender.
    /// - Parameter frameCount: The number of frames to be rendered.
    /// - Returns: A pointer to the AudioBufferList.
    func prepareInputBufferList(frameCount: UInt32) -> UnsafeMutablePointer<AudioBufferList> {
        // Update the byte size for this render pass on each buffer
        let byteSize = frameCount * UInt32(MemoryLayout<Float>.size)
        let buffersPtr = UnsafeMutableAudioBufferListPointer(inputBufferListPtr)

        for index in 0..<Int(channelCount) {
            buffersPtr[index].mDataByteSize = byteSize
        }

        return inputBufferListPtr
    }

    /// Writes captured audio samples to the ring buffers.
    /// Called by the input callback after AudioUnitRender succeeds.
    /// - Parameter frameCount: Number of frames to write.
    @inline(__always)
    func writeToRingBuffers(frameCount: UInt32) {
        let count = Int(frameCount)
        for (index, ringBuffer) in ringBuffers.enumerated() {
            _ = ringBuffer.write(inputBuffers[index], count: count)
        }
        updateMeterStorage(storage: inputMeterStorage, rmsStorage: inputRmsStorage, with: inputBufferPointers, frameCount: count)
    }

    /// Direct access to the input sample buffers (for diagnostics/debugging).
    var inputSampleBuffers: [UnsafeMutablePointer<Float>] {
        inputBuffers
    }

    /// Applies gain to a set of channel buffers, with per-callback ramping.
    @inline(__always)
    func applyGain(
        to buffers: [UnsafeMutablePointer<Float>],
        frameCount: UInt32,
        currentGain: inout Float,
        targetGain: Float
    ) {
        let count = Int(frameCount)
        guard count > 0 else {
            currentGain = targetGain
            return
        }

        let gainDelta = targetGain - currentGain
        let gainStep = gainDelta / Float(count)
        var gain = currentGain
        var index = 0

        while index < count {
            for buffer in buffers {
                buffer[index] *= gain
            }
            gain += gainStep
            index += 1
        }

        currentGain = targetGain
    }

    // MARK: - Output Callback Support

    /// Provides frames for processing, handling both direct capture and ring buffer modes.
    ///
    /// In direct capture mode (driverCapture set): polls shared memory directly into
    /// inputBuffers (= processingBuffers), bypassing the intermediate AudioRingBuffer.
    ///
    /// In ring buffer mode (driverCapture nil): reads from AudioRingBuffer into
    /// outputReadBuffers (= processingBuffers). This is used by HAL input capture
    /// where producer and consumer run on different threads.
    ///
    /// - Parameter frameCount: Maximum frames to provide (typically the output callback's frameCount).
    /// - Returns: Number of frames available in processingBuffers, or 0 if no data.
    @inline(__always)
    func provideFrames(frameCount: UInt32) -> Int {
        if let capture = driverCapture {
            // Direct capture: poll shared memory → inputBuffers (= processingBuffers)
            // Read exactly frameCount frames (the output device's requested amount).
            // The shared memory ring (65536 frames) absorbs clock drift — we consume
            // at the output device's rate, not the driver's rate. This prevents
            // over-consumption that causes periodic overflow resets and artefacts.
            guard let (polled, _, channelCount) = capture.pollIntoBuffers(
                destBuffers: inputBuffers,
                maxFrames: frameCount
            ) else { return 0 }

            guard channelCount == self.channelCount else { return 0 }

            let polledCount = Int(polled)
            let requestedCount = Int(frameCount)

            // Zero-fill the remainder on underrun to prevent stale data from
            // the previous callback leaking through.
            if polledCount < requestedCount {
                for buffer in inputBuffers {
                    memset(buffer + polledCount, 0,
                           (requestedCount - polledCount) * MemoryLayout<Float>.size)
                }
            }

            // Apply input gain to the full frameCount (skip in full bypass mode).
            // Using frameCount (not polled) ensures gain ramp state stays correct
            // across callbacks, even when partial data was read.
            // Note: Boost gain is NOT applied here - in shared memory mode, samples come
            // from the driver at full volume regardless of macOS volume setting.
            if processingMode != 0 {
                let targetInputGain = getTargetInputGain()
                applyGain(to: inputBufferMutablePointers, frameCount: frameCount,
                          currentGain: &inputGainLinear, targetGain: targetInputGain)
            }

            // Update input meters
            updateMeterStorage(storage: inputMeterStorage, rmsStorage: inputRmsStorage,
                               with: inputBufferPointers, frameCount: requestedCount)
            return requestedCount
        } else {
            // Ring buffer mode: read from AudioRingBuffer → outputReadBuffers (= processingBuffers)
            return readFromRingBuffers(frameCount: frameCount)
        }
    }

    /// Reads audio samples from ring buffers into the output read buffers.
    /// Called by provideFrames() in ring buffer mode.
    /// - Parameter frameCount: Number of frames to read.
    /// - Returns: The number of frames actually read (may be less if underrun).
    @inline(__always)
    private func readFromRingBuffers(frameCount: UInt32) -> Int {
        let count = Int(frameCount)
        var minRead = count

        for (index, ringBuffer) in ringBuffers.enumerated() {
            let read = ringBuffer.read(into: outputReadBuffers[index], count: count)
            minRead = min(minRead, read)
        }

        return minRead
    }

    /// Returns pointers to the processing buffers (immutable, for passing to render context).
    /// Points to either outputReadBuffers (ring buffer mode) or inputBuffers (direct capture).
    /// - Returns: Pre-computed array of immutable pointers to the active processing buffers.
    var outputBufferPointers: [UnsafePointer<Float>] {
        processingBufferPointers
    }

    /// Processes all EQ layers on processing buffers in-place.
    /// Called from audio thread after provideFrames() fills the processing buffers.
    /// - Parameter frameCount: Number of frames to process.
    @inline(__always)
    func processEQ(frameCount: UInt32) {
        // Process L channel through all layers in series
        for chain in leftEQChains {
            chain.applyPendingUpdates()
            chain.process(buffer: processingBuffers[0], frameCount: frameCount)
        }

        // Process R channel through all layers in series (if stereo)
        if channelCount > 1 {
            for chain in rightEQChains {
                chain.applyPendingUpdates()
                chain.process(buffer: processingBuffers[1], frameCount: frameCount)
            }
        }
    }

    /// Returns the latest per-channel meter snapshots in dBFS.
    func meterSnapshot() -> (input: [Float], output: [Float]) {
        let input = Array(UnsafeBufferPointer(start: inputMeterStorage, count: meterChannelCount))
        let output = Array(UnsafeBufferPointer(start: outputMeterStorage, count: meterChannelCount))
        return (input, output)
    }

    /// Returns the latest per-channel RMS meter snapshots in dBFS.
    func rmsSnapshot() -> (input: [Float], output: [Float]) {
        let input = Array(UnsafeBufferPointer(start: inputRmsStorage, count: meterChannelCount))
        let output = Array(UnsafeBufferPointer(start: outputRmsStorage, count: meterChannelCount))
        return (input, output)
    }

    func updateOutputMeters(from bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
        let channels = UnsafeMutableAudioBufferListPointer(bufferList)
        // Reuse pre-allocated array to avoid heap allocation on audio thread
        meterChannelPointers.removeAll(keepingCapacity: true)
        for buffer in channels {
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                meterChannelPointers.append(UnsafePointer(data))
            }
        }
        if meterChannelPointers.isEmpty {
            return
        }
        updateMeterStorage(storage: outputMeterStorage, rmsStorage: outputRmsStorage, with: meterChannelPointers, frameCount: Int(frameCount))
    }

    @inline(__always)
    func applyGain(
        to bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: UInt32,
        currentGain: inout Float,
        targetGain: Float
    ) {
        let channels = UnsafeMutableAudioBufferListPointer(bufferList)
        // Reuse pre-allocated array to avoid heap allocation on audio thread
        gainBuffers.removeAll(keepingCapacity: true)
        for buffer in channels {
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                gainBuffers.append(data)
            }
        }
        if gainBuffers.isEmpty {
            currentGain = targetGain
            return
        }
        applyGain(to: gainBuffers, frameCount: frameCount, currentGain: &currentGain, targetGain: targetGain)
    }

    private func updateMeterStorage(
        storage: UnsafeMutablePointer<Float>,
        rmsStorage: UnsafeMutablePointer<Float>,
        with channels: [UnsafePointer<Float>],
        frameCount: Int
    ) {
        // Skip all meter calculations when meters are disabled
        guard metersEnabledAtomic.load(ordering: .relaxed) != 0 else { return }

        // Assert that frameCount doesn't exceed pre-allocated buffer capacity.
        // CoreAudio guarantees frameCount <= maxFrameCount, but we validate for safety.
        // This catches any edge cases during development/testing.
        precondition(
            frameCount <= framesPerBuffer,
            "frameCount (\(frameCount)) exceeds framesPerBuffer (\(framesPerBuffer))"
        )

        guard frameCount > 0 else {
            for index in 0..<meterChannelCount {
                storage[index] = Self.silenceDB
                rmsStorage[index] = Self.silenceDB
            }
            return
        }

        for channel in 0..<meterChannelCount {
            guard !channels.isEmpty else {
                storage[channel] = Self.silenceDB
                rmsStorage[channel] = Self.silenceDB
                continue
            }

            let sourceIndex = min(channel, channels.count - 1)
            let buffer = channels[sourceIndex]
            var peak: Float = 0
            var sumSquares: Float = 0
            var frame = 0
            while frame < frameCount {
                let sample = abs(buffer[frame])
                peak = max(peak, sample)
                sumSquares += sample * sample
                frame += 1
            }
            let db = AudioMath.linearToDB(max(peak, 1e-7), silence: Self.silenceDB)
            let rms = sqrt(sumSquares / Float(frameCount))
            let rmsDb = AudioMath.linearToDB(max(rms, 1e-7), silence: Self.silenceDB)
            storage[channel] = db
            rmsStorage[channel] = rmsDb
        }
    }

    // MARK: - Utility


    /// Zeros out the given AudioBufferList.
    /// - Parameters:
    ///   - bufferList: The buffer list to zero.
    ///   - frameCount: Number of frames to zero.
    static func zeroFill(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in abl {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    /// Resets all ring buffers to empty state.
    /// - Warning: Only call when no audio is running.
    func resetRingBuffers() {
        for ringBuffer in ringBuffers {
            ringBuffer.reset()
        }
        inputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        outputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
    }

    /// Returns diagnostic information about ring buffer state.
    func getDiagnostics() -> (availableToRead: [Int], underruns: [UInt64], overflows: [UInt64]) {
        let available = ringBuffers.map { $0.availableToRead() }
        let underruns = ringBuffers.map { $0.getUnderrunCount() }
        let overflows = ringBuffers.map { $0.getOverflowCount() }
        return (available, underruns, overflows)
    }
}
