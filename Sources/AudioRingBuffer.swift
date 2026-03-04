import Foundation
import os.log

/// A lock-free, single-producer single-consumer ring buffer for real-time audio.
///
/// This buffer is designed for use between two audio callbacks:
/// - **Producer**: The input HAL callback writes captured audio samples
/// - **Consumer**: The output HAL callback reads samples for processing
///
/// Thread safety is achieved through careful ordering of reads/writes and
/// memory barriers provided by atomic operations. No locks are used to ensure
/// real-time safety.
///
/// - Note: This class is marked `@unchecked Sendable` because it uses manual
///   synchronization via atomics rather than Swift's built-in concurrency.
final class AudioRingBuffer: @unchecked Sendable {
    // MARK: - Properties

    /// The underlying sample buffer (Float samples).
    private let buffer: UnsafeMutablePointer<Float>

    /// Total capacity in samples.
    private let capacity: Int

    /// Mask for fast modulo operations (capacity must be power of 2).
    private let mask: Int

    /// Write position (only modified by producer).
    /// Using UnsafeMutablePointer for atomic access.
    private let writeIndex: UnsafeMutablePointer<Int>

    /// Read position (only modified by consumer).
    private let readIndex: UnsafeMutablePointer<Int>

    /// Logger for diagnostics (used sparingly to avoid audio thread overhead).
    private static let logger = Logger(
        subsystem: "com.example.EqualizerApp",
        category: "AudioRingBuffer"
    )

    /// Counter for underrun events (for periodic logging).
    private var underrunCount: UInt64 = 0

    /// Counter for overflow events (for periodic logging).
    private var overflowCount: UInt64 = 0

    // MARK: - Initialization

    /// Creates a new ring buffer with the specified capacity.
    ///
    /// - Parameter capacity: The capacity in samples. Will be rounded up to the
    ///   next power of 2 for efficient modulo operations.
    /// - Precondition: Capacity must be greater than 0.
    init(capacity requestedCapacity: Int) {
        precondition(requestedCapacity > 0, "Capacity must be greater than 0")

        // Round up to next power of 2 for efficient masking
        let power = max(1, Int(ceil(log2(Double(requestedCapacity)))))
        self.capacity = 1 << power
        self.mask = self.capacity - 1

        // Allocate the sample buffer (zero-initialized)
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        self.buffer.initialize(repeating: 0.0, count: self.capacity)

        // Allocate atomic indices
        self.writeIndex = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        self.writeIndex.initialize(to: 0)

        self.readIndex = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        self.readIndex.initialize(to: 0)

        Self.logger.info(
            "Ring buffer created: requested=\(requestedCapacity), actual=\(self.capacity)"
        )
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()

        writeIndex.deinitialize(count: 1)
        writeIndex.deallocate()

        readIndex.deinitialize(count: 1)
        readIndex.deallocate()
    }

    // MARK: - Producer API (Input Callback)

    /// Writes samples to the ring buffer.
    ///
    /// This method is designed to be called from the audio input callback (producer).
    /// It is lock-free and real-time safe.
    ///
    /// - Parameters:
    ///   - samples: Pointer to the samples to write.
    ///   - count: Number of samples to write.
    /// - Returns: The number of samples actually written (may be less than `count` if buffer is full).
    @inline(__always)
    func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
        // Load indices with memory barrier
        let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
        let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

        let write = Int(currentWrite)
        let read = Int(currentRead)

        // Calculate available space
        let available = capacity - (write - read)
        let toWrite = min(count, available)

        if toWrite < count {
            // Overflow - we're dropping samples
            overflowCount &+= 1
        }

        if toWrite == 0 {
            return 0
        }

        // Write samples (may wrap around)
        let writePos = write & mask
        let firstChunk = min(toWrite, capacity - writePos)
        let secondChunk = toWrite - firstChunk

        // Copy first chunk
        buffer.advanced(by: writePos).update(from: samples, count: firstChunk)

        // Copy second chunk (if wrapping)
        if secondChunk > 0 {
            buffer.update(from: samples.advanced(by: firstChunk), count: secondChunk)
        }

        // Update write index with memory barrier (release semantics)
        OSAtomicAdd64Barrier(Int64(toWrite), writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

        return toWrite
    }

    // MARK: - Consumer API (Output Callback)

    /// Reads samples from the ring buffer.
    ///
    /// This method is designed to be called from the audio output callback (consumer).
    /// It is lock-free and real-time safe.
    ///
    /// - Parameters:
    ///   - destination: Pointer to the buffer to read into.
    ///   - count: Number of samples to read.
    /// - Returns: The number of samples actually read (may be less than `count` if buffer is empty).
    @inline(__always)
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        // Load indices with memory barrier
        let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
        let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

        let write = Int(currentWrite)
        let read = Int(currentRead)

        // Calculate available samples
        let available = write - read
        let toRead = min(count, available)

        if toRead < count {
            // Underrun - not enough samples
            underrunCount &+= 1
        }

        if toRead == 0 {
            // Zero-fill the destination
            destination.initialize(repeating: 0.0, count: count)
            return 0
        }

        // Read samples (may wrap around)
        let readPos = read & mask
        let firstChunk = min(toRead, capacity - readPos)
        let secondChunk = toRead - firstChunk

        // Copy first chunk
        destination.update(from: buffer.advanced(by: readPos), count: firstChunk)

        // Copy second chunk (if wrapping)
        if secondChunk > 0 {
            destination.advanced(by: firstChunk).update(from: buffer, count: secondChunk)
        }

        // Zero-fill any remaining if we underran
        if toRead < count {
            destination.advanced(by: toRead).initialize(repeating: 0.0, count: count - toRead)
        }

        // Update read index with memory barrier (release semantics)
        OSAtomicAdd64Barrier(Int64(toRead), readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })

        return toRead
    }

    // MARK: - Status

    /// Returns the number of samples available to read.
    ///
    /// - Note: This is a snapshot and may change immediately after the call.
    @inline(__always)
    func availableToRead() -> Int {
        let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
        let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
        return Int(currentWrite - currentRead)
    }

    /// Returns the number of samples that can be written.
    ///
    /// - Note: This is a snapshot and may change immediately after the call.
    @inline(__always)
    func availableToWrite() -> Int {
        let currentWrite = OSAtomicAdd64Barrier(0, writeIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
        let currentRead = OSAtomicAdd64Barrier(0, readIndex.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
        return capacity - Int(currentWrite - currentRead)
    }

    /// Resets the buffer to empty state.
    ///
    /// - Warning: Only call this when no audio is running.
    func reset() {
        writeIndex.pointee = 0
        readIndex.pointee = 0
        buffer.initialize(repeating: 0.0, count: capacity)
        underrunCount = 0
        overflowCount = 0
    }

    /// Returns the total capacity of the buffer in samples.
    func getCapacity() -> Int {
        return capacity
    }

    /// Returns the underrun count (for diagnostics).
    func getUnderrunCount() -> UInt64 {
        return underrunCount
    }

    /// Returns the overflow count (for diagnostics).
    func getOverflowCount() -> UInt64 {
        return overflowCount
    }
}
