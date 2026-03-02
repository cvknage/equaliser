import AVFoundation
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

struct ChannelMeterState: Equatable {
    var peak: Float
    var peakHold: Float
    var peakHoldTimeRemaining: TimeInterval
    var clipHold: TimeInterval
    var rms: Float

    var isClipping: Bool { clipHold > 0 }

    static let silent = ChannelMeterState(peak: 0, peakHold: 0, peakHoldTimeRemaining: 0, clipHold: 0, rms: 0)
}

struct StereoMeterState: Equatable {
    var left: ChannelMeterState
    var right: ChannelMeterState

    static let silent = StereoMeterState(left: .silent, right: .silent)
}

/// Shared constants for meter visualization.
enum MeterConstants {
    static let meterRange: ClosedRange<Float> = -36...0
    static let gamma: Float = 0.5
    static let meterHeight: CGFloat = 126
    static let standardTickValues: [Float] = [0, -6, -12, -18, -24, -30, -36]

    /// Converts a dB value to a normalized position (0-1) matching the meter visual.
    static func normalizedPosition(for db: Float) -> Float {
        if db <= meterRange.lowerBound { return 0 }
        if db >= meterRange.upperBound { return 1 }
        let amp = powf(10.0, 0.05 * db)
        let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
        let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
        let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
        return powf(normalizedAmp, gamma)
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

    @Published var inputGain: Float = 0 {
        didSet {
            let clamped = EqualizerStore.clampGain(inputGain)
            if clamped != inputGain {
                inputGain = clamped
                return
            }
            persist()
            eqConfiguration.inputGain = inputGain
            renderPipeline?.updateInputGain(linear: EqualizerStore.dbToLinear(inputGain))
        }
    }

    @Published var outputGain: Float = 0 {
        didSet {
            let clamped = EqualizerStore.clampGain(outputGain)
            if clamped != outputGain {
                outputGain = clamped
                return
            }
            persist()
            eqConfiguration.outputGain = outputGain
            renderPipeline?.updateOutputGain(linear: EqualizerStore.dbToLinear(outputGain))
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
    @Published var inputMeterLevel: StereoMeterState = .silent
    @Published var outputMeterLevel: StereoMeterState = .silent
    @Published var inputMeterRMS: StereoMeterState = .silent
    @Published var outputMeterRMS: StereoMeterState = .silent

    // MARK: - Audio Components

    /// Device manager for enumerating audio devices.
    let deviceManager = DeviceManager()

    /// EQ configuration storage (no audio engine side effects).
    let eqConfiguration: EQConfiguration

    /// The render pipeline connecting HAL to AVAudioEngine.
    /// Owns the HALIOManager and ManualRenderingEngine internally.
    private var renderPipeline: RenderPipeline?

    private static let meterInterval: TimeInterval = 1.0 / 30.0
    private static let peakHoldHoldDuration: TimeInterval = 1.0
    private static let peakHoldDecayPerTick: Float = 0.02
    private static let peakAttackSmoothing: Float = 0.8
    private static let peakReleaseSmoothing: Float = 0.33
    private static let rmsSmoothing: Float = 0.12
    private static let clipHoldDuration: TimeInterval = 0.5
    private static let meterRange: ClosedRange<Float> = Float(-36)...Float(0)
    private static let gainRange: ClosedRange<Float> = -24...24
    private static let gamma: Float = 0.5

    // MARK: - Private Properties

    private let storage: UserDefaults
    private let logger = Logger(subsystem: "com.example.EqualizerApp", category: "EqualizerStore")
    private var cancellables = Set<AnyCancellable>()
    private var meterTimer: AnyCancellable?

    private enum Keys {
        static let bypass = "equalizer.bypass"
        static let inputDevice = "equalizer.input"
        static let outputDevice = "equalizer.output"
        static let bandCount = "equalizer.bandCount"
        static let inputGain = "equalizer.inputGain"
        static let outputGain = "equalizer.outputGain"
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

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        self.eqConfiguration = EQConfiguration(storage: storage)

        // Restore persisted state (no audio engine is created here)
        let storedBypass = storage.bool(forKey: Keys.bypass)
        let storedInput = storage.string(forKey: Keys.inputDevice)
        let storedOutput = storage.string(forKey: Keys.outputDevice)
        let storedBands = storage.object(forKey: Keys.bandCount) as? Int ?? eqConfiguration.activeBandCount
        let storedInputGain = EqualizerStore.clampGain(storage.float(forKey: Keys.inputGain))
        let storedOutputGain = EqualizerStore.clampGain(storage.float(forKey: Keys.outputGain))

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
            meterTimer?.cancel()
            meterTimer = nil
            _ = pipeline.stop()
            renderPipeline = nil
            inputMeterLevel = .silent
            outputMeterLevel = .silent
            inputMeterRMS = .silent
            outputMeterRMS = .silent
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
            renderPipeline?.updateInputGain(linear: EqualizerStore.dbToLinear(inputGain))
            renderPipeline?.updateOutputGain(linear: EqualizerStore.dbToLinear(outputGain))
            routingStatus = .active(inputName: inputName, outputName: outputName)
            logger.info("Routing active: \(inputName) → \(outputName)")
            startMeterUpdates()
        case .failure(let error):
            routingStatus = .error("Start failed: \(error.localizedDescription)")
            logger.error("Pipeline start failed: \(error.localizedDescription)")
        }
    }

    /// Stops the current audio routing.

    func stopRouting() {
        if let pipeline = renderPipeline {
            meterTimer?.cancel()
            meterTimer = nil
            _ = pipeline.stop()
            renderPipeline = nil
        }
        inputMeterLevel = .silent
        outputMeterLevel = .silent
        inputMeterRMS = .silent
        outputMeterRMS = .silent
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

    private func startMeterUpdates() {
        meterTimer?.cancel()
        guard renderPipeline != nil else { return }

        meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMeterSnapshot()
            }
    }

    private func refreshMeterSnapshot() {
        guard let pipeline = renderPipeline else { return }
        let snapshot = pipeline.currentMeters()
        inputMeterLevel = meterState(from: snapshot.inputDB, previous: inputMeterLevel)
        outputMeterLevel = meterState(from: snapshot.outputDB, previous: outputMeterLevel)
        inputMeterRMS = rmsState(from: snapshot.inputRmsDB, previous: inputMeterRMS)
        outputMeterRMS = rmsState(from: snapshot.outputRmsDB, previous: outputMeterRMS)
    }

    private func rmsState(from dbValues: [Float], previous: StereoMeterState) -> StereoMeterState {
        let left = channelRMSState(from: dbValues, channelIndex: 0, previous: previous.left)
        let right = channelRMSState(from: dbValues, channelIndex: 1, previous: previous.right)
        return StereoMeterState(left: left, right: right)
    }

    private func channelRMSState(from dbValues: [Float], channelIndex: Int, previous: ChannelMeterState) -> ChannelMeterState {
        let db = dbValues.indices.contains(channelIndex) ? dbValues[channelIndex] : Self.meterRange.lowerBound
        let normalized = EqualizerStore.normalize(db: db)
        let delta = normalized - previous.rms
        let rawRMS = previous.rms + delta * Self.rmsSmoothing
        let rms = max(0, min(1, rawRMS))

        return ChannelMeterState(
            peak: previous.peak,
            peakHold: previous.peakHold,
            peakHoldTimeRemaining: previous.peakHoldTimeRemaining,
            clipHold: previous.clipHold,
            rms: rms
        )
    }

    private func meterState(from dbValues: [Float], previous: StereoMeterState) -> StereoMeterState {
        let left = channelState(from: dbValues, channelIndex: 0, previous: previous.left)
        let right = channelState(from: dbValues, channelIndex: 1, previous: previous.right)
        return StereoMeterState(left: left, right: right)
    }

    static func clampGain(_ gain: Float) -> Float {
        min(max(gain, gainRange.lowerBound), gainRange.upperBound)
    }

    private static func dbToLinear(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }

    private func channelState(from dbValues: [Float], channelIndex: Int, previous: ChannelMeterState) -> ChannelMeterState {
        let db = dbValues.indices.contains(channelIndex) ? dbValues[channelIndex] : Self.meterRange.lowerBound
        let normalized = EqualizerStore.normalize(db: db)
        let delta = normalized - previous.peak
        let smoothing = delta >= 0 ? Self.peakAttackSmoothing : Self.peakReleaseSmoothing
        let rawPeak = previous.peak + delta * smoothing
        let peak = max(0, min(1, rawPeak))

        // When clipping occurs, use the actual normalized value (1.0) for peak hold
        // rather than the smoothed peak, so the white line shows the true maximum
        let isClipping = db >= 0
        let actualPeakForHold = isClipping ? normalized : peak
        let isNewPeak = actualPeakForHold > previous.peakHold
        let newHoldTime: TimeInterval
        let peakHold: Float
        if isNewPeak {
            newHoldTime = Self.peakHoldHoldDuration
            peakHold = actualPeakForHold
        } else if previous.peakHoldTimeRemaining > 0 {
            newHoldTime = max(0, previous.peakHoldTimeRemaining - Self.meterInterval)
            peakHold = previous.peakHold
        } else {
            newHoldTime = 0
            let rawPeakHold = max(previous.peakHold - Self.peakHoldDecayPerTick, peak)
            peakHold = max(0, min(1, rawPeakHold))
        }

        let clipHold = isClipping ? Self.clipHoldDuration : max(0, previous.clipHold - Self.meterInterval)
        return ChannelMeterState(peak: peak, peakHold: peakHold, peakHoldTimeRemaining: newHoldTime, clipHold: clipHold, rms: previous.rms)
    }

    private static func normalize(db: Float) -> Float {
        if db <= meterRange.lowerBound {
            return 0
        }
        if db >= meterRange.upperBound {
            return 1
        }
        let amp = powf(10.0, 0.05 * db)
        let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
        let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
        let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
        return powf(normalizedAmp, gamma)
    }
}
