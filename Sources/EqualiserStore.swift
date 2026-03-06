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
    // MARK: - Published Properties

    @Published var isBypassed: Bool = false {
        didSet {
            persist()
            eqConfiguration.globalBypass = isBypassed
            renderPipeline?.updateProcessingMode(systemEQOff: isBypassed, compareMode: compareMode)
        }
    }

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

    @Published var bandCount: Int = EQConfiguration.defaultBandCount {
        didSet {
            let clamped = eqConfiguration.setActiveBandCount(bandCount)
            if clamped != bandCount {
                bandCount = clamped
                return
            }
            persist()
            reconfigureRouting()
        }
    }

    @Published var inputGain: Float = 0 {
        didSet {
            let clamped = EqualiserStore.clampGain(inputGain)
            if clamped != inputGain {
                inputGain = clamped
                return
            }
            persist()
            eqConfiguration.inputGain = inputGain
            renderPipeline?.updateInputGain(linear: EqualiserStore.dbToLinear(inputGain))
        }
    }

    @Published var outputGain: Float = 0 {
        didSet {
            let clamped = EqualiserStore.clampGain(outputGain)
            if clamped != outputGain {
                outputGain = clamped
                return
            }
            persist()
            eqConfiguration.outputGain = outputGain
            renderPipeline?.updateOutputGain(linear: EqualiserStore.dbToLinear(outputGain))
        }
    }

    @Published var selectedInputDeviceID: String? {
        didSet {
            persist()
            if selectedInputDeviceID != oldValue {
                reconfigureRouting()
            }
        }
    }

    @Published var selectedOutputDeviceID: String? {
        didSet {
            persist()
            if selectedOutputDeviceID != oldValue {
                reconfigureRouting()
            }
        }
    }

    @Published private(set) var routingStatus: RoutingStatus = .idle

    var metersEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.meterStore.metersEnabled },
            set: { self.meterStore.metersEnabled = $0 }
        )
    }

    /// User preference for displaying bandwidth as octaves or Q factor.
    @Published var bandwidthDisplayMode: BandwidthDisplayMode = .octaves {
        didSet {
            storage.set(bandwidthDisplayMode.rawValue, forKey: Keys.bandwidthDisplayMode)
        }
    }

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

    private enum Keys {
        static let bypass = "equalizer.bypass"
        static let inputDevice = "equalizer.input"
        static let outputDevice = "equalizer.output"
        static let bandCount = "equalizer.bandCount"
        static let inputGain = "equalizer.inputGain"
        static let outputGain = "equalizer.outputGain"
        static let bandwidthDisplayMode = "equalizer.bandwidthDisplayMode"
    }

    private let storage: UserDefaults
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "EqualiserStore")
    private var cancellables = Set<AnyCancellable>()
    private static let gainRange: ClosedRange<Float> = -24...24

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

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        self.eqConfiguration = EQConfiguration(storage: storage)
        self.presetManager = PresetManager(storage: storage)
        self.meterStore = MeterStore(storage: storage)

        // Restore persisted state (no audio engine is created here)
        let storedBypass = storage.bool(forKey: Keys.bypass)
        let storedInput = storage.string(forKey: Keys.inputDevice)
        let storedOutput = storage.string(forKey: Keys.outputDevice)
        let storedBands = storage.object(forKey: Keys.bandCount) as? Int ?? eqConfiguration.activeBandCount
        let storedInputGain = EqualiserStore.clampGain(storage.float(forKey: Keys.inputGain))
        let storedOutputGain = EqualiserStore.clampGain(storage.float(forKey: Keys.outputGain))
        let storedBandwidthMode = storage.string(forKey: Keys.bandwidthDisplayMode)
            .flatMap { BandwidthDisplayMode(rawValue: $0) } ?? .octaves

        // Apply to EQ configuration first
        eqConfiguration.globalBypass = storedBypass
        eqConfiguration.setActiveBandCount(storedBands)
        eqConfiguration.inputGain = storedInputGain
        eqConfiguration.outputGain = storedOutputGain
        storage.set(eqConfiguration.activeBandCount, forKey: Keys.bandCount)

        // Then set published properties (without triggering didSet side effects)
        _isBypassed = Published(initialValue: storedBypass)
        _bandCount = Published(initialValue: eqConfiguration.activeBandCount)
        _inputGain = Published(initialValue: storedInputGain)
        _outputGain = Published(initialValue: storedOutputGain)
        _selectedInputDeviceID = Published(initialValue: storedInput)
        _selectedOutputDeviceID = Published(initialValue: storedOutput)
        _bandwidthDisplayMode = Published(initialValue: storedBandwidthMode)

        // Auto-start routing if both devices are already selected
        if storedInput != nil && storedOutput != nil {
            // Defer to next run loop to allow UI to initialize
            Task { @MainActor in
                self.reconfigureRouting()
            }
        }

        eqConfiguration.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.presetManager.markAsModified()
            }
            .store(in: &cancellables)

        presetManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        bandCount = eqConfiguration.activeBandCount
    }

    // MARK: - Persistence

    private func persist() {
        storage.set(isBypassed, forKey: Keys.bypass)
        storage.set(selectedInputDeviceID, forKey: Keys.inputDevice)
        storage.set(selectedOutputDeviceID, forKey: Keys.outputDevice)
        storage.set(bandCount, forKey: Keys.bandCount)
        storage.set(inputGain, forKey: Keys.inputGain)
        storage.set(outputGain, forKey: Keys.outputGain)
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

    /// Updates the gain for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - gain: The gain value in dB.
    func updateBandGain(index: Int, gain: Float) {
        eqConfiguration.updateBandGain(index: index, gain: gain)
        renderPipeline?.updateBandGain(index: index)
    }

    /// Updates the bandwidth for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - bandwidth: The bandwidth in octaves.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        eqConfiguration.updateBandBandwidth(index: index, bandwidth: bandwidth)
        renderPipeline?.updateBandBandwidth(index: index)
    }

    /// Updates the frequency for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - frequency: The center frequency in Hz.
    func updateBandFrequency(index: Int, frequency: Float) {
        eqConfiguration.updateBandFrequency(index: index, frequency: frequency)
        renderPipeline?.updateBandFrequency(index: index)
    }

    /// Updates the filter type for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - filterType: The filter type to apply.
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        eqConfiguration.updateBandFilterType(index: index, filterType: filterType)
        renderPipeline?.updateBandFilterType(index: index)
    }

    /// Updates the bypass state for a specific EQ band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - bypass: Whether the band should be bypassed.
    func updateBandBypass(index: Int, bypass: Bool) {
        eqConfiguration.updateBandBypass(index: index, bypass: bypass)
        renderPipeline?.updateBandBypass(index: index)
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

    /// Resets to default EQ settings (flat response).
    func resetToDefaults() {
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

        // Clear preset selection
        presetManager.selectPreset(named: nil)
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
