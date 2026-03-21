// DeviceChangeHandler.swift
// Handles device connect/disconnect events with debouncing and state-based detection

import Combine
import CoreAudio
import Foundation
import OSLog

/// Handles device enumeration changes (connect/disconnect).
/// Uses debouncing to coalesce event storms and diff-based detection for built-in devices.
/// Detects headphone plug events for built-in audio devices.
@MainActor
final class DeviceChangeHandler {
    
    // MARK: - Constants
    
    /// Debounce interval in milliseconds
    private static let debounceIntervalMs: UInt64 = 100
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceChangeHandler")
    private let deviceManager: DeviceManager
    
    /// Previous built-in output device UIDs.
    /// Used to detect when built-in devices appear/disappear (Apple Silicon headphone detection).
    private var previousBuiltInDeviceUIDs: Set<String> = []
    
    /// Flag to indicate if tracking has been initialized.
    /// First device enumeration establishes baseline state; subsequent callbacks detect changes.
    private var hasInitializedTracking = false
    
    /// The last selected output UID that was reported as missing.
    /// Used to avoid repeatedly calling the missing callback for the same UID.
    private var lastReportedMissingSelectedUID: String?
    
    /// Pending debounce task
    private var debounceTask: Task<Void, Never>?
    
    /// Latest device snapshot (updated on each Combine callback)
    private var pendingDeviceSnapshot: [AudioDevice] = []
    
    // MARK: - Callbacks
    
    /// Called when a single built-in device is added (Apple Silicon: headphones plugged in).
    /// Only fires when exactly one built-in device is added.
    var onBuiltInDeviceAdded: ((AudioDevice) -> Void)?
    
    /// Called when the currently selected output device is missing from available devices.
    /// Parameter is the missing device UID.
    var onSelectedOutputMissing: ((String) -> Void)?
    
    /// Called when built-in devices are removed (headphones unplugged).
    var onBuiltInDevicesRemoved: (() -> Void)?
    
    /// Closure to get the current selected output UID.
    var currentSelectedOutputUID: (() -> String?)?
    
    /// Closure to check if manual mode is enabled.
    var isManualMode: (() -> Bool)?
    
    /// Closure to check if routing is in progress.
    var isReconfiguring: (() -> Bool)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        
        // Observe output device list changes
        deviceManager.$outputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.scheduleDeviceUpdate(devices)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Debounced Processing
    
    /// Schedules a debounced device update.
    /// - Parameter devices: The latest device snapshot
    private func scheduleDeviceUpdate(_ devices: [AudioDevice]) {
        // Store latest snapshot
        pendingDeviceSnapshot = devices
        
        // Cancel any existing pending task
        debounceTask?.cancel()
        
        // Schedule new processing
        debounceTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Small delay to coalesce rapid updates
            try? await Task.sleep(nanoseconds: Self.debounceIntervalMs * 1_000_000)
            
            // Check if still valid (not cancelled)
            guard !Task.isCancelled else { return }
            
            await self.processDeviceUpdate()
        }
    }
    
    /// Processes the pending device update.
    private func processDeviceUpdate() async {
        let devices = pendingDeviceSnapshot
        
        // In manual mode, let user handle device selection
        guard isManualMode?() == false else { return }
        
        // Don't react during reconfiguration - reschedule
        guard isReconfiguring?() == false else {
            // Reschedule to process after reconfiguration completes
            scheduleDeviceUpdate(devices)
            return
        }
        
        // Get built-in devices
        let builtInDevices = devices.filter { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        let currentBuiltInUIDs = Set(builtInDevices.map { $0.uid })
        
        // FIRST CALLBACK: Initialize tracking state from actual device list
        if !hasInitializedTracking {
            previousBuiltInDeviceUIDs = currentBuiltInUIDs
            hasInitializedTracking = true
            logger.debug("Initialized tracking with \(builtInDevices.count) built-in device(s)")
            
            // Still check for missing selected device on first run
            checkForMissingSelectedDevice(devices: devices)
            return
        }
        
        // Compute diffs (Apple Silicon: headphone detection)
        let addedBuiltInUIDs = currentBuiltInUIDs.subtracting(previousBuiltInDeviceUIDs)
        let removedBuiltInUIDs = previousBuiltInDeviceUIDs.subtracting(currentBuiltInUIDs)
        
        // Log diff summary
        if !addedBuiltInUIDs.isEmpty || !removedBuiltInUIDs.isEmpty {
            logger.debug("Built-in device diff: +\(addedBuiltInUIDs.count), -\(removedBuiltInUIDs.count)")
        }
        
        // Handle added built-in devices (exactly one)
        if addedBuiltInUIDs.count == 1,
           let addedUID = addedBuiltInUIDs.first,
           let addedDevice = builtInDevices.first(where: { $0.uid == addedUID }) {
            logger.info("Built-in device added: '\(addedDevice.name)'")
            onBuiltInDeviceAdded?(addedDevice)
        } else if addedBuiltInUIDs.count > 1 {
            logger.debug("Multiple built-in devices added (\(addedBuiltInUIDs.count)), ignoring")
        }
        
        // Handle removed built-in devices
        if !removedBuiltInUIDs.isEmpty {
            logger.info("Built-in device(s) removed: \(removedBuiltInUIDs.count)")
            onBuiltInDevicesRemoved?()
        }
        
        // Update tracking
        previousBuiltInDeviceUIDs = currentBuiltInUIDs
        
        // Check for missing selected output device
        checkForMissingSelectedDevice(devices: devices)
    }
    
    /// Checks if the currently selected output device is missing.
    /// - Parameter devices: Available output devices
    private func checkForMissingSelectedDevice(devices: [AudioDevice]) {
        guard let selectedUID = currentSelectedOutputUID?() else { return }
        
        let deviceExists = devices.contains { $0.uid == selectedUID }
        
        if !deviceExists {
            // Only report if not already reported
            if lastReportedMissingSelectedUID != selectedUID {
                lastReportedMissingSelectedUID = selectedUID
                logger.info("Selected output device missing: \(selectedUID)")
                onSelectedOutputMissing?(selectedUID)
            }
        } else {
            // Clear tracking if device is back
            if lastReportedMissingSelectedUID == selectedUID {
                lastReportedMissingSelectedUID = nil
            }
        }
    }
    
    // MARK: - Manual History Management (deprecated - use OutputDeviceHistory)
    
    /// Clears the missing device tracking (call when device is restored)
    func clearMissingTracking() {
        lastReportedMissingSelectedUID = nil
    }
}