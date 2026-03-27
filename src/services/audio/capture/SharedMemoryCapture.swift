// SharedMemoryCapture.swift
// Lock-free audio capture from driver via file-based shared memory

import CoreAudio
import Darwin
import Foundation
import OSLog

// MARK: - Shared Memory Layout

/// Structure matching the driver's EqualiserSharedMemory
/// Must be kept in sync with EqualiserDriver.c
struct SharedMemoryLayout {
    /// Size of the ring buffer (must match SHARED_MEM_RING_SIZE in driver)
    static let ringSize: UInt32 = 65536

    /// Header offsets in shared memory
    struct Header {
        static let writeIndexOffset: Int = 0                              // _Atomic UInt32
        static let readIndexOffset: Int = 4                               // _Atomic UInt32
        static let frameCountOffset: Int = 8                              // _Atomic UInt32
        static let channelCountOffset: Int = 12                           // UInt32
        static let sampleRateOffset: Int = 16                             // Float64
        static let samplesOffset: Int = 64                                // After padding
    }

    /// Total size of the shared memory region
    static func totalSize(channelCount: UInt32) -> Int {
        return Header.samplesOffset + Int(ringSize) * Int(channelCount) * MemoryLayout<Float>.size
    }
}

// MARK: - Data Types

/// Audio buffer data returned from the driver.
/// Contains interleaved L/R samples.
struct AudioBufferData: Sendable {
    let sampleRate: Float64
    let frameCount: UInt32
    let channelCount: UInt32
    let samples: [Float]  // Interleaved: L0, R0, L1, R1, ...
}

// MARK: - Error Types

/// Errors for shared memory capture
enum SharedMemoryCaptureError: Error, LocalizedError, Sendable {
    case sharedMemoryNotAvailable
    case createFailed(Int32)
    case truncateFailed(Int32)
    case mmapFailed(Int32)
    case invalidDevice

    var errorDescription: String? {
        switch self {
        case .sharedMemoryNotAvailable:
            return "Shared memory not available"
        case .createFailed(let errno):
            return "Failed to create shared memory file: \(errno)"
        case .truncateFailed(let errno):
            return "Failed to set shared memory size: \(errno)"
        case .mmapFailed(let errno):
            return "Failed to map shared memory: \(errno)"
        case .invalidDevice:
            return "Invalid device"
        }
    }
}

// MARK: - Shared Memory Capture

/// Lock-free audio capture from driver via file-based shared memory.
/// The app creates the shared memory file and the driver opens it.
/// This avoids permission issues with POSIX shm_open on macOS.
///
/// - Important: This class is `@unchecked Sendable` because the shared memory
///   is accessed from the audio thread, but all mutations use atomic operations.
final class SharedMemoryCapture: @unchecked Sendable {

    // MARK: - Properties

    /// Static logger for thread-safe access
    private static let logger = Logger(subsystem: "net.knage.equaliser", category: "SharedMemoryCapture")

    /// File descriptor for shared memory (read-only)
    private nonisolated(unsafe) var shmFD: Int32 = -1

    /// Mapped shared memory address
    private nonisolated(unsafe) var shmAddr: UnsafeMutableRawPointer?

    /// Size of mapped region
    private nonisolated(unsafe) var shmSize: Int = 0

    /// Current read position in the ring buffer
    private nonisolated(unsafe) var readIndex: UInt32 = 0

    /// Number of channels (should match driver)
    private let channelCount: UInt32

    /// Path to the shared memory file
    private nonisolated(unsafe) var shmPath: String = ""

    /// Whether shared memory is connected
    private nonisolated(unsafe) var isConnected: Bool = false

    /// First poll after connection - skip accumulated data
    private nonisolated(unsafe) var firstPoll: Bool = true

    // MARK: - Initialization

    /// Creates a new shared memory capture instance.
    /// - Parameter channelCount: Number of audio channels (must match driver)
    init(channelCount: UInt32 = 2) {
        self.channelCount = channelCount
    }

    // MARK: - Lifecycle

    /// Creates and opens a file-based shared memory region.
    /// The caller must set this path on the driver before audio starts.
    /// - Returns: Path to the created shared memory file
    /// - Throws: SharedMemoryCaptureError if creation fails
    @discardableResult
    func create() throws -> String {
        // Create unique file in /tmp with PID
        let path = "/tmp/equaliser-audio-\(getpid()).shm"

        Self.logger.debug("Creating shared memory file: \(path)")

        // Remove existing file if present
        unlink(path)

        // Create new file with read/write permissions
        // Note: Swift uses 0o prefix for octal, not 0 prefix like C
        let fd = open(path, O_CREAT | O_RDWR, 0o666)
        guard fd >= 0 else {
            let err = errno
            Self.logger.error("Failed to create shared memory file: \(err)")
            throw SharedMemoryCaptureError.createFailed(err)
        }

        // Set world-writable permissions explicitly (bypass umask)
        // This allows the driver (running as coreaudiod) to write to the file
        fchmod(fd, 0o666)

        // Set file size
        let size = SharedMemoryLayout.totalSize(channelCount: channelCount)
        guard ftruncate(fd, off_t(size)) == 0 else {
            let err = errno
            close(fd)
            unlink(path)
            Self.logger.error("Failed to truncate shared memory file: \(err)")
            throw SharedMemoryCaptureError.truncateFailed(err)
        }

        // Map shared memory (read-write so driver can write)
        guard let addr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0), addr != MAP_FAILED else {
            let err = errno
            close(fd)
            unlink(path)
            Self.logger.error("Failed to map shared memory: \(err)")
            throw SharedMemoryCaptureError.mmapFailed(err)
        }

        // Initialize header
        // Note: Atomics are handled on the driver side. We just initialize to zero here.
        let headerPtr = addr.assumingMemoryBound(to: UInt32.self)
        headerPtr.pointee = 0  // writeIndex
        headerPtr.advanced(by: 1).pointee = 0  // readIndex
        headerPtr.advanced(by: 2).pointee = 0  // frameCount

        // Set channel count
        let channelPtr = addr.advanced(by: SharedMemoryLayout.Header.channelCountOffset)
            .assumingMemoryBound(to: UInt32.self)
        channelPtr.pointee = channelCount

        // Set sample rate (default, driver will update)
        let sampleRatePtr = addr.advanced(by: SharedMemoryLayout.Header.sampleRateOffset)
            .assumingMemoryBound(to: Float64.self)
        sampleRatePtr.pointee = 48000.0

        // Store values
        self.shmFD = fd
        self.shmAddr = addr
        self.shmSize = size
        self.shmPath = path
        self.isConnected = true
        self.firstPoll = true
        self.readIndex = 0

        Self.logger.info("Created shared memory file: \(path), size: \(size)")

        return path
    }

    /// Gets the path to the shared memory file (for setting on driver).
    /// - Returns: Path if created, empty string otherwise
    func getPath() -> String {
        return shmPath
    }

    /// Disconnects from shared memory and cleans up.
    func disconnect() {
        guard isConnected else { return }

        if let addr = shmAddr {
            munmap(addr, shmSize)
            shmAddr = nil
        }

        if shmFD >= 0 {
            close(shmFD)
            shmFD = -1
        }

        // Remove the file
        let pathToRemove = shmPath
        if !pathToRemove.isEmpty {
            unlink(pathToRemove)
            Self.logger.debug("Removed shared memory file: \(pathToRemove)")
        }

        shmPath = ""
        isConnected = false
        firstPoll = true
        readIndex = 0
    }

    // MARK: - Polling (Audio Thread Safe)

    /// Reads available frames from shared memory.
    /// Designed to be called from the audio output callback.
    /// - Returns: AudioBufferData with interleaved samples, or nil if not available
    /// - Note: Real-time safe - no allocations, no system calls, just memory reads
    @inline(__always)
    func readFrames() -> AudioBufferData? {
        guard isConnected, let shmAddr = shmAddr else { return nil }

        // Read atomic values from shared memory header
        // Using volatile reads which are sufficient for single-producer/single-consumer
        let writeIndex = shmAddr.loadAtomicUInt32(offset: SharedMemoryLayout.Header.writeIndexOffset)
        let frameCount = shmAddr.loadAtomicUInt32(offset: SharedMemoryLayout.Header.frameCountOffset)
        let channelCount = shmAddr.loadUInt32(offset: SharedMemoryLayout.Header.channelCountOffset)
        let sampleRate = shmAddr.loadFloat64(offset: SharedMemoryLayout.Header.sampleRateOffset)

        // On first poll, sync read position to write position
        // This prevents stale data from reaching the app
        if firstPoll {
            firstPoll = false
            readIndex = writeIndex
            // Return empty buffer on first poll
            return AudioBufferData(
                sampleRate: sampleRate,
                frameCount: 0,
                channelCount: channelCount,
                samples: []
            )
        }

        // Check if we have frames
        guard frameCount > 0 else { return nil }

        // Calculate available frames in ring buffer
        let availableFrames: UInt32
        if writeIndex >= readIndex {
            availableFrames = writeIndex &- readIndex
        } else {
            availableFrames = SharedMemoryLayout.ringSize &- readIndex &+ writeIndex
        }

        // Limit to what we can read
        let framesToRead = min(availableFrames, frameCount)
        guard framesToRead > 0 else { return nil }

        // Get pointer to samples array
        let samplesPtr = shmAddr.advanced(by: SharedMemoryLayout.Header.samplesOffset)
            .assumingMemoryBound(to: Float.self)

        // Copy samples from ring buffer (deinterleaving is done by caller)
        // We read directly from the ring buffer at readIndex position
        let sampleCount = Int(framesToRead * channelCount)
        var samples = [Float](repeating: 0, count: sampleCount)

        // Handle ring buffer wrap-around
        if readIndex &+ framesToRead <= SharedMemoryLayout.ringSize {
            // No wrap - single memcpy
            let srcPtr = samplesPtr.advanced(by: Int(readIndex * channelCount))
            samples.withUnsafeMutableBufferPointer { dest in
                _ = dest.initialize(from: UnsafeBufferPointer(start: srcPtr, count: sampleCount))
            }
        } else {
            // Wrap - two copies
            let firstPart = SharedMemoryLayout.ringSize &- readIndex
            let secondPart = framesToRead &- firstPart

            // First part
            let srcPtr1 = samplesPtr.advanced(by: Int(readIndex * channelCount))
            samples.withUnsafeMutableBufferPointer { dest in
                dest.baseAddress?.initialize(from: srcPtr1, count: Int(firstPart * channelCount))
            }

            // Second part (from start of ring buffer)
            let destOffset = Int(firstPart * channelCount)
            samples.withUnsafeMutableBufferPointer { dest in
                dest.baseAddress?.advanced(by: destOffset)
                    .initialize(from: samplesPtr, count: Int(secondPart * channelCount))
            }
        }

        // Update read position
        readIndex = (readIndex &+ framesToRead) % SharedMemoryLayout.ringSize

        return AudioBufferData(
            sampleRate: sampleRate,
            frameCount: framesToRead,
            channelCount: channelCount,
            samples: samples
        )
    }
}

// MARK: - Unsafe Raw Pointer Extensions

private extension UnsafeMutableRawPointer {
    /// Load atomic UInt32 from offset
    func loadAtomicUInt32(offset: Int) -> UInt32 {
        let ptr = self.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        return ptr.pointee
    }

    /// Load UInt32 from offset
    func loadUInt32(offset: Int) -> UInt32 {
        let ptr = self.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        return ptr.pointee
    }

    /// Load Float64 from offset
    func loadFloat64(offset: Int) -> Float64 {
        let ptr = self.advanced(by: offset).assumingMemoryBound(to: Float64.self)
        return ptr.pointee
    }
}