// IdleSleepManager.swift
// Manages system sleep transitions by monitoring audio activity

import Foundation
import OSLog

@MainActor
final class IdleSleepManager {

    // MARK: - Properties

    private weak var coordinator: AudioRoutingCoordinator?
    
    private var silenceStartDate: Date?
    private let silenceDurationForSleep: TimeInterval = 5.0
    
    private var isPausedForSleep = false
    private var sleepCheckTimer: Timer?
    private var pollTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "IdleSleepManager")

    // MARK: - Initialization

    init(coordinator: AudioRoutingCoordinator, meterStore: MeterStore) {
        self.coordinator = coordinator
        // meterStore no longer needed as we poll pipeline directly
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isPausedForSleep else { return }
        logger.info("Starting idle sleep monitoring")
        silenceStartDate = nil
        
        sleepCheckTimer?.invalidate()
        sleepCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSilence()
            }
        }
    }

    func stopMonitoring() {
        logger.info("Stopping idle sleep monitoring")
        sleepCheckTimer?.invalidate()
        sleepCheckTimer = nil
        silenceStartDate = nil
        
        pollTask?.cancel()
        pollTask = nil
        
        if isPausedForSleep {
            isPausedForSleep = false
        }
    }

    // MARK: - Silence Check

    private func checkSilence() {
        guard !isPausedForSleep else { return }
        guard let coordinator = coordinator, let pipeline = coordinator.pipelineManager.renderPipeline else { return }
        
        let meters = pipeline.currentMeters()
        
        // We consider it silent if all RMS values are below -80 dB
        let silenceThreshold: Float = -80.0
        
        let isSilent = meters.outputRmsDB.allSatisfy { $0 <= silenceThreshold } && 
                       meters.inputRmsDB.allSatisfy { $0 <= silenceThreshold }
        
        if isSilent {
            if let startDate = silenceStartDate {
                let duration = Date().timeIntervalSince(startDate)
                if duration >= silenceDurationForSleep {
                    triggerSleepPause()
                }
            } else {
                silenceStartDate = Date()
            }
        } else {
            silenceStartDate = nil
        }
    }

    // MARK: - Sleep / Wake Actions

    private func triggerSleepPause() {
        guard !isPausedForSleep else { return }
        guard let coordinator = coordinator else { return }
        
        // Only valid for shared memory mode. HAL input mode cannot be polled while paused.
        guard coordinator.effectiveCaptureMode == .sharedMemory else {
            logger.debug("Skipping sleep pause: not using shared memory capture")
            return
        }

        logger.info("Silence detected for \(self.silenceDurationForSleep)s, pausing pipeline to allow sleep")
        isPausedForSleep = true
        silenceStartDate = nil
        
        // Stop timer while paused
        sleepCheckTimer?.invalidate()
        sleepCheckTimer = nil
        
        // Tell coordinator to pause the CoreAudio graph
        coordinator.pipelineManager.pauseForSleep()
        
        // Start polling for activity
        startActivityPolling()
    }

    private func startActivityPolling() {
        pollTask?.cancel()
        pollTask = Task {
            logger.info("Started polling for driver activity")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                
                guard !Task.isCancelled else { break }
                
                if let coordinator = self.coordinator, coordinator.pipelineManager.isDriverActive() {
                    self.triggerWakeResume()
                    break
                }
            }
        }
    }

    private func triggerWakeResume() {
        guard isPausedForSleep else { return }
        logger.info("Driver activity detected, resuming pipeline")
        
        isPausedForSleep = false
        pollTask?.cancel()
        pollTask = nil
        
        // Resume CoreAudio graph
        coordinator?.pipelineManager.resumeFromSleep()
        
        // Restart monitoring
        startMonitoring()
    }
}
