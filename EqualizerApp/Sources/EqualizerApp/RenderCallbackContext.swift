import AudioToolbox
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
/// - Important: This class is `@unchecked Sendable` because it is accessed from
///   both the main thread (for setup) and the audio render thread (for processing).
///   All mutable state is designed for single-writer/single-reader access patterns.
final class RenderCallbackContext: @unchecked Sendable {
    // MARK: - Properties

    private static let maxMeterChannels = 2
    private static let silenceDB: Float = -90

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

    /// Number of channels exposed to the level meters (up to two for stereo visualization).
    private let meterChannelCount: Int

    /// Storage for latest input peak levels per channel (in dBFS).
    private let inputMeterStorage: UnsafeMutablePointer<Float>

    /// Storage for latest output peak levels per channel (in dBFS).
    private let outputMeterStorage: UnsafeMutablePointer<Float>

    // MARK: - Initialization

    /// Creates a new callback context with ring buffers and pre-allocated audio buffers.
    /// - Parameters:
    ///   - inputHALUnit: The INPUT HAL audio unit instance for capturing audio.
    ///   - renderContext: The render context for EQ processing.
    ///   - channelCount: Number of audio channels.
    ///   - maxFrameCount: Maximum frames per callback (used for buffer sizing).
    ///   - ringBufferCapacity: Capacity of each ring buffer in samples (default 8192).
    init(
        inputHALUnit: AudioComponentInstance?,
        renderContext: AudioRenderContext?,
        channelCount: UInt32,
        maxFrameCount: UInt32,
        ringBufferCapacity: Int = 8192
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
        inputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)
        outputMeterStorage.initialize(repeating: Self.silenceDB, count: meterChannelCount)

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
        updateMeterStorage(storage: inputMeterStorage, with: channels, frameCount: count)
    }

    /// Direct access to the input sample buffers (for diagnostics/debugging).
    var inputSampleBuffers: [UnsafeMutablePointer<Float>] {
        inputBuffers
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

    /// Returns mutable pointers to the output read buffers.
    var outputMutableBufferPointers: [UnsafeMutablePointer<Float>] {
        outputReadBuffers
    }

    /// Returns the latest per-channel meter snapshots in dBFS.
    func meterSnapshot() -> (input: [Float], output: [Float]) {
        let input = Array(UnsafeBufferPointer(start: inputMeterStorage, count: meterChannelCount))
        let output = Array(UnsafeBufferPointer(start: outputMeterStorage, count: meterChannelCount))
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
        updateMeterStorage(storage: outputMeterStorage, with: channelPointers, frameCount: Int(frameCount))
    }

    private func updateMeterStorage(
        storage: UnsafeMutablePointer<Float>,
        with channels: [UnsafePointer<Float>],
        frameCount: Int
    ) {
        guard frameCount > 0 else {
            for index in 0..<meterChannelCount {
                storage[index] = Self.silenceDB
            }
            return
        }

        for channel in 0..<meterChannelCount {
            guard !channels.isEmpty else {
                storage[channel] = Self.silenceDB
                continue
            }

            let sourceIndex = min(channel, channels.count - 1)
            let buffer = channels[sourceIndex]
            var peak: Float = 0
            var frame = 0
            while frame < frameCount {
                peak = max(peak, abs(buffer[frame]))
                frame += 1
            }
            let db = max(Self.silenceDB, 20 * log10(max(peak, 1e-7)))
            storage[channel] = db
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
