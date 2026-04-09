// PipelineManager.swift
// Manages the audio render pipeline lifecycle

import CoreAudio
import Foundation
import OSLog

/// Result of starting the audio pipeline.
enum PipelineStartResult {
    /// Pipeline started successfully.
    case success(sampleRate: Double)
    /// Pipeline configuration failed.
    case configurationFailed(String)
    /// Pipeline start failed.
    case startFailed(String)
}

/// Manages the RenderPipeline lifecycle: creation, configuration, starting, stopping,
/// and teardown. Also manages VolumeManager and EQ coefficient staging integration.
@MainActor
final class PipelineManager {

    // MARK: - Dependencies

    private let eqConfiguration: EQConfiguration
    private let meterStore: MeterStore
    private let volumeService: VolumeControlling
    private let eqStager: EQCoefficientStager

    // MARK: - State

    private(set) var renderPipeline: RenderPipeline?
    private var volumeManager: VolumeManager?

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "PipelineManager")

    // MARK: - Initialization

    init(eqConfiguration: EQConfiguration, meterStore: MeterStore, volumeService: VolumeControlling, eqStager: EQCoefficientStager) {
        self.eqConfiguration = eqConfiguration
        self.meterStore = meterStore
        self.volumeService = volumeService
        self.eqStager = eqStager
    }

    // MARK: - Pipeline Lifecycle

    /// Creates, configures, and starts the render pipeline.
    /// Returns the result indicating success or failure with details.
    func startPipeline(
        inputDeviceID: AudioDeviceID,
        outputDeviceID: AudioDeviceID,
        captureMode: CaptureMode,
        driverRegistry: DriverDeviceRegistry?,
        isAutomaticMode: Bool,
        driverID: AudioDeviceID?,
        driverOutputDeviceID: AudioDeviceID
    ) -> PipelineStartResult {
        let pipeline = RenderPipeline(eqConfiguration: eqConfiguration)

        switch pipeline.configure(
            inputDeviceID: inputDeviceID,
            outputDeviceID: outputDeviceID,
            captureMode: captureMode,
            driverRegistry: driverRegistry
        ) {
        case .success:
            break
        case .failure(let error):
            return .configurationFailed(error.localizedDescription)
        }

        switch pipeline.start() {
        case .success:
            renderPipeline = pipeline
            meterStore.setRenderPipeline(pipeline)
            meterStore.startMeterUpdates()

            // Store sample rate and pipeline reference for coefficient calculations
            eqStager.setCurrentSampleRate(pipeline.sampleRate)
            eqStager.setRenderPipeline(pipeline)

            // Stage initial EQ coefficients
            eqStager.reapplyConfiguration()

            // Set up volume sync (automatic mode only)
            if isAutomaticMode, let driverID = driverID {
                volumeManager = VolumeManager(volumeService: volumeService)
                if captureMode == .halInput {
                    volumeManager?.onBoostGainChanged = { [weak self] boostGain in
                        self?.renderPipeline?.updateBoostGain(linear: boostGain)
                    }
                }
                volumeManager?.setupVolumeSync(driverID: driverID, outputID: driverOutputDeviceID)

                // Schedule drift checks to catch macOS async volume restorations
                volumeManager?.scheduleDriftChecks()
            }

            return .success(sampleRate: pipeline.sampleRate)

        case .failure(let error):
            return .startFailed(error.localizedDescription)
        }
    }

    /// Stops the pipeline and tears down associated resources.
    func stopPipeline() {
        if let pipeline = renderPipeline {
            meterStore.stopMeterUpdates()
            meterStore.setRenderPipeline(nil)
            _ = pipeline.stop()
            renderPipeline = nil
        }

        // Clear stager's pipeline reference
        eqStager.setRenderPipeline(nil)

        // Clear callbacks and tear down volume sync
        volumeManager?.onBoostGainChanged = nil
        volumeManager?.tearDown()
        volumeManager = nil
    }

    // MARK: - Pipeline Pass-throughs

    /// Updates the processing mode on the render pipeline.
    func updateProcessingMode(systemEQOff: Bool, compareMode: CompareMode) {
        renderPipeline?.updateProcessingMode(systemEQOff: systemEQOff, compareMode: compareMode)
    }

    /// Updates the input gain on the render pipeline.
    func updateInputGain(linear: Float) {
        renderPipeline?.updateInputGain(linear: linear)
    }

    /// Updates the output gain on the render pipeline.
    func updateOutputGain(linear: Float) {
        renderPipeline?.updateOutputGain(linear: linear)
    }

    /// Updates the boost gain on the render pipeline.
    func updateBoostGain(linear: Float) {
        renderPipeline?.updateBoostGain(linear: linear)
    }
}