// AudioRoutingCoordinator.swift
// Coordinates audio routing: device selection and pipeline management

import AVFoundation
import Combine
import CoreAudio
import Foundation
import OSLog

/// Represents the result of automatic output device selection.
enum OutputDeviceSelection: Equatable {
    /// Use the existing selected device (it's still valid)
    case preserveCurrent(String)
    /// Use the current macOS default output device
    case useMacDefault(String)
    /// Need to find a fallback device (no valid selection available)
    case useFallback
}

/// Coordinates audio routing between input and output devices.
/// Manages the RenderPipeline and handles device selection, sample rate sync,
/// and mode switching (automatic vs manual).
@MainActor
final class AudioRoutingCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var routingStatus: RoutingStatus = .idle
    @Published var selectedInputDeviceID: String?
    @Published var selectedOutputDeviceID: String?
    @Published var manualModeEnabled: Bool = false
    @Published var showDriverPrompt: Bool = false
    
    // MARK: - Dependencies
    
    let deviceManager: DeviceManager
    private let eqConfiguration: EQConfiguration
    private let meterStore: MeterStore
    private let volumeSyncCoordinator: VolumeSyncCoordinator
    private let systemDefaultObserver: SystemDefaultObserver
    private let deviceChangeHandler: DeviceChangeHandler
    
    // MARK: - Private Properties
    
    private var renderPipeline: RenderPipeline?
    private var observedOutputDeviceID: AudioDeviceID?
    private var isReconfiguring = false
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AudioRoutingCoordinator")
    
    // MARK: - Initialization
    
    init(
        deviceManager: DeviceManager,
        eqConfiguration: EQConfiguration,
        meterStore: MeterStore,
        volumeSyncCoordinator: VolumeSyncCoordinator,
        systemDefaultObserver: SystemDefaultObserver,
        deviceChangeHandler: DeviceChangeHandler
    ) {
        self.deviceManager = deviceManager
        self.eqConfiguration = eqConfiguration
        self.meterStore = meterStore
        self.volumeSyncCoordinator = volumeSyncCoordinator
        self.systemDefaultObserver = systemDefaultObserver
        self.deviceChangeHandler = deviceChangeHandler
        
        // Wire up callbacks
        systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
            self?.handleSystemDefaultChanged(device)
        }
        
        deviceChangeHandler.onDeviceDisconnected = { [weak self] _ in
            self?.handleDeviceDisconnected()
        }
        deviceChangeHandler.isReconfiguring = { [weak self] in
            self?.isReconfiguring ?? false
        }
        deviceChangeHandler.isManualMode = { [weak self] in
            self?.manualModeEnabled ?? false
        }
    }
    
    // MARK: - Public Methods
    
    /// Reconfigures the audio routing pipeline.
    /// In automatic mode: derives devices from macOS default output.
    /// In manual mode: uses user-selected devices.
    func reconfigureRouting() {
        logger.debug("reconfigureRouting called, manualMode=\(self.manualModeEnabled), isReconfiguring=\(self.isReconfiguring)")
        
        // Prevent re-entrant calls
        guard !isReconfiguring else {
            logger.debug("reconfigureRouting: already reconfiguring, returning")
            return
        }
        
        isReconfiguring = true
        defer { isReconfiguring = false }
        
        // Stop existing pipeline if running
        stopPipeline()
        
        // Determine devices based on mode
        let inputUID: String
        let outputUID: String
        
        if manualModeEnabled {
            // Manual mode: use user-selected devices (driver not required)
            logger.debug("Manual mode: using user-selected devices")
            
            guard let selectedInput = selectedInputDeviceID else {
                routingStatus = .error("No input device selected")
                logger.error("Manual mode: no input device selected")
                return
            }
            guard let selectedOutput = selectedOutputDeviceID else {
                routingStatus = .error("No output device selected")
                logger.error("Manual mode: no output device selected")
                return
            }
            
            // Validate devices exist
            guard deviceManager.device(forUID: selectedInput) != nil else {
                routingStatus = .error("Input device not found")
                logger.error("Manual mode: input device not found: \(selectedInput)")
                return
            }
            guard deviceManager.device(forUID: selectedOutput) != nil else {
                routingStatus = .error("Output device not found")
                logger.error("Manual mode: output device not found: \(selectedOutput)")
                return
            }
            
            inputUID = selectedInput
            outputUID = selectedOutput
            
            logger.info("Manual mode: input=\(selectedInput), output=\(selectedOutput)")
            
        } else {
            // Automatic mode: derive from macOS default
            logger.debug("Automatic mode: deriving from macOS default")
            
            // Check if driver is installed (required for automatic mode)
            guard DriverManager.shared.isReady else {
                routingStatus = .driverNotInstalled
                logger.warning("Routing cannot start: driver not installed")
                showDriverPrompt = true
                return
            }
            
            // Check if driver is currently visible in CoreAudio
            if !DriverManager.shared.isDriverVisible() {
                logger.warning("Driver not immediately visible, waiting for reconnection...")
                
                Task { @MainActor in
                    if await DriverManager.shared.findDriverDeviceWithRetry() != nil {
                        logger.info("Driver became visible, retrying routing configuration")
                        self.reconfigureRouting()
                    } else {
                        logger.error("Driver did not become visible within timeout")
                        self.routingStatus = .driverNotInstalled
                        self.showDriverPrompt = true
                    }
                }
                return
            }
            
            // Input is always driver in automatic mode
            inputUID = DRIVER_DEVICE_UID
            
            // Determine output device using pure selection logic
            let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID()
            let selection = Self.determineAutomaticOutputDevice(
                currentSelected: selectedOutputDeviceID,
                macDefault: macDefault,
                availableDevices: deviceManager.outputDevices
            )
            
            switch selection {
            case .preserveCurrent(let uid):
                outputUID = uid
                logger.debug("Automatic mode: preserving selected output")
                
            case .useMacDefault(let uid):
                outputUID = uid
                logger.debug("Automatic mode: using macOS default output: \(uid)")
                
            case .useFallback:
                guard let fallback = findFallbackOutputDevice() else {
                    routingStatus = .error("No output device available")
                    logger.error("Automatic mode: no output device available")
                    return
                }
                outputUID = fallback.uid
                logger.info("Automatic mode: using fallback output: \(fallback.name)")
            }
            
            // Update selected devices to reflect current state
            selectedInputDeviceID = inputUID
            selectedOutputDeviceID = outputUID
            
            // Rename driver to match output device
            _ = updateDriverName()
            
            // Set driver as macOS default (with loop prevention)
            systemDefaultObserver.setDriverAsDefault(
                onSuccess: { [weak self] in
                    self?.logger.info("Automatic mode: set driver as system default output")
                },
                onFailure: { [weak self] in
                    self?.routingStatus = .error("Failed to set system default output device")
                    self?.logger.error("Automatic mode: failed to set driver as system default")
                    DriverManager.shared.restoreToBuiltInSpeakers()
                }
            )
        }
        
        // Get device IDs and names
        // For automatic mode, ensure driver is still visible before proceeding
        if !manualModeEnabled && inputUID == DRIVER_DEVICE_UID {
            if !DriverManager.shared.isDriverVisible() {
                logger.warning("Driver became hidden during configuration, waiting...")

                Task { @MainActor in
                    if await DriverManager.shared.findDriverDeviceWithRetry() != nil {
                        logger.info("Driver became visible, retrying routing configuration")
                        self.reconfigureRouting()
                    } else {
                        self.routingStatus = .error("Driver device not found")
                        self.logger.error("Driver did not become visible during device resolution")
                        self.showDriverPrompt = true
                    }
                }
                return
            }
        }

        guard let inputDeviceID = deviceManager.deviceID(forUID: inputUID),
              let outputDeviceID = deviceManager.deviceID(forUID: outputUID),
              let outputDevice = deviceManager.device(forUID: outputUID) else {
            routingStatus = .error("Failed to resolve device IDs")
            logger.error("Failed to resolve device IDs")
            return
        }

        logger.debug("Device IDs resolved: input=\(inputDeviceID), output=\(outputDeviceID)")

        // Sync driver sample rate to match output device (automatic mode only)
        if !manualModeEnabled {
            syncDriverSampleRate(to: outputDeviceID)
        }

        // Set up listener for output device sample rate changes
        setupSampleRateListener(for: outputDeviceID)

        // Create and configure the render pipeline
        let outputName = outputDevice.name

        // In automatic mode, use the intended driver name (just set via updateDriverName)
        // instead of reading from cached device list which may not have refreshed yet
        let inputName: String
        if manualModeEnabled {
            guard let inputDevice = deviceManager.device(forUID: inputUID) else {
                routingStatus = .error("Failed to resolve input device")
                logger.error("Manual mode: failed to resolve input device")
                return
            }
            // If input is the driver, use known name "Equaliser" (cache may be stale after rename)
            if inputUID == DRIVER_DEVICE_UID {
                inputName = "Equaliser"
            } else {
                inputName = inputDevice.name
            }
        } else {
            inputName = "\(outputDevice.name) (Equaliser)"
        }

        routingStatus = .starting
        logger.info("Starting routing: \(inputName) → \(outputName)")

        let pipeline = RenderPipeline(eqConfiguration: eqConfiguration)

        switch pipeline.configure(inputDeviceID: inputDeviceID, outputDeviceID: outputDeviceID) {
        case .success:
            break // RenderPipeline logs success at info level
        case .failure(let error):
            routingStatus = .error("Configuration failed: \(error.localizedDescription)")
            logger.error("Pipeline configuration failed: \(error.localizedDescription)")
            return
        }

        // Start the pipeline
        switch pipeline.start() {
        case .success:
            renderPipeline = pipeline
            routingStatus = .active(inputName: inputName, outputName: outputName)
            logger.info("Routing active: \(inputName) → \(outputName)")
            meterStore.setRenderPipeline(pipeline)
            meterStore.startMeterUpdates()
            
            // Set up volume sync between driver and output device (automatic mode only)
            if !manualModeEnabled, let driverID = DriverManager.shared.deviceID {
                // Wire up boost gain callback before setting up volume sync
                volumeSyncCoordinator.onBoostGainChanged = { [weak self] boostGain in
                    self?.renderPipeline?.updateBoostGain(linear: boostGain)
                }
                volumeSyncCoordinator.setup(driverID: driverID, outputID: outputDeviceID)
            }
            
        case .failure(let error):
            routingStatus = .error("Start failed: \(error.localizedDescription)")
            logger.error("Pipeline start failed: \(error.localizedDescription)")
        }
    }
    
    /// Stops the current audio routing and restores system defaults (automatic mode only).
    func stopRouting() {
        logger.info("stopRouting called, manualMode=\(self.manualModeEnabled)")
        
        // Stop the pipeline
        stopPipeline()
        
        // In automatic mode, restore macOS default
        if !manualModeEnabled {
            // Restore to selected output device
            if let outputUID = selectedOutputDeviceID,
               outputUID != DRIVER_DEVICE_UID {
                
                let restored = systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
                if !restored {
                    logger.warning("Failed to restore output device, using fallback")
                    if let fallback = findFallbackOutputDevice() {
                        systemDefaultObserver.restoreSystemDefaultOutput(to: fallback.uid)
                    } else {
                        DriverManager.shared.restoreToBuiltInSpeakers()
                    }
                }
            } else {
                // No valid output, use fallback
                if let fallback = findFallbackOutputDevice() {
                    systemDefaultObserver.restoreSystemDefaultOutput(to: fallback.uid)
                } else {
                    DriverManager.shared.restoreToBuiltInSpeakers()
                }
            }
            
            // Rename driver back to "Equaliser"
            _ = updateDriverName()
        }
        // In manual mode, don't modify macOS default
        
        // Clear loop prevention flag
        systemDefaultObserver.clearAppSettingFlagAfterDelay()
        
        routingStatus = .idle
        logger.info("Routing stopped")
    }
    
    /// Called after driver installation completes successfully.
    /// Starts routing in automatic mode.
    func handleDriverInstalled() {
        showDriverPrompt = false
        logger.info("Driver installed, starting routing")
        reconfigureRouting()
    }
    
    /// Switches to manual mode when user declines to install driver.
    func switchToManualMode() {
        showDriverPrompt = false
        manualModeEnabled = true
        deviceChangeHandler.clearHistory()

        // Rename driver back to default since it's no longer used in manual mode
        _ = updateDriverName()

        // Reset driver volume to 100% for clean state when returning to automatic mode
        if let driverID = DriverManager.shared.deviceID {
            _ = deviceManager.setDeviceVolumeScalar(deviceID: driverID, volume: 1.0)
        }

        logger.info("Switched to manual mode")

        // Attempt routing if both input and output devices are selected
        if selectedInputDeviceID != nil && selectedOutputDeviceID != nil {
            reconfigureRouting()
        }
    }
    
    /// Switches to automatic mode from manual mode.
    /// Shows driver and starts routing.
    func switchToAutomaticMode() {
        guard DriverManager.shared.isReady else {
            logger.warning("Cannot switch to automatic mode: driver not installed")
            return
        }

        manualModeEnabled = false
        logger.info("Switched to automatic mode")

        // Start routing (this will rename the driver)
        reconfigureRouting()
    }
    
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
    
    /// Updates a band's gain on the render pipeline.
    func updateBandGain(index: Int) {
        renderPipeline?.updateBandGain(index: index)
    }
    
    /// Updates a band's bandwidth on the render pipeline.
    func updateBandBandwidth(index: Int) {
        renderPipeline?.updateBandBandwidth(index: index)
    }
    
    /// Updates a band's frequency on the render pipeline.
    func updateBandFrequency(index: Int) {
        renderPipeline?.updateBandFrequency(index: index)
    }
    
    /// Updates a band's filter type on the render pipeline.
    func updateBandFilterType(index: Int) {
        renderPipeline?.updateBandFilterType(index: index)
    }
    
    /// Updates a band's bypass state on the render pipeline.
    func updateBandBypass(index: Int) {
        renderPipeline?.updateBandBypass(index: index)
    }
    
    /// Reapplies the entire configuration to the render pipeline.
    func reapplyConfiguration() {
        renderPipeline?.reapplyConfiguration()
    }
    
    // MARK: - Static Device Selection Logic
    
    /// Determines which output device to use in automatic mode.
    /// Pure function — no side effects, testable with any inputs.
    ///
    /// - Parameters:
    ///   - currentSelected: Currently selected output device UID (if any)
    ///   - macDefault: Current macOS default output device UID (if any)
    ///   - availableDevices: List of available output devices
    /// - Returns: Selection decision indicating which device to use
    static func determineAutomaticOutputDevice(
        currentSelected: String?,
        macDefault: String?,
        availableDevices: [AudioDevice]
    ) -> OutputDeviceSelection {
        // If current selection is valid (not driver, exists, not virtual), preserve it
        if let current = currentSelected,
           current != DRIVER_DEVICE_UID,
           let device = availableDevices.first(where: { $0.uid == current }),
           !device.isVirtual {
            return .preserveCurrent(current)
        }
        
        // If macOS default exists and isn't the driver, use it
        if let defaultUID = macDefault,
           defaultUID != DRIVER_DEVICE_UID,
           let device = availableDevices.first(where: { $0.uid == defaultUID }),
           !device.isVirtual {
            return .useMacDefault(defaultUID)
        }
        
        // Otherwise need fallback
        return .useFallback
    }
    
    // MARK: - Private Methods
    
    private func stopPipeline() {
        if let pipeline = renderPipeline {
            meterStore.stopMeterUpdates()
            meterStore.setRenderPipeline(nil)
            _ = pipeline.stop()
            renderPipeline = nil
        }
        
        // Clear callbacks and tear down volume sync
        volumeSyncCoordinator.onBoostGainChanged = nil
        volumeSyncCoordinator.tearDown()
    }
    
    private func syncDriverSampleRate(to outputDeviceID: AudioDeviceID) {
        // Get output device's sample rate (prefer actual over nominal)
        let outputRate = deviceManager.getActualSampleRate(deviceID: outputDeviceID)
            ?? deviceManager.getNominalSampleRate(deviceID: outputDeviceID)
        
        guard let targetRate = outputRate else {
            logger.warning("Could not determine output device sample rate")
            return
        }
        
        // Set driver to closest supported rate
        guard let setRate = DriverManager.shared.setDriverSampleRate(matching: targetRate) else {
            logger.error("Failed to sync driver sample rate")
            return
        }
        
        logger.info("Driver sample rate synced: \(setRate) Hz (output: \(targetRate) Hz)")
    }
    
    private func setupSampleRateListener(for outputDeviceID: AudioDeviceID) {
        // Clean up previous listener if any
        if let previousDeviceID = observedOutputDeviceID {
            deviceManager.stopObservingSampleRateChanges(on: previousDeviceID)
        }
        
        observedOutputDeviceID = outputDeviceID
        
        // Start observing rate changes
        deviceManager.observeSampleRateChanges(on: outputDeviceID) { [weak self] newRate in
            guard let self = self else { return }
            
            // Only sync if routing is active and in automatic mode
            guard case .active = self.routingStatus, !self.manualModeEnabled else { return }
            
            self.logger.info("Output device sample rate changed to \(newRate) Hz, re-syncing driver")
            
            // Sync driver to new rate
            if let setRate = DriverManager.shared.setDriverSampleRate(matching: newRate) {
                self.logger.info("Driver re-synced to \(setRate) Hz")
                
                // Reconfigure pipeline after rate change settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.reconfigureRouting()
                }
            }
        }
    }
    
    private func handleSystemDefaultChanged(_ device: AudioDevice) {
        // In manual mode, ignore macOS changes
        guard !manualModeEnabled else {
            logger.debug("Manual mode: ignoring macOS output change notification")
            return
        }
        
        logger.debug("macOS default output changed to: \(device.name) (uid=\(device.uid))")
        
        // Check if same as currently selected output
        if device.uid == selectedOutputDeviceID {
            logger.info("Same output device selected, reconfiguring to ensure driver visibility")
            reconfigureRouting()
            return
        }
        
        // Save current output to history before switching (automatic mode only)
        if let current = selectedOutputDeviceID,
           current != DRIVER_DEVICE_UID,
           current != device.uid {
            deviceChangeHandler.addToHistory(current)
        }
        
        // Update output device
        selectedOutputDeviceID = device.uid

        // Reconfigure routing (this will rename the driver)
        reconfigureRouting()
    }
    
    private func handleDeviceDisconnected() {
        // Only handle in automatic mode (driver is used)
        guard !manualModeEnabled else {
            logger.debug("Manual mode: ignoring device disconnect handling for driver")
            return
        }

        // Check if our currently selected output device still exists
        guard !deviceChangeHandler.deviceStillExists(selectedOutputDeviceID) else {
            logger.debug("Selected output device still exists, no action needed")
            return
        }
        
        logger.info("Selected output device disconnected, finding replacement")
        
        // Find replacement device
        if let replacement = deviceChangeHandler.findReplacementDevice(currentUID: selectedOutputDeviceID) {
            selectedOutputDeviceID = replacement.uid
            logger.info("Using replacement device: \(replacement.name)")

            // Reconfigure routing (this will rename the driver)
            reconfigureRouting()
        } else {
            // No output device available
            logger.error("No output device available after disconnect")
            routingStatus = .error("No output device available")
        }
    }
    
    private func findFallbackOutputDevice() -> AudioDevice? {
        DeviceManager.selectFallbackOutputDevice(from: deviceManager.outputDevices)
    }
    
    // MARK: - Init-time Configuration

    /// Configures callbacks after initialization (for cross-reference callbacks).
    func configureCallbacks(
        onSystemDefaultChanged: ((AudioDevice) -> Void)? = nil,
        onDeviceDisconnected: ((AudioDevice?) -> Void)? = nil
    ) {
        // Already configured in init, but allow override if needed
    }

    // MARK: - Driver Name Management

    /// Updates the driver name based on current routing state.
    ///
    /// This method handles naming the driver to reflect the current output device:
    /// - **Automatic mode (routing active)**: Sets name to "{outputDevice} (Equaliser)"
    /// - **Automatic mode (not routing)**: Sets name to "{outputDevice} (Equaliser)"
    /// - **Manual mode**: Resets name to "Equaliser"
    ///
    /// ## Why Refresh After Name Change
    ///
    /// After setting the driver name, we must refresh the device list because:
    /// 1. CoreAudio caches device names - the cache becomes stale after rename
    /// 2. The UI displays device names from the cached list
    /// 3. Without refresh, the status bar shows outdated driver names
    ///
    /// ## The Toggle Pattern
    ///
    /// Simply renaming the driver doesn't trigger CoreAudio notifications. We use a
    /// toggle pattern to force macOS to notice the change:
    /// 1. Set driver name via CoreAudio property
    /// 2. Set output device as default (triggers notification)
    /// 3. After 0.1s delay, set driver as default again (triggers notification)
    /// 4. Refresh device list to get updated name
    ///
    /// The delay is necessary because CoreAudio notifications are asynchronous.
    ///
    /// - Returns: `true` if name was set and verified, `false` otherwise.
    @discardableResult
    private func updateDriverName() -> Bool {
        // Manual mode or not routing: reset to default name
        guard !manualModeEnabled else {
            let success = DriverManager.shared.setDeviceName("Equaliser")

            // Trigger macOS Control Center refresh by toggling default output
            // When switching from automatic to manual mode:
            // - Driver is already default (from automatic mode)
            // - Setting driver as default again is a no-op (no notification)
            // - Toggle to output device and back to trigger CoreAudio notifications
            if success, let outputUID = selectedOutputDeviceID {
                // First, set the output device as default (triggers notification)
                systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)

                // Then, set driver back as default (triggers another notification)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.systemDefaultObserver.setDriverAsDefault()
                    // Refresh device list so status shows updated driver name
                    self?.deviceManager.refreshDevices()
                    self?.logger.debug("Device list refreshed after driver name change")
                }
            }

            return success
        }

        // Automatic mode: need output device and visible driver
        guard let outputUID = selectedOutputDeviceID,
              let outputDevice = deviceManager.device(forUID: outputUID),
              DriverManager.shared.isDriverVisible() else {
            logger.warning("updateDriverName: cannot update - no output device or driver not visible")
            return false
        }

        let driverName = "\(outputDevice.name) (Equaliser)"
        let success = DriverManager.shared.setDeviceName(driverName)

        // Trigger macOS Control Center refresh by toggling default output
        // When switching from manual to automatic mode:
        // - Driver may or may not be the current default
        // - Toggle to output device and back to ensure CoreAudio notifications fire
        if success, let _ = DriverManager.shared.deviceID {
            systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.systemDefaultObserver.setDriverAsDefault()
                // Refresh device list so status shows updated driver name
                self?.deviceManager.refreshDevices()
                self?.logger.debug("Device list refreshed after driver name change")
            }
        }

        return success
    }
}