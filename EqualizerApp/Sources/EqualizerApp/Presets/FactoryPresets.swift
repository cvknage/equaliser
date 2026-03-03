import AVFoundation
import Foundation

/// Factory presets that ship with the app.
enum FactoryPresets {
    /// All factory presets.
    static let all: [Preset] = [
        flat,
        bassBoost,
        trebleBoost,
        vocalPresence,
        loudness,
        acoustic,
    ]

    /// Flat EQ - all bands at 0 dB.
    static let flat: Preset = {
        let bands = defaultBands(count: 32, gainAdjustments: [:])
        return Preset(
            metadata: PresetMetadata(name: "Flat"),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: 0,
                activeBandCount: 32,
                bands: bands
            )
        )
    }()

    /// Bass Boost - enhanced low frequencies.
    static let bassBoost: Preset = {
        // Boost frequencies below 250 Hz
        let gainAdjustments: [Int: Float] = [
            0: 6.0,   // 20 Hz
            1: 6.0,   // 25 Hz
            2: 5.5,   // 32 Hz
            3: 5.0,   // 40 Hz
            4: 4.5,   // 50 Hz
            5: 4.0,   // 63 Hz
            6: 3.5,   // 80 Hz
            7: 3.0,   // 100 Hz
            8: 2.5,   // 125 Hz
            9: 2.0,   // 160 Hz
            10: 1.5,  // 200 Hz
            11: 1.0,  // 250 Hz
            12: 0.5,  // 315 Hz
        ]
        let bands = defaultBands(count: 32, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Bass Boost"),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -2.0,  // Compensate for increased gain
                activeBandCount: 32,
                bands: bands
            )
        )
    }()

    /// Treble Boost - enhanced high frequencies.
    static let trebleBoost: Preset = {
        // Boost frequencies above 2 kHz
        let gainAdjustments: [Int: Float] = [
            19: 0.5,  // 2 kHz
            20: 1.0,  // 2.5 kHz
            21: 1.5,  // 3.15 kHz
            22: 2.0,  // 4 kHz
            23: 2.5,  // 5 kHz
            24: 3.0,  // 6.3 kHz
            25: 3.5,  // 8 kHz
            26: 4.0,  // 10 kHz
            27: 4.5,  // 12.5 kHz
            28: 5.0,  // 16 kHz
            29: 5.0,  // 20 kHz
            30: 5.0,  // ~20 kHz
            31: 5.0,  // ~26 kHz
        ]
        let bands = defaultBands(count: 32, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Treble Boost"),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -2.0,  // Compensate for increased gain
                activeBandCount: 32,
                bands: bands
            )
        )
    }()

    /// Vocal Presence - enhanced mid-range for voice clarity.
    static let vocalPresence: Preset = {
        // Boost vocal presence frequencies (1-4 kHz) and reduce low mud
        let gainAdjustments: [Int: Float] = [
            8: -1.0,  // 125 Hz - reduce mud
            9: -1.5,  // 160 Hz - reduce mud
            10: -2.0, // 200 Hz - reduce mud
            11: -1.5, // 250 Hz - reduce mud
            12: -1.0, // 315 Hz
            14: 0.5,  // 500 Hz
            15: 1.0,  // 630 Hz
            16: 1.5,  // 800 Hz
            17: 2.0,  // 1 kHz - vocal presence
            18: 2.5,  // 1.25 kHz - vocal presence
            19: 3.0,  // 1.6 kHz - vocal presence
            20: 3.0,  // 2 kHz - vocal presence
            21: 2.5,  // 2.5 kHz
            22: 2.0,  // 3.15 kHz
            23: 1.5,  // 4 kHz - sibilance area
            24: 1.0,  // 5 kHz
        ]
        let bands = defaultBands(count: 32, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Vocal Presence"),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -1.5,
                activeBandCount: 32,
                bands: bands
            )
        )
    }()

    /// Loudness - enhanced bass and treble at low listening levels.
    static let loudness: Preset = {
        // Classic loudness curve - boost lows and highs
        let gainAdjustments: [Int: Float] = [
            0: 5.0,   // 20 Hz
            1: 5.0,   // 25 Hz
            2: 4.5,   // 32 Hz
            3: 4.0,   // 40 Hz
            4: 3.5,   // 50 Hz
            5: 3.0,   // 63 Hz
            6: 2.5,   // 80 Hz
            7: 2.0,   // 100 Hz
            8: 1.5,   // 125 Hz
            9: 1.0,   // 160 Hz
            10: 0.5,  // 200 Hz
            24: 0.5,  // 5 kHz
            25: 1.0,  // 6.3 kHz
            26: 1.5,  // 8 kHz
            27: 2.0,  // 10 kHz
            28: 2.5,  // 12.5 kHz
            29: 3.0,  // 16 kHz
            30: 3.0,  // 20 kHz
            31: 3.0,  // ~26 kHz
        ]
        let bands = defaultBands(count: 32, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Loudness"),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -2.5,
                activeBandCount: 32,
                bands: bands
            )
        )
    }()

    /// Acoustic - warm, natural sound for acoustic instruments.
    static let acoustic: Preset = {
        let gainAdjustments: [Int: Float] = [
            0: 1.5,   // 20 Hz - warmth
            1: 1.5,   // 25 Hz
            2: 1.0,   // 32 Hz
            3: 0.5,   // 40 Hz
            8: -1.0,  // 125 Hz - reduce boominess
            9: -1.5,  // 160 Hz
            10: -1.0, // 200 Hz
            16: 0.5,  // 800 Hz - body
            17: 1.0,  // 1 kHz - presence
            18: 1.5,  // 1.25 kHz
            19: 1.5,  // 1.6 kHz
            20: 1.0,  // 2 kHz
            24: 1.0,  // 5 kHz - air
            25: 1.5,  // 6.3 kHz
            26: 2.0,  // 8 kHz
            27: 2.0,  // 10 kHz
            28: 1.5,  // 12.5 kHz
        ]
        let bands = defaultBands(count: 32, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Acoustic"),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -1.0,
                activeBandCount: 32,
                bands: bands
            )
        )
    }()

    // MARK: - Helper Functions

    /// Generates default bands with optional gain adjustments.
    private static func defaultBands(count: Int, gainAdjustments: [Int: Float]) -> [PresetBand] {
        let frequencies = defaultFrequencies()
        return frequencies.enumerated().map { index, frequency in
            PresetBand(
                frequency: frequency,
                bandwidth: EQConfiguration.defaultBandwidth,
                gain: gainAdjustments[index] ?? 0,
                filterType: .parametric,
                bypass: false
            )
        }
    }

    /// Generates logarithmically spaced default frequencies for 64 bands.
    private static func defaultFrequencies() -> [Float] {
        let minFrequency: Float = 20
        let maxFrequency: Float = 26000
        let steps = EQConfiguration.maxBandCount - 1
        let ratio = pow(maxFrequency / minFrequency, 1 / Float(steps))

        return (0..<EQConfiguration.maxBandCount).map { index in
            minFrequency * pow(ratio, Float(index))
        }
    }
}

// MARK: - PresetManager Extension

extension PresetManager {
    /// Installs factory presets if they don't already exist.
    func installFactoryPresetsIfNeeded() {
        for factoryPreset in FactoryPresets.all {
            if !presetExists(named: factoryPreset.metadata.name) {
                do {
                    try savePreset(factoryPreset)
                } catch {
                    // Ignore errors - factory presets are optional
                }
            }
        }
    }
}
