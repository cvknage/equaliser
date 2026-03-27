// DriverCapture.swift
// Audio capture from driver via shared memory, called synchronously from output callback

import CoreAudio
import Foundation
import OSLog

// MARK: - DriverCapture

/// Manages audio capture from the Equaliser driver via shared memory.
/// Does NOT trigger TCC microphone permission.
///
/// For shared memory, the app creates a file in /tmp/ which the driver opens.
/// This avoids macOS permission issues with POSIX shm_open (driver runs as root).
///
/// This class is designed to be polled from the audio output callback,
/// ensuring perfect synchronization with the audio clock.
///
/// - Important: `init()` must be called from MainActor context
///   because it accesses `DriverDeviceRegistry` which is `@MainActor`.
///   The `poll()` method can be called from any thread (including the audio thread).
final class DriverCapture: @unchecked Sendable {

    // MARK: - Properties

    private let sampleRate: Float64
    private let bufferSize: UInt32

    /// Shared memory capture instance
    private nonisolated(unsafe) var sharedMemoryCapture: SharedMemoryCapture?

    /// Static logger for thread-safe access
    private static let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverCapture")

    /// Whether capture is initialized (device resolved, shared memory ready)
    private nonisolated(unsafe) var isInitialized = false

    // MARK: - Initialization

    /// Creates a new driver capture instance.
    /// - Parameters:
    ///   - registry: Driver registry for device discovery (MainActor-isolated)
    ///   - sampleRate: Audio sample rate
    ///   - bufferSize: Buffer size in frames
    @MainActor
    init(registry: DriverDeviceRegistry, sampleRate: Float64, bufferSize: UInt32) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
    }

    // MARK: - Lifecycle

    /// Initializes capture by resolving the device and setting up shared memory.
    /// Must be called before `poll()`.
    /// - Parameter deviceID: The audio device ID for the driver
    /// - Throws: Error if shared memory setup fails
    @MainActor
    func initialize(deviceID: AudioDeviceID) throws {
        guard !isInitialized else {
            Self.logger.warning("Driver capture already initialized")
            return
        }

        // Create and set up shared memory
        guard let capture = tryCreateAndSetSharedMemory(deviceID: deviceID) else {
            Self.logger.error("Failed to create shared memory for driver capture")
            throw SharedMemoryCaptureError.sharedMemoryNotAvailable
        }

        sharedMemoryCapture = capture
        isInitialized = true
        Self.logger.info("Driver capture initialized: \(self.sampleRate) Hz, buffer size \(self.bufferSize)")
    }

    /// Creates shared memory file and sets path on driver.
    /// - Parameter deviceID: The audio device ID
    /// - Returns: Connected SharedMemoryCapture, or nil if failed
    @MainActor
    private func tryCreateAndSetSharedMemory(deviceID: AudioDeviceID) -> SharedMemoryCapture? {
        let capture = SharedMemoryCapture(channelCount: 2)

        do {
            // Create the shared memory file
            let path = try capture.create()
            Self.logger.debug("Created shared memory file: \(path)")

            // Set the path on the driver
            if setSharedMemoryPath(deviceID: deviceID, path: path) {
                Self.logger.info("Set shared memory path on driver: \(path)")
                return capture
            } else {
                Self.logger.warning("Failed to set shared memory path on driver")
                capture.disconnect()
                return nil
            }
        } catch {
            Self.logger.warning("Failed to create shared memory: \(error)")
            return nil
        }
    }

    /// Sets the shared memory path on the driver.
    /// - Parameters:
    ///   - deviceID: The audio device ID
    ///   - path: Path to the shared memory file
    /// - Returns: true if successful, false otherwise
    @MainActor
    private func setSharedMemoryPath(deviceID: AudioDeviceID, path: String) -> Bool {
        var address = DRIVER_ADDRESS_SHARED_MEM_PATH
        var cfPath = path as CFString

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<CFString>.size),
            &cfPath
        )

        if status != noErr {
            Self.logger.error("Failed to set shared memory path: \(status)")
            return false
        }

        return true
    }

    // MARK: - Polling (Audio Thread Safe)

    /// Polls the driver and returns audio samples.
    /// Designed to be called from the audio output callback for perfect synchronization.
    /// - Returns: Audio buffer data with interleaved samples, or nil if not available
    /// - Note: This method is real-time safe and can be called from the audio thread.
    @inline(__always)
    func poll() -> AudioBufferData? {
        guard isInitialized, let capture = sharedMemoryCapture else { return nil }

        if let data = capture.readFrames(), data.frameCount > 0 {
            return data
        }
        return nil
    }

    /// Stops capturing (resets initialization state).
    func stop() {
        sharedMemoryCapture?.disconnect()
        sharedMemoryCapture = nil
        isInitialized = false
        Self.logger.info("Driver capture stopped")
    }
}