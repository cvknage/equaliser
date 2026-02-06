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
    // MARK: - Published Properties

    /// Global bypass for all EQ bands.
    @Published var globalBypass: Bool = false

    /// Global gain applied to the EQ output.
    @Published var globalGain: Float = 0

    /// Configuration for all 32 EQ bands.
    @Published private(set) var bands: [EQBandConfiguration]

    // MARK: - Constants

    /// Default center frequencies for the 32-band EQ.
    static let defaultFrequencies: [Float] = [
        31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000,
        1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300,
        8000, 10000, 12500, 16000, 20000, 22050, 24000, 26000
    ]

    /// Default bandwidth in octaves.
    static let defaultBandwidth: Float = 0.67

    /// Total number of EQ bands.
    static let bandCount: Int = 32

    // MARK: - Initialization

    init() {
        // Initialize all 32 bands with default frequencies
        bands = Self.defaultFrequencies.map { frequency in
            EQBandConfiguration.parametric(frequency: frequency, bandwidth: Self.defaultBandwidth)
        }
    }

    // MARK: - Band Updates

    /// Updates the gain for a specific band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - gain: The gain value in dB.
    func updateBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].gain = gain
    }

    /// Updates the bandwidth for a specific band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - bandwidth: The bandwidth in octaves.
    func updateBandBandwidth(index: Int, bandwidth: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].bandwidth = bandwidth
    }

    /// Updates the frequency for a specific band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - frequency: The center frequency in Hz.
    func updateBandFrequency(index: Int, frequency: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].frequency = frequency
    }

    /// Updates the bypass state for a specific band.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - bypass: Whether the band should be bypassed.
    func updateBandBypass(index: Int, bypass: Bool) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].bypass = bypass
    }

    // MARK: - Apply to EQ Units

    /// Applies this configuration to a pair of AVAudioUnitEQ instances.
    /// - Parameters:
    ///   - eqUnitA: The first EQ unit (bands 0-15).
    ///   - eqUnitB: The second EQ unit (bands 16-31).
    func apply(to eqUnitA: AVAudioUnitEQ, _ eqUnitB: AVAudioUnitEQ) {
        eqUnitA.bypass = globalBypass
        eqUnitB.bypass = globalBypass
        eqUnitA.globalGain = globalGain
        eqUnitB.globalGain = globalGain

        for (index, config) in bands.enumerated() {
            let (unit, bandIndex) = index < 16
                ? (eqUnitA, index)
                : (eqUnitB, index - 16)

            let band = unit.bands[bandIndex]
            band.filterType = config.filterType
            band.frequency = config.frequency
            band.bandwidth = config.bandwidth
            band.gain = config.gain
            band.bypass = config.bypass
        }
    }

    /// Updates the bypass state on live EQ units.
    /// - Parameters:
    ///   - eqUnitA: The first EQ unit.
    ///   - eqUnitB: The second EQ unit.
    func applyBypass(to eqUnitA: AVAudioUnitEQ, _ eqUnitB: AVAudioUnitEQ) {
        eqUnitA.bypass = globalBypass
        eqUnitB.bypass = globalBypass
    }

    /// Updates a single band's gain on live EQ units.
    /// - Parameters:
    ///   - index: The band index (0-31).
    ///   - eqUnitA: The first EQ unit (bands 0-15).
    ///   - eqUnitB: The second EQ unit (bands 16-31).
    func applyBandGain(index: Int, to eqUnitA: AVAudioUnitEQ, _ eqUnitB: AVAudioUnitEQ) {
        guard index >= 0 && index < bands.count else { return }
        let (unit, bandIndex) = index < 16
            ? (eqUnitA, index)
            : (eqUnitB, index - 16)
        unit.bands[bandIndex].gain = bands[index].gain
    }

    /// Updates a single band's bandwidth on live EQ units.
    func applyBandBandwidth(index: Int, to eqUnitA: AVAudioUnitEQ, _ eqUnitB: AVAudioUnitEQ) {
        guard index >= 0 && index < bands.count else { return }
        let (unit, bandIndex) = index < 16
            ? (eqUnitA, index)
            : (eqUnitB, index - 16)
        unit.bands[bandIndex].bandwidth = bands[index].bandwidth
    }

    /// Updates a single band's frequency on live EQ units.
    func applyBandFrequency(index: Int, to eqUnitA: AVAudioUnitEQ, _ eqUnitB: AVAudioUnitEQ) {
        guard index >= 0 && index < bands.count else { return }
        let (unit, bandIndex) = index < 16
            ? (eqUnitA, index)
            : (eqUnitB, index - 16)
        unit.bands[bandIndex].frequency = bands[index].frequency
    }
}
