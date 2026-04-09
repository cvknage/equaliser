// AudioRoutingCoordinator.swift
// Coordinates audio routing: device selection and pipeline management

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
    @Published var manualModeEnabled: Bool = false {
        didSet { routingMode = manualModeEnabled ? ManualRoutingMode() as RoutingMode : AutomaticRoutingMode() as RoutingMode }
    }
    private(set) var routingMode: RoutingMode = AutomaticRoutingMode()
    @Published var showDriverPrompt: Bool = false
    
    /// Whether the driver needs updating (supports outdated driver detection).
    /// Set when driver doesn't support shared memory capture.
    @Published var showDriverUpdateRequired: Bool = false

    /// Capture mode preference for automatic routing.
    /// In automatic mode with the Equaliser driver, this determines how audio is captured.
    /// Manual mode always uses HAL input capture.
    @Published var captureMode: CaptureMode = .sharedMemory
    
    // MARK: - Dependencies

    let deviceProvider: DeviceProviding
    let deviceChangeCoordinator: DeviceChangeCoordinator
    private let eqConfiguration: EQConfiguration
    private let meterStore: MeterStore
    private let volumeService: VolumeControlling
    private let permissionService: PermissionRequesting

    // MARK: - Constants

    private enum Constants {
        /// Delay after syncing driver sample rate before creating HAL input unit.
        /// Allows CoreAudio to propagate the rate change.
        static let sampleRatePropagationDelay: TimeInterval = 0.1
    }
    private let systemDefaultObserver: SystemDefaultObserver
    private let sampleRateService: SampleRateObserving
    private let driverAccess: DriverAccessing
    private let driverNameManager: DriverNameManager

    // MARK: - Private Properties

    let pipelineManager: PipelineManager
    private var observedOutputDeviceID: AudioDeviceID?
    private var isReconfiguring = false
    private var cancellables = Set<AnyCancellable>()
    let eqStager: EQCoefficientStager

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AudioRoutingCoordinator")
    
    // MARK: - Initialization
    
    init(
        deviceProvider: DeviceProviding,
        deviceChangeCoordinator: DeviceChangeCoordinator,
        eqConfiguration: EQConfiguration,
        meterStore: MeterStore,
        volumeService: VolumeControlling,
        permissionService: PermissionRequesting,
        systemDefaultObserver: SystemDefaultObserver,
        sampleRateService: SampleRateObserving,
        driverAccess: DriverAccessing? = nil
    ) {
        self.deviceProvider = deviceProvider
        self.deviceChangeCoordinator = deviceChangeCoordinator
        self.eqConfiguration = eqConfiguration
        self.meterStore = meterStore
        self.volumeService = volumeService
        self.permissionService = permissionService
        self.systemDefaultObserver = systemDefaultObserver
        self.sampleRateService = sampleRateService
        self.eqStager = EQCoefficientStager(eqConfiguration: eqConfiguration)
        self.pipelineManager = PipelineManager(
            eqConfiguration: eqConfiguration,
            meterStore: meterStore,
            volumeService: volumeService,
            eqStager: eqStager
        )
        
        // Initialize driver access first (needed by driverNameManager)
        let resolvedDriverAccess = driverAccess ?? DriverManager.shared
        self.driverAccess = resolvedDriverAccess
        
        // Create driver name manager for CoreAudio refresh workaround
        self.driverNameManager = DriverNameManager(
            driverAccess: resolvedDriverAccess,
            systemDefaultObserver: systemDefaultObserver,
            deviceProvider: deviceProvider
        )
        
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

        // In manual mode, verify microphone permission before starting
        // (HAL input capture requires TCC permission)
        // Also check for automatic mode with HAL input capture preference
        let needsPermission = routingMode.needsMicPermission || (!routingMode.isManual && self.captureMode == .halInput)
        if needsPermission {
            guard permissionService.isMicPermissionGranted else {
                requestPermissionAndRetryRouting()
                return
            }

            // Permission is granted, but input devices may not be enumerated yet
            // (permission persists across sessions, but device enumeration doesn't)
            if routingMode.isManual && deviceProvider.inputDevices.isEmpty {
                logger.info("Permission granted but input devices not enumerated - enumerating now")
                deviceProvider.enumerateInputDevices()
            }
        }

        // Stop existing pipeline if running
        stopPipeline()

        // For automatic mode, check driver prerequisites before device resolution
        if routingMode.requiresDriverVisibility {
            guard driverAccess.isReady else {
                routingStatus = .driverNotInstalled
                logger.warning("Routing cannot start: driver not installed")
                showDriverPrompt = true
                return
            }

            // If driver is not visible, retry asynchronously then reconfigure
            guard driverAccess.isDriverVisible() else {
                ensureDriverVisible { [weak self] in
                    self?.reconfigureRouting()
                }
                return
            }
        }

        // Resolve devices using the routing mode strategy
        let resolution = routingMode.resolveDevices(
            selectedInputDeviceID: selectedInputDeviceID,
            selectedOutputDeviceID: selectedOutputDeviceID,
            deviceProvider: deviceProvider,
            systemDefaultObserver: systemDefaultObserver,
            driverAccess: driverAccess,
            captureMode: captureMode
        )

        let inputUID: String
        let outputUID: String

        switch resolution {
        case .resolved(let resolvedInput, let resolvedOutput):
            inputUID = resolvedInput
            outputUID = resolvedOutput
        case .failed(let message):
            routingStatus = .error(message)
            logger.error("Device resolution failed: \(message)")
            return
        }

        // Automatic mode: update selected devices and pre-sync volume
        if !routingMode.isManual {
            // Update selected devices to reflect current state
            selectedInputDeviceID = inputUID
            selectedOutputDeviceID = outputUID

            // Pre-sync driver volume BEFORE updateDriverName() to prevent macOS volume sync
            // from overwriting the new output device's volume.
            if let outputDeviceID = deviceProvider.deviceID(forUID: outputUID),
               let driverID = driverAccess.deviceID,
               let volume = volumeService.getDeviceVolumeScalar(deviceID: outputDeviceID) {
                _ = volumeService.setDeviceVolumeScalar(deviceID: driverID, volume: volume)
                logger.info("Pre-synced driver volume to: \(volume)")
            }

            // Rename driver to match output device
            _ = updateDriverName()

            // Set driver as macOS default IMMEDIATELY (before pipeline starts)
            systemDefaultObserver.setDriverAsDefault(
                onSuccess: { [weak self] in
                    self?.logger.info("Automatic mode: set driver as system default output")
                },
                onFailure: { [weak self] in
                    self?.routingStatus = .error("Failed to set system default output device")
                    self?.logger.error("Automatic mode: failed to set driver as system default")
                    self?.driverAccess.restoreToBuiltInSpeakers()
                }
            )
        }

        // Get device IDs and names
        // For automatic mode, ensure driver is still visible before proceeding
        if routingMode.requiresDriverVisibility && inputUID == DRIVER_DEVICE_UID {
            if !driverAccess.isDriverVisible() {
                ensureDriverVisible { [weak self] in
                    self?.reconfigureRouting()
                }
                return
            }
        }

        // Resolve device IDs with diagnostic logging
        let inputDeviceID = deviceProvider.deviceID(forUID: inputUID)
        let outputDeviceID = deviceProvider.deviceID(forUID: outputUID)
        let outputDevice = deviceProvider.device(forUID: outputUID)

        if inputDeviceID == nil {
            logger.error("Failed to resolve input device ID for UID: \(inputUID)")
        }
        if outputDeviceID == nil {
            logger.error("Failed to resolve output device ID for UID: \(outputUID)")
        }
        if outputDevice == nil {
            logger.error("Failed to resolve output device for UID: \(outputUID)")
        }

        guard let inputDeviceID = inputDeviceID,
              let outputDeviceID = outputDeviceID,
              let outputDevice = outputDevice else {
            routingStatus = .error("Failed to resolve device IDs")
            logger.error("Failed to resolve device IDs")
            return
        }
        
        logger.debug("Device IDs resolved: input=\(inputDeviceID), output=\(outputDeviceID)")

        // Sync driver sample rate to match output device (automatic mode only)
        if routingMode.requiresSampleRateSync {
            syncDriverSampleRate(to: outputDeviceID)
        }

        // Set up listener for output device sample rate changes
        setupSampleRateListener(for: outputDeviceID)

        // Determine capture mode early - needed to decide if we need rate sync delay
        let capturePreference: CaptureMode = routingMode.isManual ? .halInput : self.captureMode
        let supportsSharedMemory = driverAccess.hasSharedMemoryCapability()
        let captureDecision = CaptureModePolicy.determineMode(
            preference: capturePreference,
            isManualMode: routingMode.isManual,
            supportsSharedMemory: supportsSharedMemory
        )
        let resolvedCaptureMode: CaptureMode
        switch captureDecision {
        case .useMode(let mode):
            resolvedCaptureMode = mode
        case .fallbackToHALInput:
            resolvedCaptureMode = .halInput
        }

        // For HAL input mode in automatic mode, add delay after sample rate sync
        // to allow CoreAudio to propagate the rate change before creating input HAL unit.
        // In shared memory mode, no input HAL unit is created, so no delay needed.
        let needsRateSyncDelay = !routingMode.isManual && resolvedCaptureMode == .halInput

        if needsRateSyncDelay {
            // Delay to allow CoreAudio to propagate sample rate change
            logger.debug("Waiting for driver sample rate propagation before HAL input configuration")
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.sampleRatePropagationDelay) { [weak self] in
                self?.continueRoutingConfiguration(
                    inputDeviceID: inputDeviceID,
                    outputDeviceID: outputDeviceID,
                    outputDevice: outputDevice,
                    inputUID: inputUID,
                    outputUID: outputUID,
                    resolvedCaptureMode: resolvedCaptureMode,
                    captureDecision: captureDecision
                )
            }
        } else {
            continueRoutingConfiguration(
                inputDeviceID: inputDeviceID,
                outputDeviceID: outputDeviceID,
                outputDevice: outputDevice,
                inputUID: inputUID,
                outputUID: outputUID,
                resolvedCaptureMode: resolvedCaptureMode,
                captureDecision: captureDecision
            )
        }
    }

    /// Continues routing configuration after optional rate sync delay.
    /// Separated to allow async delay for HAL input mode.
    private func continueRoutingConfiguration(
        inputDeviceID: AudioDeviceID,
        outputDeviceID: AudioDeviceID,
        outputDevice: AudioDevice,
        inputUID: String,
        outputUID: String,
        resolvedCaptureMode: CaptureMode,
        captureDecision: CaptureModeDecision
    ) {

        // Set up jack connection listener on built-in device (Intel Macs: headphone jack detection)
        // Note: Apple Silicon uses device count change detection in DeviceEnumerationService instead
        if !routingMode.isManual {
            if let builtInDevice = deviceProvider.findBuiltInAudioDevice() {
                deviceChangeCoordinator.setupJackConnectionListener(for: builtInDevice.id)
            }
        }

        // Create and configure the render pipeline
        let outputName = outputDevice.name

        // In automatic mode, use the intended driver name (just set via updateDriverName)
        // instead of reading from cached device list which may not have refreshed yet
        let inputName: String
        if routingMode.isManual {
            guard let inputDevice = deviceProvider.device(forUID: inputUID) else {
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

        // Handle capture mode decision (already determined in reconfigureRouting)
        if case .fallbackToHALInput = captureDecision {
            logger.info("Driver does not support shared memory, falling back to HAL input")
            showDriverUpdateRequired = true
        }

        // Clear driver update flag when using shared memory successfully
        if resolvedCaptureMode == .sharedMemory {
            showDriverUpdateRequired = false
        }

        // Validate shared memory capture requirements
        if resolvedCaptureMode == .sharedMemory {
            guard inputUID == DRIVER_DEVICE_UID else {
                routingStatus = .error("Shared memory capture requires Equaliser driver")
                logger.error("Shared memory capture requires driver as input")
                return
            }
            guard driverAccess.isReady else {
                routingStatus = .error("Driver not installed")
                logger.error("Shared memory capture requires driver")
                return
            }
        }

        // HAL input requires microphone permission
        if resolvedCaptureMode == .halInput {
            guard permissionService.isMicPermissionGranted else {
                requestPermissionAndRetryRouting()
                return
            }
        }

        let registry: DriverDeviceRegistry? = resolvedCaptureMode == .sharedMemory ? driverAccess.deviceRegistry : nil

        let result = pipelineManager.startPipeline(
            inputDeviceID: inputDeviceID,
            outputDeviceID: outputDeviceID,
            captureMode: resolvedCaptureMode,
            driverRegistry: registry,
            isAutomaticMode: !routingMode.isManual,
            driverID: driverAccess.deviceID,
            driverOutputDeviceID: outputDeviceID
        )

        switch result {
        case .success(let sampleRate):
            routingStatus = .active(inputName: inputName, outputName: outputName)
            logger.info("Routing active: \(inputName) → \(outputName)")

            // Update sample rate for coefficient calculations
            eqStager.setCurrentSampleRate(sampleRate)

        case .configurationFailed(let error):
            routingStatus = .error("Configuration failed: \(error)")
            logger.error("Pipeline configuration failed: \(error)")

        case .startFailed(let error):
            routingStatus = .error("Start failed: \(error)")
            logger.error("Pipeline start failed: \(error)")
        }
    }

    /// Requests microphone permission and retries routing.
    /// Called when HAL input capture is needed and microphone permission hasn't been granted.
    private func requestPermissionAndRetryRouting() {
        routingStatus = .starting  // Show loading state while requesting permission

        Task { @MainActor in
            let granted = await permissionService.requestMicPermission()

            if granted {
                logger.info("Microphone permission granted")
                // Enumerate input devices now that we have permission
                deviceProvider.enumerateInputDevices()
                // Retry routing - permission now granted, HAL input will work
                reconfigureRouting()
            } else {
                logger.warning("Microphone permission denied")
                routingStatus = .error("Microphone permission required for audio routing")
            }
        }
    }

    /// Stops the current audio routing and restores system defaults (automatic mode only).
    func stopRouting() {
        logger.info("stopRouting called, manualMode=\(self.manualModeEnabled)")
        
        // Stop the pipeline
        stopPipeline()
        
        // In automatic mode, restore macOS default
        if !routingMode.isManual {
            // Restore to selected output device
            if let outputUID = selectedOutputDeviceID,
               outputUID != DRIVER_DEVICE_UID {
                
                let restored = systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)
                if !restored {
                    logger.warning("Failed to restore output device, using fallback")
                    if let fallback = findFallbackOutputDevice() {
                        systemDefaultObserver.restoreSystemDefaultOutput(to: fallback.uid)
                    } else {
                        driverAccess.restoreToBuiltInSpeakers()
                    }
                }
            } else {
                // No valid output, use fallback
                if let fallback = findFallbackOutputDevice() {
                    systemDefaultObserver.restoreSystemDefaultOutput(to: fallback.uid)
                } else {
                    driverAccess.restoreToBuiltInSpeakers()
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
        if let driverID = driverAccess.deviceID {
            volumeService.setDeviceVolumeScalar(deviceID: driverID, volume: 1.0)
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
        guard driverAccess.isReady else {
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
        pipelineManager.updateProcessingMode(systemEQOff: systemEQOff, compareMode: compareMode)
    }

    /// Updates the input gain on the render pipeline.
    func updateInputGain(linear: Float) {
        pipelineManager.updateInputGain(linear: linear)
    }

    /// Updates the output gain on the render pipeline.
    func updateOutputGain(linear: Float) {
        pipelineManager.updateOutputGain(linear: linear)
    }

    // MARK: - EQ Coefficient Staging (delegated to EQCoefficientStager)

    /// Updates a band's gain by recalculating and staging coefficients.
    func updateBandGain(index: Int) {
        eqStager.updateBandGain(index: index)
    }

    /// Updates a band's Q factor by recalculating and staging coefficients.
    func updateBandQ(index: Int) {
        eqStager.updateBandQ(index: index)
    }

    /// Updates a band's frequency by recalculating and staging coefficients.
    func updateBandFrequency(index: Int) {
        eqStager.updateBandFrequency(index: index)
    }

    /// Updates a band's filter type by recalculating and staging coefficients.
    func updateBandFilterType(index: Int) {
        eqStager.updateBandFilterType(index: index)
    }

    /// Updates a band's bypass state.
    func updateBandBypass(index: Int) {
        eqStager.updateBandBypass(index: index)
    }

    /// Returns the current band capacity from EQConfiguration.
    func currentBandCapacity() -> Int {
        eqStager.currentBandCapacity()
    }

    /// Reapplies all coefficients from the current configuration.
    func reapplyConfiguration() {
        eqStager.reapplyConfiguration()
    }
    
    // MARK: - Private Methods

    /// Ensures the driver is visible in CoreAudio, retrying if necessary.
    /// Calls `onVisible` if the driver is found, or sets an error state if not.
    private func ensureDriverVisible(onVisible: @escaping @MainActor () -> Void) {
        guard !driverAccess.isDriverVisible() else {
            onVisible()
            return
        }

        logger.warning("Driver not immediately visible, waiting for reconnection...")

        Task { @MainActor in
            if await driverAccess.findDriverDeviceWithRetry(initialDelayMs: 100, maxAttempts: 6) != nil {
                logger.info("Driver became visible, retrying routing configuration")
                onVisible()
            } else {
                logger.error("Driver did not become visible within timeout")
                routingStatus = .driverNotInstalled
                showDriverPrompt = true
            }
        }
    }

    private func stopPipeline() {
        pipelineManager.stopPipeline()

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
        guard let setRate = driverAccess.setDriverSampleRate(matching: targetRate) else {
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
            if let setRate = driverAccess.setDriverSampleRate(matching: newRate) {
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
        guard routingMode.handlesSystemDefaultChanges else {
            logger.debug("handleSystemDefaultChanged: Manual mode - ignoring")
            return
        }

        logger.info("handleSystemDefaultChanged: macOS default output changed to '\(device.name)' (uid=\(device.uid))")
        logger.debug("handleSystemDefaultChanged: Current selected output: \(self.selectedOutputDeviceID ?? "nil")")

        // IMMEDIATE check for same device - no debounce delay
        // When user clicks the same device in System Settings, just restore the driver as default
        if device.uid == selectedOutputDeviceID {
            if routingStatus.isActive {
                logger.info("handleSystemDefaultChanged: Same device already selected - restoring driver as default")
                systemDefaultObserver.setDriverAsDefault(shortTimeout: true)
            } else {
                logger.info("handleSystemDefaultChanged: Same device selected but routing inactive - reconfiguring")
                reconfigureRouting()
            }
            return
        }

        // Different device - reconfigure immediately (no debounce)
        // Save current output to history before switching
        if let current = selectedOutputDeviceID,
           current != DRIVER_DEVICE_UID,
           current != device.uid {
            deviceChangeCoordinator.addToHistory(current)
            logger.debug("handleSystemDefaultChanged: Saved previous output to history")
        }

        // Update output device
        selectedOutputDeviceID = device.uid
        logger.info("handleSystemDefaultChanged: Switching to '\(device.name)'")

        // Reconfigure routing immediately
        reconfigureRouting()
    }

    // MARK: - Device Change Handlers
    
    /// Called when the selected output device is missing from available devices.
    private func handleSelectedOutputMissing(_ uid: String) {
        // Only handle in automatic mode (driver is used)
        guard routingMode.handlesBuiltInDeviceChanges else {
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
        guard routingMode.handlesBuiltInDeviceChanges else { return }
        
        // Clear missing tracking so we can detect if current device is missing
        deviceChangeCoordinator.clearMissingTracking()
    }
    
    /// Called when a single built-in device is added (Apple Silicon: headphones plugged in).
    private func handleBuiltInDeviceAdded(_ device: AudioDevice) {
        guard routingMode.handlesBuiltInDeviceChanges else {
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
              let currentDevice = deviceProvider.device(forUID: currentUID),
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
        deviceProvider.selectFallbackOutputDevice()
    }
    
    // MARK: - Init-time Configuration

    // MARK: - Driver Name Management

    /// Updates the driver name based on current routing state.
    /// Delegates to DriverNameManager for the CoreAudio refresh workaround.
    /// This method is synchronous and returns immediately.
    /// The caller is responsible for calling setDriverAsDefault() before starting the pipeline.
    /// - Returns: `true` if name was set successfully, `false` otherwise.
    @discardableResult
    private func updateDriverName() -> Bool {
        let outputDevice = selectedOutputDeviceID.flatMap { deviceProvider.device(forUID: $0) }

        return driverNameManager.updateDriverName(
            manualMode: manualModeEnabled,
            selectedOutputUID: selectedOutputDeviceID,
            selectedOutputDevice: outputDevice
        )
    }
}