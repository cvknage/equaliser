// EqualiserStore.swift
// Thin coordinator for EQ application state

import AVFoundation
import Combine
import Foundation
import OSLog
import AppKit
import SwiftUI

/// Compare mode for EQ vs Flat comparison.
enum CompareMode: Int, Codable, Sendable {
    case eq = 0
    case flat = 1
}

@MainActor
final class EqualiserStore: ObservableObject {
    
    // MARK: - Computed Properties (delegate to EQConfiguration)
    
    /// Global bypass state - delegates to eqConfiguration.globalBypass.
    var isBypassed: Bool {
        get { eqConfiguration.globalBypass }
        set {
            eqConfiguration.globalBypass = newValue
            routingCoordinator.updateProcessingMode(systemEQOff: newValue, compareMode: compareMode)
        }
    }
    
    /// Band count - delegates to eqConfiguration.activeBandCount.
    var bandCount: Int {
        get { eqConfiguration.activeBandCount }
        set {
            eqConfiguration.setActiveBandCount(newValue)

            // Only update pipeline if routing is active
            guard routingCoordinator.routingStatus.isActive else { return }

            // Reconfigure only if new band count exceeds current capacity
            if newValue > routingCoordinator.currentBandCapacity() {
                routingCoordinator.reconfigureRouting()
            } else {
                routingCoordinator.reapplyConfiguration()
            }
        }
    }
    
    /// Input gain (dB) - delegates to eqConfiguration.inputGain.
    var inputGain: Float {
        get { eqConfiguration.inputGain }
        set {
            let clamped = Self.clampGain(newValue)
        eqConfiguration.inputGain = clamped
        routingCoordinator.updateInputGain(linear: AudioMath.dbToLinear(clamped))
        }
    }
    
    /// Output gain (dB) - delegates to eqConfiguration.outputGain.
    var outputGain: Float {
        get { eqConfiguration.outputGain }
        set {
            let clamped = Self.clampGain(newValue)
        eqConfiguration.outputGain = clamped
        routingCoordinator.updateOutputGain(linear: AudioMath.dbToLinear(clamped))
        }
    }
    
    // MARK: - Published Properties
    
    @Published var compareMode: CompareMode = .eq {
        didSet {
            routingCoordinator.updateProcessingMode(systemEQOff: isBypassed, compareMode: compareMode)
            
            if compareMode == .flat {
                compareModeTimer.start()
            } else {
                compareModeTimer.cancel()
            }
        }
    }
    
    /// User preference for displaying bandwidth as octaves or Q factor.
    @Published var bandwidthDisplayMode: BandwidthDisplayMode = .octaves
    
    // MARK: - Forwarded Properties from RoutingCoordinator
    
    var routingStatus: RoutingStatus { routingCoordinator.routingStatus }
    
    var selectedInputDeviceID: String? {
        get { routingCoordinator.selectedInputDeviceID }
        set {
            routingCoordinator.selectedInputDeviceID = newValue
            if newValue != nil && routingCoordinator.selectedOutputDeviceID != nil {
                routingCoordinator.reconfigureRouting()
            }
        }
    }
    
    var selectedOutputDeviceID: String? {
        get { routingCoordinator.selectedOutputDeviceID }
        set {
            routingCoordinator.selectedOutputDeviceID = newValue
            if routingCoordinator.selectedInputDeviceID != nil && newValue != nil {
                routingCoordinator.reconfigureRouting()
            }
        }
    }
    
    var manualModeEnabled: Bool {
        get { routingCoordinator.manualModeEnabled }
        set { routingCoordinator.manualModeEnabled = newValue }
    }
    
    var showDriverPrompt: Bool {
        get { routingCoordinator.showDriverPrompt }
        set { routingCoordinator.showDriverPrompt = newValue }
    }
    
    var inputDevices: [AudioDevice] { deviceManager.inputDevices }
    var outputDevices: [AudioDevice] { deviceManager.outputDevices }
    
    // MARK: - Components
    
    let deviceManager = DeviceManager()
    let volumeService: VolumeControlling
    let sampleRateService: SampleRateObserving
    let eqConfiguration: EQConfiguration
    let presetManager: PresetManager
    let meterStore: MeterStore

    // MARK: - Coordinators
    
    private(set) var deviceChangeCoordinator: DeviceChangeCoordinator
    private(set) var routingCoordinator: AudioRoutingCoordinator
    private let systemDefaultObserver: SystemDefaultObserver
    private let compareModeTimer = CompareModeTimer()
    
    // MARK: - Private Properties
    
    let persistence: AppStatePersistence
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "EqualiserStore")
    private var cancellables = Set<AnyCancellable>()
    public static let gainRange: ClosedRange<Float> = -36...36
    
    // MARK: - Snapshot
    
    var currentSnapshot: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: eqConfiguration.globalBypass,
            inputGain: eqConfiguration.inputGain,
            outputGain: eqConfiguration.outputGain,
            activeBandCount: eqConfiguration.activeBandCount,
            bands: eqConfiguration.bands,
            inputDeviceID: manualModeEnabled ? routingCoordinator.selectedInputDeviceID : nil,
            outputDeviceID: routingCoordinator.selectedOutputDeviceID,
            bandwidthDisplayMode: bandwidthDisplayMode.rawValue,
            manualModeEnabled: manualModeEnabled,
            metersEnabled: meterStore.metersEnabled
        )
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
        
        // Create services
        self.volumeService = DeviceVolumeService()
        self.sampleRateService = DeviceSampleRateService()
        
        // Create coordinators
        self.systemDefaultObserver = SystemDefaultObserver(deviceManager: deviceManager)
        self.deviceChangeCoordinator = DeviceChangeCoordinator(
            deviceEnumerator: deviceManager.enumerator
        )
        self.routingCoordinator = AudioRoutingCoordinator(
            deviceManager: deviceManager,
            deviceChangeCoordinator: deviceChangeCoordinator,
            eqConfiguration: eqConfiguration,
            meterStore: meterStore,
            volumeService: volumeService,
            systemDefaultObserver: systemDefaultObserver,
            sampleRateService: sampleRateService
        )
        
        // Log macOS system default output
        if let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID() {
            if let device = deviceManager.device(forUID: macDefault) {
                logger.info("EqualiserStore.init: macOS default output: '\(device.name)' (uid=\(macDefault))")
            } else {
                logger.info("EqualiserStore.init: macOS default output uid=\(macDefault) (device not in list)")
            }
        } else {
            logger.warning("EqualiserStore.init: No macOS default output device found")
        }
        
        // Wire up callbacks
        compareModeTimer.onRevert = { [weak self] in
            self?.compareMode = .eq
        }
        
        persistence.setStore(self)
        
        // Restore app-level state
        if let snapshot = snapshot {
            logger.debug("Loading from snapshot: outputDeviceID=\(snapshot.outputDeviceID ?? "nil"), manualMode=\(snapshot.manualModeEnabled)")
            _bandwidthDisplayMode = Published(initialValue: BandwidthDisplayMode(rawValue: snapshot.bandwidthDisplayMode) ?? .octaves)
            
            if snapshot.manualModeEnabled {
                // Manual mode: load saved devices
                routingCoordinator.selectedInputDeviceID = snapshot.inputDeviceID
                routingCoordinator.selectedOutputDeviceID = snapshot.outputDeviceID
                routingCoordinator.manualModeEnabled = true
                logger.debug("Manual mode: loaded saved devices")
            } else {
                // Automatic mode: use unified selection logic
                routingCoordinator.manualModeEnabled = false
                
                let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID()
                let selection = OutputDeviceSelection.determine(
                    currentSelected: snapshot.outputDeviceID,
                    macDefault: macDefault,
                    availableDevices: deviceManager.outputDevices
                )
                
                switch selection {
                case .preserveCurrent(let uid):
                    routingCoordinator.selectedOutputDeviceID = uid
                    logger.debug("Startup: preserving saved output device")
                    
                case .useMacDefault(let uid):
                    routingCoordinator.selectedOutputDeviceID = uid
                    if let device = deviceManager.device(forUID: uid) {
                        logger.debug("Startup: using macOS default '\(device.name)'")
                    }
                    
                case .useFallback:
                    if let fallback = deviceManager.selectFallbackOutputDevice() {
                        routingCoordinator.selectedOutputDeviceID = fallback.uid
                        logger.info("Startup: using fallback output '\(fallback.name)'")
                    } else {
                        logger.error("Startup: no output device available")
                    }
                }
                
                // Input is always driver in automatic mode
                routingCoordinator.selectedInputDeviceID = DRIVER_DEVICE_UID
            }
        } else {
            // First launch: automatic mode, use unified selection logic
            logger.info("First launch, no snapshot")
            routingCoordinator.manualModeEnabled = false
            
            let macDefault = systemDefaultObserver.getCurrentSystemDefaultOutputUID()
            let selection = OutputDeviceSelection.determine(
                currentSelected: nil,
                macDefault: macDefault,
                availableDevices: deviceManager.outputDevices
            )
            
            switch selection {
            case .preserveCurrent:
                // Not possible with nil currentSelected
                break
                
            case .useMacDefault(let uid):
                routingCoordinator.selectedOutputDeviceID = uid
                if let device = deviceManager.device(forUID: uid) {
                    logger.debug("Startup: using macOS default '\(device.name)'")
                }
                
            case .useFallback:
                if let fallback = deviceManager.selectFallbackOutputDevice() {
                    routingCoordinator.selectedOutputDeviceID = fallback.uid
                    logger.info("Startup: using fallback output '\(fallback.name)'")
                } else {
                    logger.error("Startup: no output device available")
                }
            }
            
            // Input is always driver in automatic mode
            routingCoordinator.selectedInputDeviceID = DRIVER_DEVICE_UID
        }
        
        // Start observing system default changes
        systemDefaultObserver.startObserving()
        
        // Check if driver prompt should be shown (automatic mode without driver)
        // Defer to next run loop so onChange can observe the transition
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // Forward driver prompt state from routing coordinator
            routingCoordinator.$showDriverPrompt
                .receive(on: DispatchQueue.main)
                .sink { [weak self] showPrompt in
                    guard let self else { return }
                    if showPrompt && !self.routingCoordinator.manualModeEnabled && !DriverManager.shared.isReady {
                        self.logger.info("Automatic mode but driver not installed - showing prompt")
                    }
                }
                .store(in: &self.cancellables)
            
            if !routingCoordinator.manualModeEnabled && !DriverManager.shared.isReady {
                self.logger.info("Automatic mode but driver not installed - showing prompt")
                self.routingCoordinator.showDriverPrompt = true
                self.routingCoordinator.routingStatus = .driverNotInstalled
            } else {
                // Driver visibility is now automatic
                if routingCoordinator.selectedOutputDeviceID != nil {
                    // Auto-start routing if devices are selected
                    self.routingCoordinator.reconfigureRouting()
                }
            }
        }
        
        // Wire up EQ configuration changes
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
        
        // Forward routing coordinator changes
        routingCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward device manager changes (device list updates)
        deviceManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Listen for app termination
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle
    
    @objc private func handleAppWillTerminate() {
        logger.info("App terminating, stopping routing")
        routingCoordinator.stopRouting()
        // Driver visibility is now automatic
    }
    
    // MARK: - Routing Delegation
    
    func reconfigureRouting() {
        routingCoordinator.reconfigureRouting()
    }
    
    func stopRouting() {
        routingCoordinator.stopRouting()
    }
    
    func handleDriverInstalled() {
        routingCoordinator.handleDriverInstalled()
    }
    
    func switchToManualMode() {
        routingCoordinator.switchToManualMode()
    }
    
    func switchToAutomaticMode() {
        routingCoordinator.switchToAutomaticMode()
    }
    
    // MARK: - EQ Control
    
    /// Updates the gain for a specific EQ band.
    func updateBandGain(index: Int, gain: Float) {
        eqConfiguration.updateBandGain(index: index, gain: gain)
        routingCoordinator.updateBandGain(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the bandwidth for a specific EQ band.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        eqConfiguration.updateBandBandwidth(index: index, bandwidth: bandwidth)
        routingCoordinator.updateBandBandwidth(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the frequency for a specific EQ band.
    func updateBandFrequency(index: Int, frequency: Float) {
        eqConfiguration.updateBandFrequency(index: index, frequency: frequency)
        routingCoordinator.updateBandFrequency(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the filter type for a specific EQ band.
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        eqConfiguration.updateBandFilterType(index: index, filterType: filterType)
        routingCoordinator.updateBandFilterType(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the bypass state for a specific EQ band.
    func updateBandBypass(index: Int, bypass: Bool) {
        eqConfiguration.updateBandBypass(index: index, bypass: bypass)
        routingCoordinator.updateBandBypass(index: index)
        presetManager.markAsModified()
    }
    
    /// Updates the band count and marks the preset as modified.
    func updateBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        bandCount = clamped
        presetManager.markAsModified()
    }
    
    /// Updates the input gain and marks the preset as modified.
    func updateInputGain(_ gain: Float) {
        inputGain = gain
        presetManager.markAsModified()
    }
    
    /// Updates the output gain and marks the preset as modified.
    func updateOutputGain(_ gain: Float) {
        outputGain = gain
        presetManager.markAsModified()
    }
    
    /// Sets the window reference for visibility checking.
    func setEqualiserWindow(_ window: NSWindow?) {
        meterStore.setEqualiserWindow(window)
    }
    
    // MARK: - Preset Management
    
    /// Saves the current EQ settings as a new preset.
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
    func loadPreset(_ preset: Preset) {
        // Apply settings to EQ configuration
        presetManager.applyPreset(preset, to: eqConfiguration)

        // Apply input/output gains
        inputGain = preset.settings.inputGain
        outputGain = preset.settings.outputGain
        isBypassed = preset.settings.globalBypass
        bandCount = preset.settings.activeBandCount  // Uses smart setter

        // Mark as selected (not modified since we just loaded it)
        presetManager.selectPreset(named: preset.metadata.name)
    }
    
    /// Loads a preset by name.
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
        routingCoordinator.reapplyConfiguration()
        
        // Mark preset as modified
        presetManager.markAsModified()
    }
    
    /// Creates a new preset with 10 bands spread across the frequency spectrum.
    func createNewPreset() {
        // Always reset to 10 bands with proper frequency spreading
        bandCount = 10
        _ = eqConfiguration.setActiveBandCount(10, preserveConfiguredBands: false)
        
        // Force frequency reset
        eqConfiguration.resetBandsWithFrequencySpread()
        
        // Reset gains
        inputGain = 0
        outputGain = 0
        isBypassed = false
        
        // Reapply to audio engine
        routingCoordinator.reapplyConfiguration()
        
        // Clear preset selection (this is a new unsaved preset)
        presetManager.selectPreset(named: nil)
    }
    
    // MARK: - Helpers
    
    static func clampGain(_ gain: Float) -> Float {
        min(max(gain, gainRange.lowerBound), gainRange.upperBound)
    }
}
