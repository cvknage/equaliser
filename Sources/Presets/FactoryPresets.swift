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
                inputGain: 0,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Bass Boost - adds punch and warmth without mud.
    static let bassBoost: Preset = {
        // Boost bass frequencies, gentle transition to mids
        let gainAdjustments: [Int: Float] = [
            0: 3.0,   // 32 Hz - sub-bass (subtle)
            1: 5.0,   // 64 Hz - bass foundation (main boost)
            2: 4.0,   // 128 Hz - upper bass (punch)
            3: 1.0,   // 256 Hz - low mids (gentle transition)
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Bass Boost", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2.0,  // Compensate for increased gain
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Treble Boost - adds brightness and air without harshness.
    static let trebleBoost: Preset = {
        // Boost highs with decreasing curve (not harsh)
        let gainAdjustments: [Int: Float] = [
            6: 3.0,   // 2000 Hz - presence
            7: 4.0,   // 4000 Hz - clarity (peak)
            8: 3.0,   // 8000 Hz - treble (start reducing)
            9: 2.0,   // 16000 Hz - air (gentle)
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Treble Boost", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2.0,  // Compensate for increased gain
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Vocal Presence - makes vocals cut through with clarity.
    static let vocalPresence: Preset = {
        // Cut lows, boost vocal presence frequencies
        let gainAdjustments: [Int: Float] = [
            3: -2.0,  // 256 Hz - reduce mud/boominess
            4: -1.0,  // 512 Hz - reduce boxiness
            6: 3.0,   // 2000 Hz - vocal presence (core)
            7: 4.0,   // 4000 Hz - vocal clarity (peak)
            8: 2.0,   // 8000 Hz - breath/air
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Vocal Presence", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -1.5,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Loudness - Fletcher-Munson compensation for low-level listening.
    static let loudness: Preset = {
        // Classic loudness curve - boost lows and highs
        let gainAdjustments: [Int: Float] = [
            0: 4.0,   // 32 Hz - deep bass
            1: 5.0,   // 64 Hz - bass (peak)
            2: 3.0,   // 128 Hz - upper bass
            3: 1.0,   // 256 Hz - gentle transition
            7: 2.0,   // 4000 Hz - presence
            8: 3.0,   // 8000 Hz - brilliance
            9: 2.0,   // 16000 Hz - air
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Loudness", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2.5,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Acoustic - warm, natural sound for acoustic instruments.
    static let acoustic: Preset = {
        // Warm and natural with subtle presence and air
        let gainAdjustments: [Int: Float] = [
            1: 2.0,   // 64 Hz - warmth/body
            2: 1.0,   // 128 Hz - acoustic body
            3: -1.0,  // 256 Hz - reduce mud slightly
            5: 1.0,   // 1000 Hz - natural presence
            6: 2.0,   // 2000 Hz - clarity
            7: 1.0,   // 4000 Hz - definition
            8: 2.0,   // 8000 Hz - sparkle
            9: 1.0,   // 16000 Hz - air
        ]
        let bands = defaultBands(count: 10, gainAdjustments: gainAdjustments)
        return Preset(
            metadata: PresetMetadata(name: "Acoustic", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -1.0,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    // MARK: - Helper Functions

    /// Generates default bands with optional gain adjustments.
    private static func defaultBands(count: Int, gainAdjustments: [Int: Float]) -> [PresetBand] {
        let frequencies = EQConfiguration.frequenciesForBandCount(count)
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
}

// MARK: - PresetManager Extension

extension PresetManager {
    private static let factoryPresetVersion = 6  // Bump when factory presets change
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
