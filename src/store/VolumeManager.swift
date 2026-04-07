import Foundation
import CoreAudio
import OSLog

/// Manages volume synchronization between driver and output device.
/// Uses device-level kAudioDevicePropertyVolumeScalar for both devices.
///
/// Architecture:
/// - Output device (speakers/headphones) is source of truth for volume
/// - Driver volume syncs to output device (user's preferred volume stored by macOS)
/// - Both devices receive same scalar value (0-1 range)
/// - Boost = 1.0 / linear_gain (brings signal back to unity for EQ processing)
/// - Mute state synced from output to driver
///
/// Signal Flow:
/// ```
/// App Start/Device Change:
///   Output Device (50%) → Driver (50%) → [boost calculated]
///
/// User moves macOS slider:
///   Driver (30%) → Output Device (30%) → [boost recalculated]
///
/// Result: Driver (30% scalar) → audio at 0.57% (linear) → [Boost 175x] → EQ at 100% → Output (30%)
/// ```
@MainActor
final class VolumeManager: ObservableObject {
    
    // MARK: - Constants

    /// Volume change threshold below which changes are ignored.
    /// Prevents glitches from rapid tiny volume fluctuations.
    private let volumeEpsilon: Float = 0.001

    // MARK: - Constants

    private enum Constants {
        /// Duration to suppress volume forwarding after setup.
        /// macOS may restore driver volume to 100% during device switches.
        static let settlingWindowDuration: TimeInterval = 0.5
    }

    // MARK: - Published State

    /// Current volume from driver (0.0 - 1.0). Used to calculate boost.
    @Published private(set) var gain: Float = 1.0

    /// Whether volume boost is enabled. When false, boost is always 1.0.
    @Published private(set) var boostEnabled: Bool = true

    /// Whether audio is muted.
    @Published private(set) var muted: Bool = false

    // MARK: - Dependencies

    /// Volume service for CoreAudio calls.
    /// nonisolated(unsafe) since it's a let set once in init and never changes,
    /// and setDeviceVolumeScalar is nonisolated.
    nonisolated(unsafe) let volumeService: VolumeControlling
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "VolumeManager")

    /// Serial queue for volume forwarding (isolated from main thread).
    /// Prevents CoreAudio calls from interfering with UI work and audio callback timing.
    private let volumeForwardQueue = DispatchQueue(label: "net.knage.equaliser.volume-forward")

    /// Last forwarded volume per device for deduplication.
    /// Accessed only on volumeForwardQueue, marked nonisolated(unsafe) for Swift concurrency.
    nonisolated(unsafe) var lastForwardedVolumeByDevice: [AudioDeviceID: Float] = [:]

    /// Driver device ID for volume sync.
    private var driverDeviceID: AudioDeviceID?

    /// Output device ID for volume sync.
    private var outputDeviceID: AudioDeviceID?

    /// Flag to prevent feedback loops.
    private var isSyncingMute = false

    /// Whether we're in the settling window after setupVolumeSync.
    /// During settling, volume forwarding is suppressed to avoid macOS-initiated spikes.
    private var isSettling: Bool = false

    // MARK: - Callbacks

    /// Called when boost gain changes (for render pipeline to apply).
    var onBoostGainChanged: ((Float) -> Void)?
    
    // MARK: - Initialization
    
    init(volumeService: VolumeControlling) {
        self.volumeService = volumeService
    }
    
    // MARK: - Setup

    /// Sets up volume and mute sync between driver and output device.
    /// Must be called after driver and output device are ready.
    /// - Parameters:
    ///   - driverID: The driver device ID
    ///   - outputID: The output device ID
    func setupVolumeSync(driverID: AudioDeviceID, outputID: AudioDeviceID) {
        tearDown()

        driverDeviceID = driverID
        outputDeviceID = outputID

        logger.info("setupVolumeSync: driverID=\(driverID), outputID=\(outputID)")

        // Output device is source of truth for volume
        // (speakers/headphones have user's preferred volume stored by macOS)
        let initialVolume: Float
        if let volume = volumeService.getDeviceVolumeScalar(deviceID: outputID), volume > 0 {
            initialVolume = volume
            let linearGain = driverScalarToLinear(volume)
            logger.info("Initial volume from output device: scalar=\(volume), linear=\(linearGain)")
        } else {
            // Fallback to very low volume to avoid blasting user's ears
            initialVolume = 0.01
            logger.warning("Could not get output volume, defaulting to 1%")
        }

        gain = initialVolume

        // Initialize last forwarded volume for this device to prevent first forward being skipped
        lastForwardedVolumeByDevice[outputID] = initialVolume

        // Get initial mute state from output device (source of truth)
        let initialMuted = volumeService.getDeviceMute(deviceID: outputID) ?? false
        muted = initialMuted
        logger.info("Initial mute state: \(initialMuted)")
        
        // Sync driver volume to output device (output is source of truth)
        if volumeService.setDeviceVolumeScalar(deviceID: driverID, volume: initialVolume) {
            logger.debug("Synced driver volume to output: \(initialVolume)")
        } else {
            logger.warning("Failed to sync driver volume to \(initialVolume)")
        }

        // Note: We do NOT forward volume to output device here.
        // macOS stores per-device volumes and restores them when a device becomes default.
        // Forwarding would overwrite the device's correct stored volume.

        // Sync mute state to driver (output is source of truth)
        if volumeService.setDeviceMute(deviceID: driverID, muted: initialMuted) {
            logger.debug("Synced driver mute to \(initialMuted)")
        }
        
        // Listen for driver volume changes (master control)
        volumeService.observeDeviceVolumeChanges(deviceID: driverID) { [weak self] newVolume in
            Task { @MainActor in
                self?.handleDriverVolumeChanged(newVolume)
            }
        }
        logger.info("Registered volume listener on driver device \(driverID)")
        
        // Listen for mute changes on driver
        volumeService.observeMuteChanges(on: driverID) { [weak self] newMuted in
            Task { @MainActor in
                self?.handleDriverMuteChanged(newMuted)
            }
        }
        logger.info("Registered mute listener on driver device \(driverID)")
        
        // Listen for mute changes on output device (sync back to driver)
        volumeService.observeMuteChanges(on: outputID) { [weak self] newMuted in
            Task { @MainActor in
                self?.handleOutputMuteChanged(newMuted)
            }
        }
        logger.info("Registered mute listener on output device \(outputID)")
        
        // Calculate initial boost
        let boost = boostGain()
        logger.info("Initial boost: \(boost)x (gain=\(initialVolume), muted=\(initialMuted))")
        onBoostGainChanged?(boost)

        // Start settling window to suppress macOS async volume spikes
        // macOS may restore driver volume to 100% during device switches
        isSettling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.settlingWindowDuration) { [weak self] in
            self?.isSettling = false
        }

        logger.info("Volume sync setup complete")
    }
    
    /// Tears down volume sync listeners.
    func tearDown() {
        if let driverID = driverDeviceID {
            volumeService.stopObservingDeviceVolumeChanges(deviceID: driverID)
            volumeService.stopObservingMuteChanges(on: driverID)
        }
        if let outputID = outputDeviceID {
            volumeService.stopObservingMuteChanges(on: outputID)
        }

        driverDeviceID = nil
        outputDeviceID = nil
        lastForwardedVolumeByDevice = [:]
        isSettling = false
    }
    
    // MARK: - Volume Change Handlers

    /// Handles volume changes from the driver device (macOS slider).
    /// Updates internal state immediately, then dispatches to serial queue for CoreAudio call.
    private func handleDriverVolumeChanged(_ newVolume: Float) {
        // Update internal state immediately (UI needs this)
        gain = newVolume

        // Skip forwarding during settling window
        // macOS may set driver to 100% during device switches
        guard !isSettling else {
            logger.debug("Skipping volume forward during settling window: \(newVolume)")
            return
        }

        // Capture values before dispatching to background queue
        guard let outputID = outputDeviceID else { return }

        // Dispatch to serial queue for epsilon filtering and output sync
        // This isolates CoreAudio calls from main thread UI work
        volumeForwardQueue.async { [weak self, outputID] in
            // Forward volume to the captured output device
            // Note: We use the captured outputID to avoid race conditions with device switches
            self?.forwardVolumeToOutput(newVolume, outputID: outputID)
        }

        // Update boost (brings signal back to unity)
        let boost = boostGain()
        onBoostGainChanged?(boost)
    }

    /// Forwards volume to output device with epsilon filtering.
    /// Called on volumeForwardQueue, not main thread.
    nonisolated private func forwardVolumeToOutput(_ newVolume: Float, outputID: AudioDeviceID) {
        // Skip if change is below epsilon threshold for this device
        if let lastVolume = lastForwardedVolumeByDevice[outputID],
           abs(newVolume - lastVolume) < volumeEpsilon {
            return
        }

        lastForwardedVolumeByDevice[outputID] = newVolume

        // CoreAudio call on serial queue (isolated from main thread)
        // Note: setDeviceVolumeScalar is nonisolated and thread-safe
        _ = volumeService.setDeviceVolumeScalar(deviceID: outputID, volume: newVolume)
    }
    
    // MARK: - Mute Change Handlers
    
    /// Handles mute changes from the driver device.
    private func handleDriverMuteChanged(_ newMuted: Bool) {
        guard !isSyncingMute else {
            logger.debug("handleDriverMuteChanged: skipping - already syncing")
            return
        }
        
        logger.info("handleDriverMuteChanged: newMuted=\(newMuted)")
        
        isSyncingMute = true
        defer { isSyncingMute = false }
        
        // Update internal state
        muted = newMuted
        
        // Sync mute to output device
        if let outputID = outputDeviceID {
            volumeService.setDeviceMute(deviceID: outputID, muted: newMuted)
        }
        
        // Update boost (no boost when muted)
        let boost = boostGain()
        onBoostGainChanged?(boost)
    }
    
    /// Handles mute changes from the output device.
    /// Syncs back to driver since mute should be unified.
    private func handleOutputMuteChanged(_ newMuted: Bool) {
        guard !isSyncingMute else {
            logger.debug("handleOutputMuteChanged: skipping - already syncing")
            return
        }
        
        logger.info("handleOutputMuteChanged: newMuted=\(newMuted)")
        
        isSyncingMute = true
        defer { isSyncingMute = false }
        
        // Update internal state
        muted = newMuted
        
        // Sync mute to driver
        if let driverID = driverDeviceID {
            volumeService.setDeviceMute(deviceID: driverID, muted: newMuted)
        }
        
        // Update boost
        let boost = boostGain()
        onBoostGainChanged?(boost)
    }
    
    // MARK: - Programmatic Changes
    
    /// Sets the volume from UI (not currently used - volume is controlled by macOS).
    func setGain(_ newGain: Float) {
        guard abs(newGain - gain) > 0.001 else { return }
        
        logger.info("setGain: newGain=\(newGain)")
        
        gain = newGain
        
        // Sync both driver and output device
        if let driverID = driverDeviceID {
            volumeService.setDeviceVolumeScalar(deviceID: driverID, volume: newGain)
        }
        if let outputID = outputDeviceID {
            volumeService.setDeviceVolumeScalar(deviceID: outputID, volume: newGain)
        }
        
        // Update boost
        let boost = boostGain()
        onBoostGainChanged?(boost)
    }
    
    /// Sets mute state from UI.
    func setMuted(_ newMuted: Bool) {
        guard newMuted != muted else { return }
        
        isSyncingMute = true
        defer { isSyncingMute = false }
        
        logger.info("setMuted: newMuted=\(newMuted)")
        
        muted = newMuted
        
        // Sync both devices
        if let driverID = driverDeviceID {
            volumeService.setDeviceMute(deviceID: driverID, muted: newMuted)
        }
        if let outputID = outputDeviceID {
            volumeService.setDeviceMute(deviceID: outputID, muted: newMuted)
        }
        
        // Update boost
        let boost = boostGain()
        onBoostGainChanged?(boost)
    }
    
    /// Sets whether boost is enabled.
    func setBoostEnabled(_ enabled: Bool) {
        guard enabled != boostEnabled else { return }
        
        boostEnabled = enabled
        let boost = boostGain()
        onBoostGainChanged?(boost)
    }
    
    // MARK: - Volume Conversion
    
    /// Converts driver's scalar value (0-1) to actual linear gain.
    /// The driver uses dB-based conversion from BlackHole:
    ///   scalar → dB: scalar × 64 - 64 (range: -64 to 0 dB)
    ///   dB → linear: 10^(dB/20)
    /// This matches the driver's volume_to_decibel and volume_from_decibel functions.
    private func driverScalarToLinear(_ scalar: Float) -> Float {
        let minDB: Float = -64.0
        let maxDB: Float = 0.0
        
        // Clamp scalar to valid range
        let clampedScalar = max(0.0, min(1.0, scalar))
        
        // Convert scalar to dB (mirrors driver's volume_to_decibel + volume_from_decibel)
        // dB = scalar × (maxDB - minDB) + minDB
        let decibel = clampedScalar * (maxDB - minDB) + minDB
        
        // Convert dB to linear: linear = 10^(dB/20)
        if decibel <= minDB { return 0.0 }
        return pow(10.0, decibel / 20.0)
    }
    
    // MARK: - Boost Calculation
    
    /// Calculates the boost to bring signal back to unity.
    /// Uses driver's actual linear gain (after dB conversion) for accurate boost.
    /// - Returns: Boost factor (1.0 = unity, 175x for 30% volume).
    func boostGain() -> Float {
        guard boostEnabled else { return 1.0 }
        guard !muted else { return 1.0 }
        guard gain > 0 else { return 1.0 }
        
        // Convert from driver's scalar dB mapping to actual linear gain
        let linearGain = driverScalarToLinear(gain)
        guard linearGain > 0 else { return 1.0 }  // Only prevent division by zero
        
        return 1.0 / linearGain
    }
    
    /// Returns the current output volume (same as gain, 0.0 - 1.0).
    func outputVolume() -> Float {
        return gain
    }
}
