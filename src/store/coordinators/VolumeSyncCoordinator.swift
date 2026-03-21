// VolumeSyncCoordinator.swift
// Coordinates volume sync between driver and output device

import Foundation
import CoreAudio

/// Coordinates volume synchronization between driver and output device.
/// Thin wrapper around VolumeManager for simpler integration with AudioRoutingCoordinator.
@MainActor
final class VolumeSyncCoordinator {

    // MARK: - Properties

    private var volumeManager: VolumeManager?
    private let volumeService: VolumeControlling

    /// Callback invoked when boost gain changes.
    var onBoostGainChanged: ((Float) -> Void)? {
        didSet {
            volumeManager?.onBoostGainChanged = onBoostGainChanged
        }
    }

    // MARK: - Initialization

    init(volumeService: VolumeControlling) {
        self.volumeService = volumeService
    }

    // MARK: - Public Methods

    /// Sets up volume sync between driver and output device.
    /// Creates VolumeManager if needed and configures the sync.
    /// - Parameters:
    ///   - driverID: The driver's audio device ID
    ///   - outputID: The output device's audio device ID
    func setup(driverID: AudioDeviceID, outputID: AudioDeviceID) {
        if volumeManager == nil {
            volumeManager = VolumeManager(volumeService: volumeService)
            volumeManager?.onBoostGainChanged = onBoostGainChanged
        }
        volumeManager?.setupVolumeSync(driverID: driverID, outputID: outputID)
    }

    /// Tears down volume sync.
    func tearDown() {
        volumeManager?.tearDown()
    }
}