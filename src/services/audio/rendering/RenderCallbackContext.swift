import AudioToolbox
import Atomics
import CoreAudio
import os.log

/// Context passed to both the input and output HAL render callbacks.
/// Contains ring buffers for inter-callback communication and all state
/// needed for real-time audio processing without requiring any allocations or locks.
///
/// Data flow:
/// 1. Input callback captures audio from device → writes to ring buffers
/// 2. Output callback reads from ring buffers → processes through EQ → outputs
///
/// For shared memory capture mode:
/// 1. Output callback polls driver shared memory → writes to ring buffers
/// 2. Output callback reads from ring buffers → processes through EQ → outputs
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

    /// The render context for processing audio through the EQ chain.
    let renderContext: AudioRenderContext?

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

    // MARK: - Driver Capture

    /// Sets the driver capture instance for polling.
    /// When set, the output callback will poll the driver before reading from ring buffers.
    func setDriverCapture(_ capture: DriverCapture?) {
        driverCapture = capture
    }

    // MARK: - Initialization

    /// Creates a new callback context with ring buffers and pre-allocated audio buffers.
    /// - Parameters:
    ///   - inputHALUnit: The INPUT HAL audio unit instance for capturing audio.
    ///   - renderContext: The render context for EQ processing.
    ///   - channelCount: Number of audio channels.
    ///   - maxFrameCount: Maximum frames per callback (used for buffer sizing).
    ///   - ringBufferCapacity: Capacity of each ring buffer in samples (default from AudioConstants).
    init(
        inputHALUnit: AudioComponentInstance?,
        renderContext: AudioRenderContext?,
        channelCount: UInt32,
        maxFrameCount: UInt32,
        ringBufferCapacity: Int = AudioConstants.ringBufferCapacity
    ) {
        self.inputHALUnit = inputHALUnit
        self.renderContext = renderContext
        self.channelCount = channelCount
        self.maxFrameCount = maxFrameCount
        self.framesPerBuffer = Int(maxFrameCount)
        self.meterChannelCount = min(Int(channelCount), Self.maxMeterChannels)

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

        self.inputMeterStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        self.outputMeterStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        self.inputRmsStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        self.outputRmsStorage = UnsafeMutablePointer<Float>.allocate(capacity: meterChannelCount)
        inputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        outputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        inputRmsStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        outputRmsStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)

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
        let channels = inputBuffers.map { UnsafePointer($0) }
        updateMeterStorage(storage: inputMeterStorage, rmsStorage: inputRmsStorage, with: channels, frameCount: count)
    }

    /// Writes interleaved audio samples to the ring buffers.
    /// Called by driver capture (not input HAL callback).
    /// - Parameters:
    ///   - interleavedSamples: Interleaved samples (L0, R0, L1, R1, ...)
    ///   - frameCount: Number of frames
    ///   - channelCount: Number of channels (must match context's channelCount)
    @inline(__always)
    func writeInterleavedToRingBuffers(
        interleavedSamples: [Float],
        frameCount: UInt32,
        channelCount: UInt32
    ) {
        guard channelCount == self.channelCount else { return }
        let count = Int(frameCount)
        guard count > 0 else { return }

        // Deinterleave into inputBuffers
        for frame in 0..<count {
            for channel in 0..<Int(channelCount) {
                let interleavedIndex = frame * Int(channelCount) + channel
                inputBuffers[channel][frame] = interleavedSamples[interleavedIndex]
            }
        }

        // Write to ring buffers (same as writeToRingBuffers)
        for (index, ringBuffer) in ringBuffers.enumerated() {
            _ = ringBuffer.write(inputBuffers[index], count: count)
        }

        // Update meters
        let channels = inputBuffers.map { UnsafePointer($0) }
        updateMeterStorage(storage: inputMeterStorage, rmsStorage: inputRmsStorage, with: channels, frameCount: count)
    }

    /// Polls driver capture and writes to ring buffers.
    /// Called by the output callback in shared memory mode.
    /// - Returns: Number of frames polled, or 0 if no data available
    @inline(__always)
    func pollAndWriteToRingBuffers() -> UInt32 {
        guard let capture = driverCapture,
              let data = capture.poll() else {
            return 0
        }

        let frameCount = data.frameCount
        let channelCount = data.channelCount

        guard frameCount > 0, channelCount == self.channelCount else {
            return 0
        }

        let count = Int(frameCount)

        // Deinterleave samples into inputBuffers
        for frame in 0..<count {
            for channel in 0..<Int(channelCount) {
                let interleavedIndex = frame * Int(channelCount) + channel
                inputBuffers[channel][frame] = data.samples[interleavedIndex]
            }
        }

        // Apply input gain before writing to ring buffers (skip in full bypass mode)
        // Note: Boost gain is NOT applied here - in shared memory mode, samples come
        // from the driver at full volume regardless of macOS volume setting
        if processingMode != 0 {
            let targetInputGain = getTargetInputGain()
            applyGain(
                to: inputBuffers.map { UnsafeMutablePointer($0) },
                frameCount: frameCount,
                currentGain: &inputGainLinear,
                targetGain: targetInputGain
            )
        }

        // Write to ring buffers
        for (index, ringBuffer) in ringBuffers.enumerated() {
            _ = ringBuffer.write(inputBuffers[index], count: count)
        }

        // Update meters
        let channels = inputBuffers.map { UnsafePointer($0) }
        updateMeterStorage(storage: inputMeterStorage, rmsStorage: inputRmsStorage, with: channels, frameCount: count)

        return frameCount
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

    /// Reads audio samples from ring buffers into the output read buffers.
    /// Called by the output callback to get samples for processing.
    /// - Parameter frameCount: Number of frames to read.
    /// - Returns: The number of frames actually read (may be less if underrun).
    @inline(__always)
    func readFromRingBuffers(frameCount: UInt32) -> Int {
        let count = Int(frameCount)
        var minRead = count

        for (index, ringBuffer) in ringBuffers.enumerated() {
            let read = ringBuffer.read(into: outputReadBuffers[index], count: count)
            minRead = min(minRead, read)
        }

        return minRead
    }

    /// Returns pointers to the output read buffers (immutable, for passing to render context).
    /// - Returns: Array of immutable pointers to the read buffers.
    var outputBufferPointers: [UnsafePointer<Float>] {
        outputReadBuffers.map { UnsafePointer($0) }
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
        var channelPointers: [UnsafePointer<Float>] = []
        for buffer in channels {
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                channelPointers.append(UnsafePointer(data))
            }
        }
        if channelPointers.isEmpty {
            return
        }
        updateMeterStorage(storage: outputMeterStorage, rmsStorage: outputRmsStorage, with: channelPointers, frameCount: Int(frameCount))
    }

    @inline(__always)
    func applyGain(
        to bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: UInt32,
        currentGain: inout Float,
        targetGain: Float
    ) {
        let channels = UnsafeMutableAudioBufferListPointer(bufferList)
        var buffers: [UnsafeMutablePointer<Float>] = []
        buffers.reserveCapacity(channels.count)
        for buffer in channels {
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                buffers.append(data)
            }
        }
        if buffers.isEmpty {
            currentGain = targetGain
            return
        }
        applyGain(to: buffers, frameCount: frameCount, currentGain: &currentGain, targetGain: targetGain)
    }

    private func updateMeterStorage(
        storage: UnsafeMutablePointer<Float>,
        rmsStorage: UnsafeMutablePointer<Float>,
        with channels: [UnsafePointer<Float>],
        frameCount: Int
    ) {
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

    /// Pre-fills ring buffers with silence to prevent startup underruns.
    /// Should be called before starting audio output in shared memory mode.
    /// - Parameter frameCount: Number of silent frames to write to each ring buffer.
    func prefillWithSilence(frameCount: UInt32) {
        let count = Int(frameCount)
        // Zero out input buffers
        for buffer in inputBuffers {
            buffer.initialize(repeating: 0.0, count: count)
        }
        // Write silence to all ring buffers
        for (index, ringBuffer) in ringBuffers.enumerated() {
            _ = ringBuffer.write(inputBuffers[index], count: count)
        }
    }

    /// Returns diagnostic information about ring buffer state.
    func getDiagnostics() -> (availableToRead: [Int], underruns: [UInt64], overflows: [UInt64]) {
        let available = ringBuffers.map { $0.availableToRead() }
        let underruns = ringBuffers.map { $0.getUnderrunCount() }
        let overflows = ringBuffers.map { $0.getOverflowCount() }
        return (available, underruns, overflows)
    }
}
