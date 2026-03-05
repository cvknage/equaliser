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

    /// Flat - neutral EQ with all bands at 0 dB.
    static let flat: Preset = {
        let bands = defaultBands(count: 10, gainAdjustments: [:])
        return Preset(
            metadata: PresetMetadata(name: "Flat", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Bass Boost - enhanced low frequencies.
    static let bassBoost: Preset = {
        // Boost low frequency bands (0-3)
        let gainAdjustments: [Int: Float] = [
            0: 6.0,   // 20 Hz
            1: 5.0,   // 44 Hz
            2: 4.0,   // 97 Hz
            3: 2.0,   // 213 Hz
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Bass Boost", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -2.0,  // Compensate for increased gain
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Treble Boost - enhanced high frequencies.
    static let trebleBoost: Preset = {
        // Boost high frequency bands (6-9)
        let gainAdjustments: [Int: Float] = [
            6: 2.0,   // 2254 Hz
            7: 3.0,   // 4948 Hz
            8: 4.0,   // 10862 Hz
            9: 5.0,   // 26000 Hz
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Treble Boost", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -2.0,  // Compensate for increased gain
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Vocal Presence - enhanced mid-range for voice clarity.
    static let vocalPresence: Preset = {
        // Cut low-mids, boost vocal presence frequencies
        let gainAdjustments: [Int: Float] = [
            3: -2.0,  // 213 Hz - reduce mud
            5: 2.5,   // 1027 Hz - vocal presence
            6: 3.0,   // 2254 Hz - vocal presence
            7: 1.5,   // 4948 Hz - air/clarity
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Vocal Presence", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -1.5,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Loudness - enhanced bass and treble at low listening levels.
    static let loudness: Preset = {
        // Classic loudness curve - boost lows and highs (smiley curve)
        let gainAdjustments: [Int: Float] = [
            0: 5.0,   // 20 Hz
            1: 4.0,   // 44 Hz
            2: 2.5,   // 97 Hz
            7: 1.5,   // 4948 Hz
            8: 2.5,   // 10862 Hz
            9: 3.0,   // 26000 Hz
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Loudness", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -2.5,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Acoustic - warm, natural sound for acoustic instruments.
    static let acoustic: Preset = {
        // Warmth on lows, reduce boominess, presence in mids, air on highs
        let gainAdjustments: [Int: Float] = [
            0: 1.5,   // 20 Hz - warmth
            1: 1.0,   // 44 Hz - warmth
            2: -1.0,  // 97 Hz - reduce boominess
            5: 1.5,   // 1027 Hz - body/presence
            6: 1.0,   // 2254 Hz - presence
            8: 2.0,   // 10862 Hz - air
            9: 1.5,   // 26000 Hz - air
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Acoustic", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                globalGain: 0,
                inputGain: 0,
                outputGain: -1.0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    // MARK: - Helper Functions

    /// Generates default bands with optional gain adjustments.
    private static func defaultBands(count: Int, gainAdjustments: [Int: Float]) -> [PresetBand] {
        let frequencies = frequenciesForBandCount(count)
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

    /// Generates logarithmically spaced frequencies for a specific band count.
    private static func frequenciesForBandCount(_ count: Int) -> [Float] {
        let minFrequency: Float = 20
        let maxFrequency: Float = 26000
        let steps = max(count - 1, 1)
        let ratio = pow(maxFrequency / minFrequency, 1 / Float(steps))

        return (0..<count).map { index in
            minFrequency * pow(ratio, Float(index))
        }
    }
}

// MARK: - PresetManager Extension

extension PresetManager {
    private static let factoryPresetVersion = 3  // Bump when factory presets change
    private static let factoryVersionKey = "equalizer.factoryPresetVersion"

    /// Installs factory presets if they don't exist or version changed.
    func installFactoryPresetsIfNeeded() {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.factoryVersionKey)
        let needsReinstall = currentVersion < Self.factoryPresetVersion

        for factoryPreset in FactoryPresets.all {
            if needsReinstall || !presetExists(named: factoryPreset.metadata.name) {
                do {
                    // Delete old version if exists
                    if presetExists(named: factoryPreset.metadata.name) {
                        try deletePreset(named: factoryPreset.metadata.name)
                    }
                    try savePreset(factoryPreset)
                } catch {
                    // Ignore errors - factory presets are optional
                }
            } else if let existingIndex = presets.firstIndex(where: { $0.metadata.name == factoryPreset.metadata.name }) {
                // Ensure existing factory presets retain factory flag
                let existingPreset = presets[existingIndex]
                if !existingPreset.metadata.isFactoryPreset {
                    var updatedPreset = existingPreset
                    updatedPreset.metadata.isFactoryPreset = true
                    try? savePreset(updatedPreset)
                }
            }
        }

        if needsReinstall {
            UserDefaults.standard.set(Self.factoryPresetVersion, forKey: Self.factoryVersionKey)
        }
    }
}
