import Foundation
import os.log

// MARK: - Channel Editing Target

/// Which channel to edit in stereo mode.
/// In linked mode, this is ignored (both channels edited together).
enum ChannelFocus: String, Codable, Sendable {
    case left
    case right
}

/// Configuration for a single EQ band.
///
/// Q (quality factor) is stored natively. Bandwidth in octaves is a display preference
/// that can be converted to/from Q using `BandwidthConverter`. Q is the value used
/// directly by the biquad coefficient calculations.
struct EQBandConfiguration: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case frequency
        case q
        case bandwidth  // Legacy: for backward compatibility with old presets
        case gain
        case filterType
        case bypass
    }

    init(frequency: Float, q: Float, gain: Float, filterType: FilterType, bypass: Bool) {
        self.frequency = frequency
        self.q = q
        self.gain = gain
        self.filterType = filterType
        self.bypass = bypass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(Float.self, forKey: .frequency)
        gain = try container.decode(Float.self, forKey: .gain)
        let filterTypeRaw = try container.decode(Int.self, forKey: .filterType)
        filterType = FilterType(validatedRawValue: filterTypeRaw) ?? .parametric
        bypass = try container.decode(Bool.self, forKey: .bypass)

        // New format: q field (preferred)
        // Legacy format: bandwidth field (convert to Q)
        if let q = try container.decodeIfPresent(Float.self, forKey: .q) {
            self.q = q
        } else if let bandwidth = try container.decodeIfPresent(Float.self, forKey: .bandwidth) {
            // Legacy: convert bandwidth (octaves) to Q
            self.q = BandwidthConverter.bandwidthToQ(bandwidth)
        } else {
            self.q = EQConfiguration.defaultQ
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(q, forKey: .q)
        try container.encode(gain, forKey: .gain)
        try container.encode(filterType.rawValue, forKey: .filterType)
        try container.encode(bypass, forKey: .bypass)
    }

    var frequency: Float
    var q: Float
    var gain: Float
    var filterType: FilterType
    var bypass: Bool

    /// Default parametric band configuration.
    static func parametric(frequency: Float, q: Float = EQConfiguration.defaultQ) -> EQBandConfiguration {
        EQBandConfiguration(
            frequency: frequency,
            q: q,
            gain: 0,
            filterType: .parametric,
            bypass: false
        )
    }
}

/// Stores EQ configuration independently of any AVAudioEngine instance.
/// This allows settings to be stored and modified without triggering
/// audio hardware initialization.
@MainActor
final class EQConfiguration: ObservableObject {
    // MARK: - Constants

    nonisolated static let maxBandCount: Int = 64
    nonisolated static let defaultBandCount: Int = 10
    /// Default Q factor for EQ bands (~1 octave bandwidth, industry standard).
    nonisolated static let defaultQ: Float = 1.41

    // MARK: - Private Properties

    private static let logger = Logger(subsystem: "net.knage.equaliser", category: "EQConfiguration")

    // MARK: - Published Properties

    /// Global bypass for all EQ bands.
    @Published var globalBypass: Bool = false

    /// Input gain applied before EQ processing (in dB).
    @Published var inputGain: Float = 0

    /// Output gain applied after EQ processing (in dB).
    @Published var outputGain: Float = 0

    /// Channel processing mode.
    /// - linked: Same EQ applied to both L and R (default)
    /// - stereo: Independent L and R EQ settings
    @Published var channelMode: ChannelMode = .linked

    /// Which channel is currently being edited in stereo mode.
    /// In linked mode, this is ignored.
    @Published var editingChannel: ChannelFocus = .left

    /// Current number of active bands exposed to the UI and audio engine.
    @Published private(set) var activeBandCount: Int

    /// Per-channel EQ state.
    /// Left channel state is used for linked mode.
    @Published private(set) var leftState: ChannelEQState
    @Published private(set) var rightState: ChannelEQState

    /// Configuration for all bands (always sized to `maxBandCount`).
    /// Returns bands for the currently edited channel:
    /// - In linked mode: left channel bands (both channels have same settings)
    /// - In stereo mode: bands for the channel being edited
    var bands: [EQBandConfiguration] {
        switch channelMode {
        case .linked:
            return leftState.userEQ.bands
        case .stereo:
            return editingChannel == .left
                ? leftState.userEQ.bands
                : rightState.userEQ.bands
        }
    }

    // MARK: - Initialization

    init(initialBandCount: Int = EQConfiguration.defaultBandCount) {
        leftState = ChannelEQState(layers: [.userEQ(bandCount: initialBandCount)])
        rightState = ChannelEQState(layers: [.userEQ(bandCount: initialBandCount)])
        activeBandCount = EQConfiguration.clampBandCount(initialBandCount)
    }

    convenience init(from snapshot: AppStateSnapshot) {
        // Snapshot decoding handles legacy migration, so we can use states directly
        let bandCount = snapshot.leftState.userEQ.activeBandCount

        self.init(initialBandCount: bandCount)
        globalBypass = snapshot.globalBypass
        inputGain = snapshot.inputGain
        outputGain = snapshot.outputGain
        channelMode = snapshot.channelMode
        editingChannel = snapshot.channelFocus

        // Restore channel states directly (migration handled in AppStateSnapshot.decode)
        leftState = snapshot.leftState
        rightState = snapshot.rightState

        // Ensure active band count matches left channel
        activeBandCount = bandCount
    }

    // MARK: - Band Count Management

    /// Sets the number of active bands, clamping to the supported range.
    /// - Parameters:
    ///   - newValue: The desired number of bands.
    ///   - preserveConfiguredBands: If true and bands have been modified (non-zero gains),
    ///     only add/remove bands from the right side. If false, respread all bands across the spectrum.
    /// - Returns: The clamped value actually set.
    @discardableResult
    func setActiveBandCount(_ newValue: Int, preserveConfiguredBands: Bool = true) -> Int {
        let clamped = EQConfiguration.clampBandCount(newValue)
        guard clamped != activeBandCount else { return clamped }

        let oldCount = activeBandCount

        if preserveConfiguredBands && hasModifiedBands(upTo: min(oldCount, clamped)) {
            // Bands have been configured - add/remove from right only
            if clamped > oldCount {
                // Adding bands: extend frequencies to the right
                let lastFreq = bands[oldCount - 1].frequency
                let maxFreq: Float = 26000
                let newBandCount = clamped - oldCount
                let ratio = pow(maxFreq / lastFreq, 1 / Float(newBandCount + 1))

                // Update both channels
                for i in oldCount..<clamped {
                    let freq = lastFreq * pow(ratio, Float(i - oldCount + 1))
                    leftState.userEQ.bands[i] = EQBandConfiguration.parametric(
                        frequency: freq,
                        q: EQConfiguration.defaultQ
                    )
                    rightState.userEQ.bands[i] = EQBandConfiguration.parametric(
                        frequency: freq,
                        q: EQConfiguration.defaultQ
                    )
                }
            }
            // Removing bands: just decrease count, existing bands preserved
        } else {
            // No modifications - respread all bands across full spectrum
            let frequencies = EQConfiguration.frequenciesForBandCount(clamped)
            for (index, frequency) in frequencies.enumerated() {
                let band = EQBandConfiguration.parametric(
                    frequency: frequency,
                    q: EQConfiguration.defaultQ
                )
                leftState.userEQ.bands[index] = band
                rightState.userEQ.bands[index] = band
            }
        }

        // Update active band count in both channels
        leftState.userEQ.activeBandCount = clamped
        rightState.userEQ.activeBandCount = clamped

        activeBandCount = clamped
        return clamped
    }

    /// Checks if any bands up to the given count have been modified (non-zero gain).
    private func hasModifiedBands(upTo count: Int) -> Bool {
        for i in 0..<count {
            if bands[i].gain != 0 { return true }
        }
        return false
    }

    /// Resets all bands with proper frequency spreading across the spectrum.
    func resetBandsWithFrequencySpread() {
        let frequencies = EQConfiguration.frequenciesForBandCount(activeBandCount)
        for (index, frequency) in frequencies.enumerated() {
            let band = EQBandConfiguration.parametric(
                frequency: frequency,
                q: EQConfiguration.defaultQ
            )
            leftState.userEQ.bands[index] = band
            rightState.userEQ.bands[index] = band
        }
    }

    static func clampBandCount(_ value: Int) -> Int {
        min(max(1, value), maxBandCount)
    }

    // MARK: - Default Frequencies

    /// Generates frequencies for a specific band count.
    /// For 10 bands, uses standard musical frequencies: 32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000
    /// For other counts, uses logarithmic spacing from 20Hz to 26000Hz.
    nonisolated static func frequenciesForBandCount(_ count: Int) -> [Float] {
        // Standard 10-band EQ frequencies (powers of 2, centered around 1kHz)
        if count == 10 {
            return [32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000]
        }

        // Logarithmic spacing for other band counts
        let minFrequency: Float = 20
        let maxFrequency: Float = 26000
        let steps = max(count - 1, 1)
        let ratio = pow(maxFrequency / minFrequency, 1 / Float(steps))

        return (0..<count).map { index in
            minFrequency * pow(ratio, Float(index))
        }
    }

    /// Generates logarithmically spaced default frequencies for all 64 bands.
    nonisolated private static func defaultFrequencies() -> [Float] {
        frequenciesForBandCount(maxBandCount)
    }

    /// Generates default band configurations for all bands.
    nonisolated static func defaultBands() -> [EQBandConfiguration] {
        defaultFrequencies().map { frequency in
            EQBandConfiguration.parametric(
                frequency: frequency,
                q: defaultQ
            )
        }
    }

    // MARK: - Channel Mode Management

    /// Sets the channel mode.
    /// When switching from linked to stereo, copies left channel state to right.
    func setChannelMode(_ newMode: ChannelMode) {
        guard newMode != channelMode else { return }

        if newMode == .stereo && channelMode == .linked {
            // Copy left state to right when switching to stereo
            rightState = leftState
        }

        channelMode = newMode
        objectWillChange.send()
    }

    // MARK: - Channel State Access

    /// Returns the channel state for the specified editing context.
    /// In linked mode, always returns left state.
    /// In stereo mode, returns the state for the currently edited channel.
    func channelState(for channel: EQChannelTarget) -> ChannelEQState {
        switch (channelMode, channel) {
        case (.linked, _):
            return leftState
        case (.stereo, .left), (.stereo, .both):
            return leftState
        case (.stereo, .right):
            return rightState
        }
    }

    // MARK: - Band Updates

    private func isValidIndex(_ index: Int) -> Bool {
        index >= 0 && index < EQConfiguration.maxBandCount
    }

    /// Returns the bands for the currently edited channel.
    /// In linked mode, returns left channel bands.
    /// In stereo mode, returns bands for the editing channel.
    private var currentEditingBands: [EQBandConfiguration] {
        switch channelMode {
        case .linked:
            return leftState.userEQ.bands
        case .stereo:
            return editingChannel == .left
                ? leftState.userEQ.bands
                : rightState.userEQ.bands
        }
    }

    /// Updates the gain for a specific band.
    /// In linked mode, updates both channels.
    /// In stereo mode, updates only the currently edited channel.
    func updateBandGain(index: Int, gain: Float) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].gain = gain
            rightState.userEQ.bands[index].gain = gain
        } else {
            if editingChannel == .left {
                leftState.userEQ.bands[index].gain = gain
            } else {
                rightState.userEQ.bands[index].gain = gain
            }
        }
        objectWillChange.send()
    }

    /// Updates the gain for a specific band on a specific channel.
    func updateBandGain(index: Int, gain: Float, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].gain = gain
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].gain = gain
        }
        objectWillChange.send()
    }

    /// Updates the Q factor for a specific band.
    func updateBandQ(index: Int, q: Float) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].q = q
            rightState.userEQ.bands[index].q = q
        } else {
            if editingChannel == .left {
                leftState.userEQ.bands[index].q = q
            } else {
                rightState.userEQ.bands[index].q = q
            }
        }
        objectWillChange.send()
    }

    /// Updates the Q factor for a specific band on a specific channel.
    func updateBandQ(index: Int, q: Float, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].q = q
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].q = q
        }
        objectWillChange.send()
    }

    /// Updates the frequency for a specific band.
    func updateBandFrequency(index: Int, frequency: Float) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].frequency = frequency
            rightState.userEQ.bands[index].frequency = frequency
        } else {
            if editingChannel == .left {
                leftState.userEQ.bands[index].frequency = frequency
            } else {
                rightState.userEQ.bands[index].frequency = frequency
            }
        }
        objectWillChange.send()
    }

    /// Updates the frequency for a specific band on a specific channel.
    func updateBandFrequency(index: Int, frequency: Float, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].frequency = frequency
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].frequency = frequency
        }
        objectWillChange.send()
    }

    /// Updates the bypass state for a specific band.
    func updateBandBypass(index: Int, bypass: Bool) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].bypass = bypass
            rightState.userEQ.bands[index].bypass = bypass
        } else {
            if editingChannel == .left {
                leftState.userEQ.bands[index].bypass = bypass
            } else {
                rightState.userEQ.bands[index].bypass = bypass
            }
        }
        objectWillChange.send()
    }

    /// Updates the bypass state for a specific band on a specific channel.
    func updateBandBypass(index: Int, bypass: Bool, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].bypass = bypass
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].bypass = bypass
        }
        objectWillChange.send()
    }

    /// Updates the filter type for a specific band.
    func updateBandFilterType(index: Int, filterType: FilterType) {
        guard isValidIndex(index) else { return }

        if channelMode == .linked {
            leftState.userEQ.bands[index].filterType = filterType
            rightState.userEQ.bands[index].filterType = filterType
        } else {
            if editingChannel == .left {
                leftState.userEQ.bands[index].filterType = filterType
            } else {
                rightState.userEQ.bands[index].filterType = filterType
            }
        }
        objectWillChange.send()
    }

    /// Updates the filter type for a specific band on a specific channel.
    func updateBandFilterType(index: Int, filterType: FilterType, channel: EQChannelTarget) {
        guard isValidIndex(index) else { return }

        let targetChannel = channelMode == .linked ? .both : channel

        if targetChannel == .both || targetChannel == .left {
            leftState.userEQ.bands[index].filterType = filterType
        }
        if targetChannel == .both || targetChannel == .right {
            rightState.userEQ.bands[index].filterType = filterType
        }
        objectWillChange.send()
    }
}
