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
            if selectedInputDeviceID != oldValue {
                reconfigureRouting()
            }
        }
    }

    @Published var selectedOutputDeviceID: String? {
        didSet {
            if selectedOutputDeviceID != oldValue {
                reconfigureRouting()
            }
        }
    }

    @Published private(set) var routingStatus: RoutingStatus = .idle

    /// User preference for displaying bandwidth as octaves or Q factor.
    @Published var bandwidthDisplayMode: BandwidthDisplayMode = .octaves

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
            inputDeviceID: selectedInputDeviceID,
            outputDeviceID: selectedOutputDeviceID,
            bandwidthDisplayMode: bandwidthDisplayMode.rawValue,
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
            _selectedInputDeviceID = Published(initialValue: snapshot.inputDeviceID)
            _selectedOutputDeviceID = Published(initialValue: snapshot.outputDeviceID)
            _bandwidthDisplayMode = Published(initialValue: BandwidthDisplayMode(rawValue: snapshot.bandwidthDisplayMode) ?? .octaves)
        } else {
            // First launch: apply smart defaults
            if let blackHole = deviceManager.findBlackHoleDevice() {
                _selectedInputDeviceID = Published(initialValue: blackHole.uid)
                logger.info("First launch: Auto-selected BlackHole as input device")
            }
            if let defaultOutput = deviceManager.defaultOutputDevice() {
                _selectedOutputDeviceID = Published(initialValue: defaultOutput.uid)
                logger.info("First launch: Auto-selected default output device: \(defaultOutput.name)")
            }
        }

        // Auto-start routing if both devices are already selected
        if selectedInputDeviceID != nil && selectedOutputDeviceID != nil {
            // Defer to next run loop to allow UI to initialize
            Task { @MainActor in
                self.reconfigureRouting()
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

    // MARK: - Routing Control

    /// Reconfigures the audio routing pipeline based on current device selections.
    /// Stops any existing routing and starts a new pipeline if both devices are selected.
    func reconfigureRouting() {
        // Stop existing pipeline if running
        if let pipeline = renderPipeline {
            logger.info("Stopping existing render pipeline")
            meterStore.stopMeterUpdates()
            meterStore.setRenderPipeline(nil)
            _ = pipeline.stop()
            renderPipeline = nil
        }

        // Check if both devices are selected
        guard let inputUID = selectedInputDeviceID,
              let outputUID = selectedOutputDeviceID else {
            routingStatus = .idle
            logger.debug("Routing idle: missing device selection")
            return
        }

        // Resolve UIDs to device IDs
        guard let inputDeviceID = deviceManager.deviceID(forUID: inputUID) else {
            routingStatus = .error("Input device not found")
            logger.error("Input device UID not found: \(inputUID)")
            return
        }

        guard let outputDeviceID = deviceManager.deviceID(forUID: outputUID) else {
            routingStatus = .error("Output device not found")
            logger.error("Output device UID not found: \(outputUID)")
            return
        }

        // Get device names for status display
        let inputName = deviceManager.device(forUID: inputUID)?.name ?? "Unknown"
        let outputName = deviceManager.device(forUID: outputUID)?.name ?? "Unknown"

        routingStatus = .starting
        logger.info("Starting routing: \(inputName) → \(outputName)")

        // Create the render pipeline with EQ configuration
        // The pipeline will create its own HAL managers internally (one for input, one for output)
        let pipeline = RenderPipeline(eqConfiguration: eqConfiguration)

        // Configure the pipeline with the selected devices
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
            routingStatus = .active(inputName: inputName, outputName: outputName)
            logger.info("Routing active: \(inputName) → \(outputName)")
            meterStore.setRenderPipeline(pipeline)
            meterStore.startMeterUpdates()
        case .failure(let error):
            routingStatus = .error("Start failed: \(error.localizedDescription)")
            logger.error("Pipeline start failed: \(error.localizedDescription)")
        }
    }

    /// Stops the current audio routing.

    func stopRouting() {
        if let pipeline = renderPipeline {
            meterStore.stopMeterUpdates()
            meterStore.setRenderPipeline(nil)
            _ = pipeline.stop()
            renderPipeline = nil
        }
        cancelCompareModeRevertTimer()
        routingStatus = .idle
        logger.info("Routing stopped")
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
