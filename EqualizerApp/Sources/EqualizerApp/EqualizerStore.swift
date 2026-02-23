import Combine
import Foundation
import os.log

/// Represents the current state of audio routing.
enum RoutingStatus: Equatable {
    case idle
    case starting
    case active(inputName: String, outputName: String)
    case error(String)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

@MainActor
final class EqualizerStore: ObservableObject {
    // MARK: - Published Properties

    @Published var isBypassed: Bool = false {
        didSet {
            persist()
            eqConfiguration.globalBypass = isBypassed
            renderPipeline?.updateBypass()
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

    // MARK: - Audio Components

    /// Device manager for enumerating audio devices.
    let deviceManager = DeviceManager()

    /// EQ configuration storage (no audio engine side effects).
    let eqConfiguration = EQConfiguration()

    /// The render pipeline connecting HAL to AVAudioEngine.
    /// Owns the HALIOManager and ManualRenderingEngine internally.
    private var renderPipeline: RenderPipeline?

    // MARK: - Private Properties

    private let storage = UserDefaults.standard
    private let logger = Logger(subsystem: "com.example.EqualizerApp", category: "EqualizerStore")
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let bypass = "equalizer.bypass"
        static let inputDevice = "equalizer.input"
        static let outputDevice = "equalizer.output"
        static let bandCount = "equalizer.bandCount"
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

    init() {
        // Restore persisted state (no audio engine is created here)
        let storedBypass = storage.bool(forKey: Keys.bypass)
        let storedInput = storage.string(forKey: Keys.inputDevice)
        let storedOutput = storage.string(forKey: Keys.outputDevice)
        let storedBands = storage.object(forKey: Keys.bandCount) as? Int ?? EQConfiguration.defaultBandCount

        // Apply to EQ configuration first
        eqConfiguration.globalBypass = storedBypass
        eqConfiguration.setActiveBandCount(storedBands)
        storage.set(eqConfiguration.activeBandCount, forKey: Keys.bandCount)

        // Then set published properties (without triggering didSet side effects)
        _isBypassed = Published(initialValue: storedBypass)
        _bandCount = Published(initialValue: eqConfiguration.activeBandCount)
        _selectedInputDeviceID = Published(initialValue: storedInput)
        _selectedOutputDeviceID = Published(initialValue: storedOutput)

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
    }

    // MARK: - Routing Control

    /// Reconfigures the audio routing pipeline based on current device selections.
    /// Stops any existing routing and starts a new pipeline if both devices are selected.
    func reconfigureRouting() {
        // Stop existing pipeline if running
        if let pipeline = renderPipeline {
            logger.info("Stopping existing render pipeline")
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
            routingStatus = .active(inputName: inputName, outputName: outputName)
            logger.info("Routing active: \(inputName) → \(outputName)")
        case .failure(let error):
            routingStatus = .error("Start failed: \(error.localizedDescription)")
            logger.error("Pipeline start failed: \(error.localizedDescription)")
        }
    }

    /// Stops the current audio routing.

    func stopRouting() {
        if let pipeline = renderPipeline {
            _ = pipeline.stop()
            renderPipeline = nil
        }
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
}
