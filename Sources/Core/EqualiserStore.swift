import AVFoundation
import Combine
import Foundation
import os.log
import AppKit
import SwiftUI

enum CompareMode: Int, Codable, Sendable {
    case eq = 0
    case flat = 1
}

/// Represents the result of automatic output device selection.
enum OutputDeviceSelection: Equatable {
    /// Use the existing selected device (it's still valid)
    case preserveCurrent(String)
    /// Use the current macOS default output device
    case useMacDefault(String)
    /// Need to find a fallback device (no valid selection available)
    case useFallback
}

@MainActor
final class EqualiserStore: ObservableObject {
    // MARK: - Computed Properties (delegate to EQConfiguration)

    /// Global bypass state - delegates to eqConfiguration.globalBypass.
    var isBypassed: Bool {
        get { eqConfiguration.globalBypass }
        set {
            eqConfiguration.globalBypass = newValue
            renderPipeline?.updateProcessingMode(systemEQOff: newValue, compareMode: compareMode)
        }
    }

    /// Band count - delegates to eqConfiguration.activeBandCount.
    var bandCount: Int {
        get { eqConfiguration.activeBandCount }
        set {
            eqConfiguration.setActiveBandCount(newValue)
            reconfigureRouting()
        }
    }

    /// Input gain (dB) - delegates to eqConfiguration.inputGain.
    var inputGain: Float {
        get { eqConfiguration.inputGain }
        set {
            let clamped = Self.clampGain(newValue)
            eqConfiguration.inputGain = clamped
            renderPipeline?.updateInputGain(linear: Self.dbToLinear(clamped))
        }
    }

    /// Output gain (dB) - delegates to eqConfiguration.outputGain.
    var outputGain: Float {
        get { eqConfiguration.outputGain }
        set {
            let clamped = Self.clampGain(newValue)
            eqConfiguration.outputGain = clamped
            renderPipeline?.updateOutputGain(linear: Self.dbToLinear(clamped))
        }
    }

    // MARK: - Published Properties

    @Published var compareMode: CompareMode = .eq {
        didSet {
            renderPipeline?.updateProcessingMode(systemEQOff: isBypassed, compareMode: compareMode)

            if compareMode == .flat {
                startCompareModeRevertTimer()
            } else {
                cancelCompareModeRevertTimer()
            }
        }
    }

    @Published var selectedInputDeviceID: String? {
        didSet {
            if selectedInputDeviceID != oldValue && manualModeEnabled {
                reconfigureRouting()
            }
        }
    }

    @Published var selectedOutputDeviceID: String? {
        didSet {
            if selectedOutputDeviceID != oldValue && manualModeEnabled {
                reconfigureRouting()
            }
        }
    }

    @Published private(set) var routingStatus: RoutingStatus = .idle

    /// User preference for displaying bandwidth as octaves or Q factor.
    @Published var bandwidthDisplayMode: BandwidthDisplayMode = .octaves
    
    /// When true, user manually selects input/output devices.
    /// When false (default), devices are derived from macOS output.
    @Published var manualModeEnabled: Bool = false {
        didSet {
            // Persistence is handled on app quit via AppStatePersistence
        }
    }
    
    /// Controls visibility of the driver installation prompt window.
    /// Set to true when automatic mode is active but driver is not installed.
    @Published var showDriverPrompt: Bool = false
     
      /// Prevents infinite loop when app sets driver as default output
      private var isAppSettingSystemDefault = false
      
      /// Prevents re-entrant calls to reconfigureRouting()
      private var isReconfiguring = false
      
      /// Tracks the current output device being observed for sample rate changes.
      private var observedOutputDeviceID: AudioDeviceID?

      // MARK: - Audio Components

    /// Device manager for enumerating audio devices.
    let deviceManager = DeviceManager()

    /// EQ configuration storage (no audio engine side effects).
    let eqConfiguration: EQConfiguration

    /// Preset manager for saving and loading EQ presets.
    let presetManager: PresetManager

    /// The render pipeline connecting HAL to AVAudioEngine.
    /// Owns the HALIOManager and ManualRenderingEngine internally.
    private var renderPipeline: RenderPipeline?
    let meterStore: MeterStore
    private weak var equaliserWindow: NSWindow?
    
    /// Volume sync manager (driver ↔ output device).
    private var volumeManager: VolumeManager?

    private var compareModeRevertTimer: AnyCancellable?
    private static let compareModeRevertInterval: TimeInterval = 300 // 5 minutes

    let persistence: AppStatePersistence
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "EqualiserStore")
    private var cancellables = Set<AnyCancellable>()
    public static let gainRange: ClosedRange<Float> = -36...36

    /// Current app state snapshot for persistence.
    var currentSnapshot: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: eqConfiguration.globalBypass,
            inputGain: eqConfiguration.inputGain,
            outputGain: eqConfiguration.outputGain,
            activeBandCount: eqConfiguration.activeBandCount,
            bands: eqConfiguration.bands,
            inputDeviceID: manualModeEnabled ? selectedInputDeviceID : nil,
            outputDeviceID: selectedOutputDeviceID,
            bandwidthDisplayMode: bandwidthDisplayMode.rawValue,
            manualModeEnabled: manualModeEnabled,
            metersEnabled: meterStore.metersEnabled
        )
    }

    // MARK: - Convenience Accessors

    /// Convenience accessor for input devices from the device manager.
    var inputDevices: [AudioDevice] {
        deviceManager.inputDevices
    }

    /// Convenience accessor for output devices from the device manager.
    var outputDevices: [AudioDevice] {
        deviceManager.outputDevices
    }

    // MARK: - Initialization

    init(persistence: AppStatePersistence = AppStatePersistence()) {
        self.persistence = persistence

        // Load snapshot if exists
        let snapshot = persistence.load()

        // Initialize EQ configuration
        if let snapshot = snapshot {
            self.eqConfiguration = EQConfiguration(from: snapshot)
        } else {
            self.eqConfiguration = EQConfiguration()
        }

        // Initialize other components
        self.presetManager = PresetManager()
        self.meterStore = MeterStore(metersEnabled: snapshot?.metersEnabled ?? true)

        // Wire up persistence
        persistence.setStore(self)

        // Restore app-level state
        if let snapshot = snapshot {
            logger.debug("Loading from snapshot: outputDeviceID=\(snapshot.outputDeviceID ?? "nil"), manualMode=\(snapshot.manualModeEnabled)")
            _bandwidthDisplayMode = Published(initialValue: BandwidthDisplayMode(rawValue: snapshot.bandwidthDisplayMode) ?? .octaves)
            _manualModeEnabled = Published(initialValue: snapshot.manualModeEnabled)
            
            if snapshot.manualModeEnabled {
                // Manual mode: load saved devices
                _selectedInputDeviceID = Published(initialValue: snapshot.inputDeviceID)
                _selectedOutputDeviceID = Published(initialValue: snapshot.outputDeviceID)
                logger.debug("Manual mode: loaded saved devices")
            } else {
                // Automatic mode: derive from macOS default
                let macDefault = getCurrentSystemDefaultOutputUID()
                
                if macDefault == DRIVER_DEVICE_UID {
                    // Driver was default (from crash) - use fallback
                    logger.info("Driver was default on launch, using fallback output")
                    if let fallback = findFallbackOutputDevice() {
                        _selectedOutputDeviceID = Published(initialValue: fallback.uid)
                    }
                } else if let defaultUID = macDefault {
                    _selectedOutputDeviceID = Published(initialValue: defaultUID)
                    logger.debug("Automatic mode: using macOS default output")
                } else {
                    // No default - use fallback
                    if let fallback = findFallbackOutputDevice() {
                        _selectedOutputDeviceID = Published(initialValue: fallback.uid)
                    }
                }
                
                // Input is always driver in automatic mode
                _selectedInputDeviceID = Published(initialValue: DRIVER_DEVICE_UID)
            }
        } else {
            // First launch: automatic mode, derive from macOS default
            logger.info("First launch, no snapshot")
            _manualModeEnabled = Published(initialValue: false)
            
            let macDefault = getCurrentSystemDefaultOutputUID()
            
            if macDefault == DRIVER_DEVICE_UID {
                // Driver was default - use fallback
                logger.info("Driver was default, using fallback output")
                if let fallback = findFallbackOutputDevice() {
                    _selectedOutputDeviceID = Published(initialValue: fallback.uid)
                }
            } else if let defaultUID = macDefault {
                _selectedOutputDeviceID = Published(initialValue: defaultUID)
                logger.debug("Using macOS default output")
            } else {
                // No default - use fallback
                if let fallback = findFallbackOutputDevice() {
                    _selectedOutputDeviceID = Published(initialValue: fallback.uid)
                }
            }
            
            // Input is always driver in automatic mode
            _selectedInputDeviceID = Published(initialValue: DRIVER_DEVICE_UID)
        }

        // Check if driver prompt should be shown (automatic mode without driver)
        // Defer to next run loop so onChange can observe the transition
        Task { @MainActor in
            if !self.manualModeEnabled && !DriverManager.shared.isReady {
                self.logger.info("Automatic mode but driver not installed - showing prompt")
                self.routingStatus = .driverNotInstalled
                self.showDriverPrompt = true
            } else {
                // Driver visibility is now automatic - managed by AddDeviceClient/RemoveDeviceClient
                // When the app connects to the driver, visibility is set to true automatically
                
                if self.selectedOutputDeviceID != nil {
                    // Auto-start routing if devices are selected
                    self.reconfigureRouting()
                }
            }
        }

        eqConfiguration.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        presetManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Listen for macOS default output changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemDefaultOutputChange),
            name: .systemDefaultOutputDidChange,
            object: nil
        )

        // Listen for app termination to restore system defaults
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        // After all state is restored, check if settings differ from selected preset
        if presetManager.selectedPresetName != nil {
            let matches = presetManager.settingsMatchSelectedPreset(
                activeBandCount: eqConfiguration.activeBandCount,
                bands: eqConfiguration.bands,
                inputGain: eqConfiguration.inputGain,
                outputGain: eqConfiguration.outputGain,
                globalBypass: eqConfiguration.globalBypass
            )
            if !matches {
                presetManager.isModified = true
            }
        }
    }

      /// Handles changes to macOS system default output device.
      /// Automatically updates the selected output device when user changes it in System Settings.
      /// Only active in automatic mode - ignored in manual mode.
      @objc private func handleSystemDefaultOutputChange() {
          // In manual mode, ignore macOS changes
          guard !manualModeEnabled else {
              logger.debug("Manual mode: ignoring macOS output change notification")
              return
          }
          
          // Prevent infinite loop when app sets driver as default
          guard !isAppSettingSystemDefault else {
              logger.debug("App is setting system default, ignoring notification")
              return
          }
          
          // Get the new system default
          guard let newDefault = deviceManager.defaultOutputDevice() else {
              logger.warning("No default output device found")
              return
          }
          
          logger.debug("macOS default output changed to: \(newDefault.name) (uid=\(newDefault.uid))")
          
          // Ignore if it's our driver (we set it)
          guard newDefault.uid != DRIVER_DEVICE_UID else {
              logger.debug("New default is our driver, ignoring")
              return
          }
          
          // Check if same as currently selected output
          if newDefault.uid == selectedOutputDeviceID {
              // User re-selected the same device in macOS Sound settings
              // This means macOS default is now the output device, NOT our driver
              // We need to restore driver as default
              logger.info("Same output device selected, restoring driver as default")
              
              // Rename driver to match output device
              let driverName = "\(newDefault.name) (Equaliser)"
              DriverManager.shared.setDeviceName(driverName)
              
              // Set driver as macOS default (with loop prevention)
              isAppSettingSystemDefault = true
              guard DriverManager.shared.setAsDefaultOutputDevice() else {
                  logger.error("Failed to restore driver as system default")
                  isAppSettingSystemDefault = false
                  return
              }
              
              // Clear flag after delay
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                  self?.isAppSettingSystemDefault = false
              }
              
              // Reconfigure routing to ensure sample rate sync
              reconfigureRouting()
              return
          }
          
          logger.info("macOS output changed to: \(newDefault.name)")
          
          // Update output device
          selectedOutputDeviceID = newDefault.uid
          
          // Rename driver to match new output (only in automatic mode)
          let driverName = "\(newDefault.name) (Equaliser)"
          DriverManager.shared.setDeviceName(driverName)
          logger.info("Renamed driver to: \(driverName)")
          
          // Reconfigure routing
          reconfigureRouting()
      }

      /// Handles app termination - restores system defaults before app quits.
      @objc private func handleAppWillTerminate() {
          logger.info("App terminating, stopping routing")
          stopRouting()
          
          // Driver visibility is now automatic - managed by AddDeviceClient/RemoveDeviceClient
          // When the app disconnects from the driver, visibility is set to false automatically
      }

      // MARK: - Routing Control

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
            
            // Input is always driver in automatic mode
            inputUID = DRIVER_DEVICE_UID
            
            // Determine output device using pure selection logic
            let macDefault = getCurrentSystemDefaultOutputUID()
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
            
            // Get output device for driver naming
            guard let outputDevice = deviceManager.device(forUID: outputUID) else {
                routingStatus = .error("Output device not found")
                logger.error("Automatic mode: output device not found for UID: \(outputUID)")
                return
            }
            
            // Rename driver to match output device
            let driverName = "\(outputDevice.name) (Equaliser)"
            DriverManager.shared.setDeviceName(driverName)
            logger.info("Automatic mode: renamed driver to '\(driverName)'")
            
            // Set driver as macOS default (with loop prevention)
            isAppSettingSystemDefault = true
            guard DriverManager.shared.setAsDefaultOutputDevice() else {
                routingStatus = .error("Failed to set system default output device")
                logger.error("Automatic mode: failed to set driver as system default")
                isAppSettingSystemDefault = false
                DriverManager.shared.restoreToBuiltInSpeakers()
                return
            }
            logger.info("Automatic mode: set driver as system default output")
            
            // Clear flag after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isAppSettingSystemDefault = false
            }
        }
        
        // Get device IDs and names
        guard let inputDeviceID = deviceManager.deviceID(forUID: inputUID),
              let outputDeviceID = deviceManager.deviceID(forUID: outputUID),
              let inputDevice = deviceManager.device(forUID: inputUID),
              let outputDevice = deviceManager.device(forUID: outputUID) else {
            routingStatus = .error("Failed to resolve device IDs")
            logger.error("Failed to resolve device IDs")
            return
        }
        
        logger.debug("Device IDs resolved: input=\(inputDeviceID), output=\(outputDeviceID)")
        
        // Sync driver sample rate to match output device
        syncDriverSampleRate(to: outputDeviceID)
        
        // Set up listener for output device sample rate changes
        setupSampleRateListener(for: outputDeviceID)
        
        // Create and configure the render pipeline
        let outputName = outputDevice.name
        routingStatus = .starting
        logger.info("Starting routing: \(inputDevice.name) → \(outputName)")
        
        let pipeline = RenderPipeline(eqConfiguration: eqConfiguration)
        
        switch pipeline.configure(inputDeviceID: inputDeviceID, outputDeviceID: outputDeviceID) {
        case .success:
            logger.debug("Pipeline configured successfully")
        case .failure(let error):
            routingStatus = .error("Configuration failed: \(error.localizedDescription)")
            logger.error("Pipeline configuration failed: \(error.localizedDescription)")
            return
        }
        
        // Start the pipeline
        switch pipeline.start() {
        case .success:
            renderPipeline = pipeline
            renderPipeline?.updateInputGain(linear: EqualiserStore.dbToLinear(inputGain))
            renderPipeline?.updateOutputGain(linear: EqualiserStore.dbToLinear(outputGain))
            routingStatus = .active(inputName: inputDevice.name, outputName: outputName)
            logger.info("Routing active: \(inputDevice.name) → \(outputName)")
            meterStore.setRenderPipeline(pipeline)
            meterStore.startMeterUpdates()
            
            // Set up volume sync between driver and output device
            setupVolumeSync(driverID: DriverManager.shared.deviceID, outputID: outputDeviceID)
            
        case .failure(let error):
            routingStatus = .error("Start failed: \(error.localizedDescription)")
            logger.error("Pipeline start failed: \(error.localizedDescription)")
        }
    }
    
    /// Stops the audio pipeline without modifying macOS default.
    private func stopPipeline() {
        if let pipeline = renderPipeline {
            meterStore.stopMeterUpdates()
            meterStore.setRenderPipeline(nil)
            _ = pipeline.stop()
            renderPipeline = nil
        }
        
        // Tear down volume sync
        volumeManager?.tearDown()
        
        cancelCompareModeRevertTimer()
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
                
                let restored = restoreSystemDefaultOutput(to: outputUID)
                if !restored {
                    logger.warning("Failed to restore output device, using fallback")
                    if let fallback = findFallbackOutputDevice() {
                        restoreSystemDefaultOutput(to: fallback.uid)
                    } else {
                        DriverManager.shared.restoreToBuiltInSpeakers()
                    }
                }
            } else {
                // No valid output, use fallback
                if let fallback = findFallbackOutputDevice() {
                    restoreSystemDefaultOutput(to: fallback.uid)
                } else {
                    DriverManager.shared.restoreToBuiltInSpeakers()
                }
            }
            
            // Rename driver back to "Equaliser"
            DriverManager.shared.setDeviceName("Equaliser")
            logger.info("Renamed driver back to 'Equaliser'")
        }
        // In manual mode, don't modify macOS default
        
        // Clear loop prevention flag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAppSettingSystemDefault = false
        }
        
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
        routingStatus = .idle  // Clear driver not installed status
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
        
        // Driver visibility is automatic - managed by AddDeviceClient/RemoveDeviceClient
        
        // Start routing
        reconfigureRouting()
    }
    
    // MARK: - Sample Rate Sync
    
    /// Syncs the driver sample rate to match the output device.
    /// Finds the closest supported rate and sets it on the driver.
    /// Called before starting the audio pipeline.
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
    
    /// Sets up a listener to re-sync sample rate when output device rate changes.
    private func setupSampleRateListener(for outputDeviceID: AudioDeviceID) {
        // Clean up previous listener if any
        if let previousDeviceID = observedOutputDeviceID {
            deviceManager.stopObservingSampleRateChanges(on: previousDeviceID)
        }
        
        observedOutputDeviceID = outputDeviceID
        
        // Start observing rate changes
        deviceManager.observeSampleRateChanges(on: outputDeviceID) { [weak self] newRate in
            guard let self = self else { return }
            
            // Only sync if routing is active
            guard case .active = self.routingStatus else { return }
            
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
    
    // MARK: - Volume Sync
    
    /// Sets up volume sync between driver and output device.
    private func setupVolumeSync(driverID: AudioDeviceID?, outputID: AudioDeviceID) {
        guard let driverID = driverID else {
            logger.warning("Cannot setup volume sync: driver not ready")
            return
        }
        
        // Create volume manager if needed
        if volumeManager == nil {
            volumeManager = VolumeManager(deviceManager: deviceManager)
            volumeManager?.onBoostGainChanged = { [weak self] boostGain in
                self?.renderPipeline?.updateBoostGain(linear: boostGain)
            }
        }
        
        volumeManager?.setupVolumeSync(driverID: driverID, outputID: outputID)
        logger.info("Volume sync set up for driver=\(driverID), output=\(outputID)")
    }
    
    // MARK: - Device Helper Methods
    
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
    
    /// Finds the first valid output device for fallback.
    /// Non-virtual, non-aggregate, prefers built-in speakers.
    private func findFallbackOutputDevice() -> AudioDevice? {
        DeviceManager.selectFallbackOutputDevice(from: deviceManager.outputDevices)
    }
    
    // MARK: - System Default Management
    
    /// Gets the current system default output device UID.
    /// - Returns: The UID of the current default output device, or nil if not available.
    private func getCurrentSystemDefaultOutputUID() -> String? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }
        
        // Get UID for this device
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        guard AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &uid
        ) == noErr else {
            return nil
        }
        
        guard let uidString = uid?.takeRetainedValue() as String? else {
            return nil
        }
        
        return uidString
    }
    
     /// Restores the system default output device to the specified UID.
     /// - Parameter uid: The UID of the device to set as default.
     /// - Returns: true if successful, false otherwise.
     @discardableResult
     private func restoreSystemDefaultOutput(to uid: String) -> Bool {
         // If original device not found, fall back to built-in speakers
         guard let deviceID = deviceManager.deviceID(forUID: uid) else {
             logger.warning("Original device not found: \(uid), falling back to built-in speakers")
             return false
         }
         
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioHardwarePropertyDefaultOutputDevice,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var deviceIDValue = deviceID
         let status = AudioObjectSetPropertyData(
             AudioObjectID(kAudioObjectSystemObject),
             &address,
             0,
             nil,
             UInt32(MemoryLayout<AudioDeviceID>.size),
             &deviceIDValue
         )
         
         if status != noErr {
             logger.error("Failed to restore system default: status \(status)")
             return false
         }
         
         logger.info("Restored system default output to device with UID: \(uid)")
         return true
     }

    // MARK: - EQ Control

    // MARK: Per-Band Updates

    /// Updates the gain for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - gain: The gain value in dB.
    func updateBandGain(index: Int, gain: Float) {
        eqConfiguration.updateBandGain(index: index, gain: gain)
        renderPipeline?.updateBandGain(index: index)
        presetManager.markAsModified()
    }

    /// Updates the bandwidth for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - bandwidth: The bandwidth in octaves.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        eqConfiguration.updateBandBandwidth(index: index, bandwidth: bandwidth)
        renderPipeline?.updateBandBandwidth(index: index)
        presetManager.markAsModified()
    }

    /// Updates the frequency for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - frequency: The center frequency in Hz.
    func updateBandFrequency(index: Int, frequency: Float) {
        eqConfiguration.updateBandFrequency(index: index, frequency: frequency)
        renderPipeline?.updateBandFrequency(index: index)
        presetManager.markAsModified()
    }

    /// Updates the filter type for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - filterType: The filter type to apply.
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        eqConfiguration.updateBandFilterType(index: index, filterType: filterType)
        renderPipeline?.updateBandFilterType(index: index)
        presetManager.markAsModified()
    }

    /// Updates the bypass state for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - bypass: Whether the band should be bypassed.
    func updateBandBypass(index: Int, bypass: Bool) {
        eqConfiguration.updateBandBypass(index: index, bypass: bypass)
        renderPipeline?.updateBandBypass(index: index)
        presetManager.markAsModified()
    }

    // MARK: Global Updates

    /// Updates the band count and marks the preset as modified.
    /// Use this method when the user changes band count via UI.
    func updateBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        bandCount = clamped
        presetManager.markAsModified()
    }

    /// Updates the input gain and marks the preset as modified.
    /// Use this method when the user changes input gain via UI.
    func updateInputGain(_ gain: Float) {
        inputGain = gain
        presetManager.markAsModified()
    }

    /// Updates the output gain and marks the preset as modified.
    /// Use this method when the user changes output gain via UI.
    func updateOutputGain(_ gain: Float) {
        outputGain = gain
        presetManager.markAsModified()
    }

    /// Sets the window reference for visibility checking.
    /// Call this when the EQ window is created or becomes key.
    func setEqualiserWindow(_ window: NSWindow?) {
        equaliserWindow = window
        meterStore.setEqualiserWindow(window)
    }

    private func startCompareModeRevertTimer() {
        compareModeRevertTimer?.cancel()
        compareModeRevertTimer = Timer.publish(every: Self.compareModeRevertInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.compareMode = .eq
                self?.compareModeRevertTimer?.cancel()
                self?.compareModeRevertTimer = nil
            }
    }

    private func cancelCompareModeRevertTimer() {
        compareModeRevertTimer?.cancel()
        compareModeRevertTimer = nil
    }

    static func clampGain(_ gain: Float) -> Float {
        min(max(gain, gainRange.lowerBound), gainRange.upperBound)
    }

    private static func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }

    // MARK: - Preset Management

    /// Saves the current EQ settings as a new preset.
    ///
    /// - Parameter name: The name for the preset.
    /// - Returns: The created preset.
    @discardableResult
    func saveCurrentAsPreset(named name: String) throws -> Preset {
        let preset = try presetManager.createPreset(
            named: name,
            from: eqConfiguration,
            inputGain: inputGain,
            outputGain: outputGain
        )
        presetManager.selectPreset(named: name)
        return preset
    }

    /// Updates the currently selected preset with current EQ settings.
    func updateCurrentPreset() throws {
        guard let currentName = presetManager.selectedPresetName else { return }
        try saveCurrentAsPreset(named: currentName)
    }

    /// Loads a preset and applies it to the EQ configuration.
    ///
    /// - Parameter preset: The preset to load.
    func loadPreset(_ preset: Preset) {
        // Apply settings to EQ configuration
        presetManager.applyPreset(preset, to: eqConfiguration)

        // Apply input/output gains
        inputGain = preset.settings.inputGain
        outputGain = preset.settings.outputGain
        isBypassed = preset.settings.globalBypass
        bandCount = preset.settings.activeBandCount

        // Reapply to audio engine if active
        renderPipeline?.reapplyConfiguration()

        // Mark as selected (not modified since we just loaded it)
        presetManager.selectPreset(named: preset.metadata.name)
    }

    /// Loads a preset by name.
    ///
    /// - Parameter name: The name of the preset to load.
    func loadPreset(named name: String) {
        guard let preset = presetManager.preset(named: name) else {
            logger.warning("Preset not found: \(name)")
            return
        }
        loadPreset(preset)
    }

    /// Flattens all band gains to 0 dB while preserving current band configuration.
    func flattenBands() {
        // Reset all bands to flat
        for i in 0..<eqConfiguration.activeBandCount {
            eqConfiguration.updateBandGain(index: i, gain: 0)
        }

        // Reset gains
        inputGain = 0
        outputGain = 0
        isBypassed = false

        // Reapply to audio engine if active
        renderPipeline?.reapplyConfiguration()

        // Mark preset as modified
        presetManager.markAsModified()
    }

    /// Creates a new preset with 10 bands spread across the frequency spectrum.
    func createNewPreset() {
        // Always reset to 10 bands with proper frequency spreading
        bandCount = 10
        _ = eqConfiguration.setActiveBandCount(10, preserveConfiguredBands: false)

        // Force frequency reset regardless of current band count
        // (setActiveBandCount short-circuits if count hasn't changed)
        eqConfiguration.resetBandsWithFrequencySpread()

        // Reset gains
        inputGain = 0
        outputGain = 0
        isBypassed = false

        // Reapply to audio engine
        renderPipeline?.reapplyConfiguration()

        // Clear preset selection (this is a new unsaved preset)
        presetManager.selectPreset(named: nil)
    }
}
