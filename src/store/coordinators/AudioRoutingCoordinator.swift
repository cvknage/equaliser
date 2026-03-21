// AudioRoutingCoordinator.swift
// Coordinates audio routing: device selection and pipeline management

import AVFoundation
import Combine
import CoreAudio
import Foundation
import OSLog

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
    let deviceChangeCoordinator: DeviceChangeCoordinator
    private let eqConfiguration: EQConfiguration
    private let meterStore: MeterStore
    private let volumeService: VolumeControlling
    private let systemDefaultObserver: SystemDefaultObserver
    private let sampleRateService: SampleRateObserving
    
    // MARK: - Private Properties
    
    private var renderPipeline: RenderPipeline?
    private var volumeManager: VolumeManager?
    private var observedOutputDeviceID: AudioDeviceID?
    private var isReconfiguring = false
    private var cancellables = Set<AnyCancellable>()
    
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AudioRoutingCoordinator")
    
    // MARK: - Initialization
    
    init(
        deviceManager: DeviceManager,
        deviceChangeCoordinator: DeviceChangeCoordinator,
        eqConfiguration: EQConfiguration,
        meterStore: MeterStore,
        volumeService: VolumeControlling,
        systemDefaultObserver: SystemDefaultObserver,
        sampleRateService: SampleRateObserving
    ) {
        self.deviceManager = deviceManager
        self.deviceChangeCoordinator = deviceChangeCoordinator
        self.eqConfiguration = eqConfiguration
        self.meterStore = meterStore
        self.volumeService = volumeService
        self.systemDefaultObserver = systemDefaultObserver
        self.sampleRateService = sampleRateService
        
        // Wire up system default callback
        systemDefaultObserver.onSystemDefaultChanged = { [weak self] device in
            self?.handleSystemDefaultChanged(device)
        }
        
        // Wire up device change coordinator callbacks
        deviceChangeCoordinator.onBuiltInDeviceAdded = { [weak self] device in
            self?.handleBuiltInDeviceAdded(device)
        }
        deviceChangeCoordinator.onBuiltInDevicesRemoved = { [weak self] in
            self?.handleBuiltInDevicesRemoved()
        }
        deviceChangeCoordinator.onSelectedOutputMissing = { [weak self] uid in
            self?.handleSelectedOutputMissing(uid)
        }
        
        // Set up providers for device change detection
        deviceChangeCoordinator.setProviders(
            selectedOutputProvider: { [weak self] in
                self?.selectedOutputDeviceID
            },
            manualModeProvider: { [weak self] in
                self?.manualModeEnabled ?? false
            },
            isReconfiguringProvider: { [weak self] in
                self?.isReconfiguring ?? false
            }
        )
    }
    
    // MARK: - Public Methods
    
    /// Reconfigures the audio routing pipeline.
    /// In automatic mode: derives devices from macOS default output.
    /// In manual mode: uses user-selected devices.
    func reconfigureRouting() {
        let modeStr = manualModeEnabled ? "manual" : "automatic"
        logger.debug("reconfigureRouting(mode=\(modeStr))")
        
        // Prevent re-entrant calls
        guard !isReconfiguring else {
            logger.debug("reconfigureRouting: skipped (already reconfiguring)")
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
            let selection = OutputDeviceSelection.determine(
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

        // Set up jack connection listener on built-in device (Intel Macs: headphone jack detection)
        // Note: Apple Silicon uses device count change detection in DeviceEnumerator instead
        if !manualModeEnabled {
            if let builtInDevice = deviceManager.enumerator.findBuiltInAudioDevice() {
                deviceChangeCoordinator.setupJackConnectionListener(for: builtInDevice.id)
            }
        }

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
                volumeManager = VolumeManager(volumeService: volumeService)
                volumeManager?.onBoostGainChanged = { [weak self] boostGain in
                    self?.renderPipeline?.updateBoostGain(linear: boostGain)
                }
                volumeManager?.setupVolumeSync(driverID: driverID, outputID: outputDeviceID)
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
        deviceChangeCoordinator.clearHistory()

        // Rename driver back to default since it's no longer used in manual mode
        _ = updateDriverName()

        // Reset driver volume to 100% for clean state when returning to automatic mode
        if let driverID = DriverManager.shared.deviceID {
            // Note: This uses DeviceManager's volume method directly since we need
            // to reset driver volume, and volumeService is a protocol that VolumeManager
            // uses internally. The driver reset is a one-time operation, not ongoing sync.
            deviceManager.setDeviceVolumeScalar(deviceID: driverID, volume: 1.0)
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
    
    /// Returns the current band capacity of the render pipeline, or 0 if not active.
    func currentBandCapacity() -> Int {
        renderPipeline?.bandCapacity ?? 0
    }
    /// Reapplies the entire configuration to the render pipeline.
    func reapplyConfiguration() {
        renderPipeline?.reapplyConfiguration()
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
        volumeManager?.onBoostGainChanged = nil
        volumeManager?.tearDown()
        volumeManager = nil
        
        // Clean up jack connection listener (Intel Macs)
        deviceChangeCoordinator.cleanupJackConnectionListener()
    }
    
    private func syncDriverSampleRate(to outputDeviceID: AudioDeviceID) {
        // Get output device's sample rate (prefer actual over nominal)
        let outputRate = sampleRateService.getActualSampleRate(deviceID: outputDeviceID)
            ?? sampleRateService.getNominalSampleRate(deviceID: outputDeviceID)
        
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
            sampleRateService.stopObservingSampleRateChanges(on: previousDeviceID)
        }
        
        observedOutputDeviceID = outputDeviceID
        
        // Start observing rate changes
        sampleRateService.observeSampleRateChanges(on: outputDeviceID) { [weak self] newRate in
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
            logger.debug("handleSystemDefaultChanged: Manual mode - ignoring")
            return
        }
        
        logger.info("handleSystemDefaultChanged: macOS default output changed to '\(device.name)' (uid=\(device.uid))")
        logger.debug("handleSystemDefaultChanged: Current selected output: \(self.selectedOutputDeviceID ?? "nil")")
        
        // Check if same as currently selected output
        if device.uid == selectedOutputDeviceID {
            logger.info("handleSystemDefaultChanged: Same device already selected - reconfiguring")
            reconfigureRouting()
            return
        }
        
        // Save current output to history before switching (automatic mode only)
        if let current = selectedOutputDeviceID,
           current != DRIVER_DEVICE_UID,
           current != device.uid {
            deviceChangeCoordinator.addToHistory(current)
            logger.debug("handleSystemDefaultChanged: Saved previous output to history")
        }
        
        // Update output device
        selectedOutputDeviceID = device.uid
        logger.info("handleSystemDefaultChanged: Switching to '\(device.name)'")

        // Reconfigure routing (this will rename the driver)
        reconfigureRouting()
    }
    
    // MARK: - Device Change Handlers
    
    /// Called when the selected output device is missing from available devices.
    private func handleSelectedOutputMissing(_ uid: String) {
        // Only handle in automatic mode (driver is used)
        guard !manualModeEnabled else {
            logger.debug("Manual mode: ignoring missing device")
            return
        }
        
        logger.info("Selected output device missing: \(uid)")
        
        // Find replacement device
        if let replacement = deviceChangeCoordinator.findReplacementDevice(for: selectedOutputDeviceID) {
            selectedOutputDeviceID = replacement.uid
            logger.info("Using replacement device: \(replacement.name)")
            reconfigureRouting()
        } else {
            // No output device available
            logger.error("No output device available after disconnect")
            routingStatus = .error("No output device available")
        }
    }
    
    /// Called when built-in devices are removed (Apple Silicon: headphones unplugged).
    private func handleBuiltInDevicesRemoved() {
        // Only handle in automatic mode
        guard !manualModeEnabled else { return }
        
        // Clear missing tracking so we can detect if current device is missing
        deviceChangeCoordinator.clearMissingTracking()
    }
    
    /// Called when a single built-in device is added (Apple Silicon: headphones plugged in).
    private func handleBuiltInDeviceAdded(_ device: AudioDevice) {
        // Only handle in automatic mode
        guard !manualModeEnabled else {
            logger.debug("handleBuiltInDeviceAdded: Manual mode - ignoring")
            return
        }
        
        // Don't reconfigure during reconfiguration
        guard !isReconfiguring else {
            logger.debug("handleBuiltInDeviceAdded: Already reconfiguring - ignoring")
            return
        }
        
        // Only switch if currently routing to a built-in device
        // (Never switch away from USB/Bluetooth/HDMI - matches macOS behaviour)
        guard let currentUID = selectedOutputDeviceID,
              let currentDevice = deviceManager.device(forUID: currentUID),
              currentDevice.transportType == kAudioDeviceTransportTypeBuiltIn else {
            logger.debug("handleBuiltInDeviceAdded: Current output is not built-in, not switching")
            return
        }
        
        logger.info("Headphones detected: '\(device.name)', switching output")
        
        // Save current device to history for restoration when headphones unplugged
        if currentUID != DRIVER_DEVICE_UID,
           currentUID != device.uid {
            deviceChangeCoordinator.addToHistory(currentUID)
        }
        
        // Switch to the new built-in device (headphones)
        selectedOutputDeviceID = device.uid
        reconfigureRouting()
    }
    
    private func findFallbackOutputDevice() -> AudioDevice? {
        deviceManager.selectFallbackOutputDevice()
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