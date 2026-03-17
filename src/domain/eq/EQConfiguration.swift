import AVFoundation
import Foundation
import os.log

/// Configuration for a single EQ band.
struct EQBandConfiguration: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case frequency
        case bandwidth
        case gain
        case filterType
        case bypass
    }

    init(frequency: Float, bandwidth: Float, gain: Float, filterType: AVAudioUnitEQFilterType, bypass: Bool) {
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.gain = gain
        self.filterType = filterType
        self.bypass = bypass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(Float.self, forKey: .frequency)
        bandwidth = try container.decode(Float.self, forKey: .bandwidth)
        gain = try container.decode(Float.self, forKey: .gain)
        let filterTypeRaw = try container.decode(Int.self, forKey: .filterType)
        filterType = AVAudioUnitEQFilterType(validatedRawValue: filterTypeRaw) ?? .parametric
        bypass = try container.decode(Bool.self, forKey: .bypass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(bandwidth, forKey: .bandwidth)
        try container.encode(gain, forKey: .gain)
        try container.encode(filterType.rawValue, forKey: .filterType)
        try container.encode(bypass, forKey: .bypass)
    }

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

    nonisolated static let maxBandCount: Int = 64
    nonisolated static let defaultBandCount: Int = 10
    nonisolated static let defaultBandwidth: Float = 0.67

    // MARK: - Published Properties

    /// Global bypass for all EQ bands.
    @Published var globalBypass: Bool = false

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

    convenience init(from snapshot: AppStateSnapshot) {
        self.init(initialBandCount: snapshot.activeBandCount)
        globalBypass = snapshot.globalBypass
        inputGain = snapshot.inputGain
        outputGain = snapshot.outputGain
        activeBandCount = snapshot.activeBandCount
        if snapshot.bands.count == EQConfiguration.maxBandCount {
            bands = snapshot.bands
        }
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
                for i in oldCount..<clamped {
                    let freq = lastFreq * pow(ratio, Float(i - oldCount + 1))
                    bands[i] = EQBandConfiguration.parametric(
                        frequency: freq,
                        bandwidth: EQConfiguration.defaultBandwidth
                    )
                }
            }
            // Removing bands: just decrease count, existing bands preserved
        } else {
            // No modifications - respread all bands across full spectrum
            let frequencies = EQConfiguration.frequenciesForBandCount(clamped)
            for (index, frequency) in frequencies.enumerated() {
                bands[index] = EQBandConfiguration.parametric(
                    frequency: frequency,
                    bandwidth: EQConfiguration.defaultBandwidth
                )
            }
        }

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
            bands[index] = EQBandConfiguration.parametric(
                frequency: frequency,
                bandwidth: EQConfiguration.defaultBandwidth
            )
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
                bandwidth: defaultBandwidth
            )
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
        objectWillChange.send()
    }

    /// Updates the bandwidth for a specific band.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        guard isValidIndex(index) else { return }
        bands[index].bandwidth = bandwidth
        objectWillChange.send()
    }

    /// Updates the frequency for a specific band.
    func updateBandFrequency(index: Int, frequency: Float) {
        guard isValidIndex(index) else { return }
        bands[index].frequency = frequency
        objectWillChange.send()
    }

    /// Updates the bypass state for a specific band.
    func updateBandBypass(index: Int, bypass: Bool) {
        guard isValidIndex(index) else { return }
        bands[index].bypass = bypass
        objectWillChange.send()
    }

    /// Updates the filter type for a specific band.
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        guard isValidIndex(index) else { return }
        bands[index].filterType = filterType
        objectWillChange.send()
    }

    // MARK: - EQ Application Helpers

    func apply(to eqUnits: [AVAudioUnitEQ]) {
        guard !eqUnits.isEmpty else { return }

        for unit in eqUnits {
            unit.bypass = globalBypass
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
