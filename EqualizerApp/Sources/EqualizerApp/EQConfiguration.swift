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
        filterType = AVAudioUnitEQFilterType(rawValue: filterTypeRaw) ?? .parametric
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

private struct EQSnapshot: Codable, Sendable {
    var globalBypass: Bool
    var globalGain: Float
    var inputGain: Float
    var outputGain: Float
    var activeBandCount: Int
    var bands: [EQBandConfiguration]
}

/// Stores EQ configuration independently of any AVAudioEngine instance.
/// This allows settings to be stored and modified without triggering
/// audio hardware initialization.
@MainActor
final class EQConfiguration: ObservableObject {
    // MARK: - Constants

    nonisolated static let maxBandCount: Int = 64
    nonisolated static let defaultBandCount: Int = 32
    nonisolated static let defaultBandwidth: Float = 0.67

    // MARK: - Published Properties

        /// Global bypass for all EQ bands.
    @Published var globalBypass: Bool = false {
        didSet { persistSnapshot() }
    }

    /// Global gain applied to the EQ output.
    @Published var globalGain: Float = 0 {
        didSet { persistSnapshot() }
    }

    /// Input gain applied before EQ processing (in dB).
    @Published var inputGain: Float = 0 {
        didSet { persistSnapshot() }
    }

    /// Output gain applied after EQ processing (in dB).
    @Published var outputGain: Float = 0 {
        didSet { persistSnapshot() }
    }

    /// Current number of active bands exposed to the UI and audio engine.
    @Published private(set) var activeBandCount: Int

    /// Configuration for all bands (always sized to `maxBandCount`).
    @Published private(set) var bands: [EQBandConfiguration]

    private let storage: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let snapshot = "equalizer.eqConfiguration"
    }

    // MARK: - Persistence

    private func loadSnapshot() {
        guard let data = storage.data(forKey: Keys.snapshot) else { return }
        do {
            let snapshot = try decoder.decode(EQSnapshot.self, from: data)
            globalBypass = snapshot.globalBypass
            globalGain = snapshot.globalGain
            inputGain = snapshot.inputGain
            outputGain = snapshot.outputGain
            activeBandCount = EQConfiguration.clampBandCount(snapshot.activeBandCount)
            if snapshot.bands.count == EQConfiguration.maxBandCount {
                bands = snapshot.bands
            } else {
                let filled = snapshot.bands + Self.defaultFrequencies().dropFirst(snapshot.bands.count).map {
                    EQBandConfiguration.parametric(frequency: $0)
                }
                bands = Array(filled.prefix(EQConfiguration.maxBandCount))
            }
        } catch {
            storage.removeObject(forKey: Keys.snapshot)
        }
    }

    private func persistSnapshot() {
        let snapshot = EQSnapshot(
            globalBypass: globalBypass,
            globalGain: globalGain,
            inputGain: inputGain,
            outputGain: outputGain,
            activeBandCount: activeBandCount,
            bands: bands
        )

        do {
            let data = try encoder.encode(snapshot)
            storage.set(data, forKey: Keys.snapshot)
        } catch {
            os_log("Failed to persist EQ snapshot: %{public}@", type: .error, String(describing: error))
        }
    }

    // MARK: - Initialization

    init(initialBandCount: Int = EQConfiguration.defaultBandCount,
         storage: UserDefaults = .standard) {
        self.storage = storage

        let frequencies = EQConfiguration.defaultFrequencies()
        bands = frequencies.map { frequency in
            EQBandConfiguration.parametric(
                frequency: frequency,
                bandwidth: EQConfiguration.defaultBandwidth
            )
        }
        activeBandCount = EQConfiguration.clampBandCount(initialBandCount)

        loadSnapshot()
    }

    // MARK: - Band Count Management

    /// Sets the number of active bands, clamping to the supported range.
    /// - Returns: The clamped value actually set.
    @discardableResult
    func setActiveBandCount(_ newValue: Int) -> Int {
        let clamped = EQConfiguration.clampBandCount(newValue)
        if clamped != activeBandCount {
            activeBandCount = clamped
            persistSnapshot()
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
        persistSnapshot()
    }

    /// Updates the bandwidth for a specific band.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        guard isValidIndex(index) else { return }
        bands[index].bandwidth = bandwidth
        persistSnapshot()
    }

    /// Updates the frequency for a specific band.
    func updateBandFrequency(index: Int, frequency: Float) {
        guard isValidIndex(index) else { return }
        bands[index].frequency = frequency
        persistSnapshot()
    }

    /// Updates the bypass state for a specific band.
    func updateBandBypass(index: Int, bypass: Bool) {
        guard isValidIndex(index) else { return }
        bands[index].bypass = bypass
        persistSnapshot()
    }

    /// Updates the filter type for a specific band.
    func updateBandFilterType(index: Int, filterType: AVAudioUnitEQFilterType) {
        guard isValidIndex(index) else { return }
        bands[index].filterType = filterType
        persistSnapshot()
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
