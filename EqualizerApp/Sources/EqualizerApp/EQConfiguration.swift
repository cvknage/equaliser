import AVFoundation

/// Configuration for a single EQ band.
struct EQBandConfiguration: Sendable {
    var frequency: Float
    var bandwidth: Float
    var gain: Float
    var filterType: AVAudioUnitEQFilterType
    var bypass: Bool

    /// Default parametric band configuration.
    static func parametric(frequency: Float, bandwidth: Float = 0.67) -> EQBandConfiguration {
        EQBandConfiguration(
            frequency: frequency,
            bandwidth: bandwidth,
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

    static let maxBandCount: Int = 64
    static let defaultBandCount: Int = 32
    static let defaultBandwidth: Float = 0.67

    // MARK: - Published Properties

    /// Global bypass for all EQ bands.
    @Published var globalBypass: Bool = false

    /// Global gain applied to the EQ output.
    @Published var globalGain: Float = 0

    /// Input gain applied before EQ processing (in dB).
    @Published var inputGain: Float = 0

    /// Output gain applied after EQ processing (in dB).
    @Published var outputGain: Float = 0

    /// Current number of active bands exposed to the UI and audio engine.
    @Published private(set) var activeBandCount: Int

    /// Configuration for all bands (always sized to `maxBandCount`).
    @Published private(set) var bands: [EQBandConfiguration]

    // MARK: - Initialization

    init(initialBandCount: Int = EQConfiguration.defaultBandCount) {
        let frequencies = EQConfiguration.defaultFrequencies()
        bands = frequencies.map { frequency in
            EQBandConfiguration.parametric(
                frequency: frequency,
                bandwidth: EQConfiguration.defaultBandwidth
            )
        }
        activeBandCount = EQConfiguration.clampBandCount(initialBandCount)
    }

    // MARK: - Band Count Management

    /// Sets the number of active bands, clamping to the supported range.
    /// - Returns: The clamped value actually set.
    @discardableResult
    func setActiveBandCount(_ newValue: Int) -> Int {
        let clamped = EQConfiguration.clampBandCount(newValue)
        if clamped != activeBandCount {
            activeBandCount = clamped
        }
        return clamped
    }

    static func clampBandCount(_ value: Int) -> Int {
        min(max(1, value), maxBandCount)
    }

    // MARK: - Default Frequencies

    /// Generates logarithmically spaced default frequencies for all 64 bands.
    private static func defaultFrequencies() -> [Float] {
        let minFrequency: Float = 20
        let maxFrequency: Float = 26000
        let steps = maxBandCount - 1
        let ratio = pow(maxFrequency / minFrequency, 1 / Float(steps))

        return (0..<maxBandCount).map { index in
            minFrequency * pow(ratio, Float(index))
        }
    }

    // MARK: - Band Updates

    private func isValidIndex(_ index: Int) -> Bool {
        index >= 0 && index < bands.count
    }

    /// Updates the gain for a specific band.
    func updateBandGain(index: Int, gain: Float) {
        guard isValidIndex(index) else { return }
        bands[index].gain = gain
    }

    /// Updates the bandwidth for a specific band.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        guard isValidIndex(index) else { return }
        bands[index].bandwidth = bandwidth
    }

    /// Updates the frequency for a specific band.
    func updateBandFrequency(index: Int, frequency: Float) {
        guard isValidIndex(index) else { return }
        bands[index].frequency = frequency
    }

    /// Updates the bypass state for a specific band.
    func updateBandBypass(index: Int, bypass: Bool) {
        guard isValidIndex(index) else { return }
        bands[index].bypass = bypass
    }

    /// Updates the filter type for a specific band.
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        guard isValidIndex(index) else { return }
        bands[index].filterType = filterType
    }

    // MARK: - EQ Application Helpers

    func apply(to eqUnits: [AVAudioUnitEQ]) {
        guard !eqUnits.isEmpty else { return }

        for unit in eqUnits {
            unit.bypass = globalBypass
            unit.globalGain = globalGain
        }

        let targetCount = min(activeBandCount, totalCapacity(of: eqUnits))
        for index in 0..<targetCount {
            guard let (unit, bandIndex) = bandLocation(for: index, in: eqUnits) else { continue }
            let config = bands[index]
            let band = unit.bands[bandIndex]
            band.filterType = config.filterType
            band.frequency = config.frequency
            band.bandwidth = config.bandwidth
            band.gain = config.gain
            band.bypass = config.bypass
        }
    }

    func applyBypass(to eqUnits: [AVAudioUnitEQ]) {
        for unit in eqUnits {
            unit.bypass = globalBypass
        }
    }

    func applyBandGain(index: Int, to eqUnits: [AVAudioUnitEQ]) {
        guard let (unit, bandIndex) = bandLocation(for: index, in: eqUnits) else { return }
        unit.bands[bandIndex].gain = bands[index].gain
    }

    func applyBandBandwidth(index: Int, to eqUnits: [AVAudioUnitEQ]) {
        guard let (unit, bandIndex) = bandLocation(for: index, in: eqUnits) else { return }
        unit.bands[bandIndex].bandwidth = bands[index].bandwidth
    }

    func applyBandFrequency(index: Int, to eqUnits: [AVAudioUnitEQ]) {
        guard let (unit, bandIndex) = bandLocation(for: index, in: eqUnits) else { return }
        unit.bands[bandIndex].frequency = bands[index].frequency
    }

    func applyBandFilterType(index: Int, to eqUnits: [AVAudioUnitEQ]) {
        guard let (unit, bandIndex) = bandLocation(for: index, in: eqUnits) else { return }
        unit.bands[bandIndex].filterType = bands[index].filterType
    }

    func applyBandBypass(index: Int, to eqUnits: [AVAudioUnitEQ]) {
        guard let (unit, bandIndex) = bandLocation(for: index, in: eqUnits) else { return }
        unit.bands[bandIndex].bypass = bands[index].bypass
    }

    // MARK: - Helpers

    private func totalCapacity(of eqUnits: [AVAudioUnitEQ]) -> Int {
        eqUnits.reduce(0) { $0 + $1.bands.count }
    }

    private func bandLocation(for index: Int, in eqUnits: [AVAudioUnitEQ]) -> (AVAudioUnitEQ, Int)? {
        guard index >= 0 else { return nil }
        var remaining = index
        for unit in eqUnits {
            let capacity = unit.bands.count
            if remaining < capacity {
                return (unit, remaining)
            }
            remaining -= capacity
        }
        return nil
    }
}
