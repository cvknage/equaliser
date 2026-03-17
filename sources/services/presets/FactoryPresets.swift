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
        rock,
        electronic,
        jazz,
        podcast,
        classical,
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
        let bands: [PresetBand] = [
            PresetBand(frequency: 25, bandwidth: 1.2, gain: 4, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 40, bandwidth: 0.9, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 63, bandwidth: 0.8, gain: 8, filterType: .parametric, bypass: false),
            PresetBand(frequency: 100, bandwidth: 0.9, gain: 7, filterType: .parametric, bypass: false),
            PresetBand(frequency: 160, bandwidth: 1.0, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 250, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 400, bandwidth: 1.0, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 630, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Bass Boost", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -5,
                outputGain: 0,
                activeBandCount: 12,
                bands: bands
            )
        )
    }()

    /// Treble Boost - adds brightness and air without harshness.
    static let trebleBoost: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 80, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, bandwidth: 1.0, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1600, bandwidth: 1.0, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, bandwidth: 0.9, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, bandwidth: 0.8, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, bandwidth: 0.9, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, bandwidth: 1.1, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, bandwidth: 1.3, gain: 3, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Treble Boost", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -3,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Vocal Presence - makes vocals cut through with clarity.
    static let vocalPresence: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 50, bandwidth: 1.5, gain: -8, filterType: .highPass, bypass: false),
            PresetBand(frequency: 80, bandwidth: 1.0, gain: -6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, bandwidth: 1.0, gain: -4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, bandwidth: 0.9, gain: -2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 315, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, bandwidth: 0.8, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1250, bandwidth: 0.7, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, bandwidth: 0.7, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, bandwidth: 0.8, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, bandwidth: 0.9, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, bandwidth: 1.0, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Vocal Presence", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -1,
                outputGain: 0,
                activeBandCount: 14,
                bands: bands
            )
        )
    }()

    /// Loudness - Fletcher-Munson compensation for low-level listening.
    static let loudness: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 32, bandwidth: 1.4, gain: 6, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 50, bandwidth: 1.0, gain: 8, filterType: .parametric, bypass: false),
            PresetBand(frequency: 80, bandwidth: 1.0, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, bandwidth: 1.2, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, bandwidth: 1.3, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, bandwidth: 1.1, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, bandwidth: 1.2, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.4, gain: 5, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Loudness", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -4,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Acoustic - warm, natural sound for acoustic instruments.
    static let acoustic: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 50, bandwidth: 1.3, gain: 3, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 80, bandwidth: 1.1, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 315, bandwidth: 1.0, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1250, bandwidth: 0.9, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, bandwidth: 0.8, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, bandwidth: 1.0, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, bandwidth: 1.2, gain: 1, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Acoustic", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2,
                outputGain: 0,
                activeBandCount: 11,
                bands: bands
            )
        )
    }()

    /// Rock - aggressive and punchy with scooped mids.
    static let rock: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 40, bandwidth: 1.1, gain: 4, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 80, bandwidth: 0.9, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, bandwidth: 1.0, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 250, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, bandwidth: 1.0, gain: -2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 0.9, gain: -4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1600, bandwidth: 0.9, gain: -3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, bandwidth: 0.9, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, bandwidth: 0.9, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, bandwidth: 1.0, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 14000, bandwidth: 1.1, gain: 2, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Rock", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2,
                outputGain: 0,
                activeBandCount: 12,
                bands: bands
            )
        )
    }()

    /// Electronic/EDM - tight bass and bright highs for modern electronic music.
    static let electronic: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 30, bandwidth: 1.0, gain: 4, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 50, bandwidth: 0.7, gain: 7, filterType: .parametric, bypass: false),
            PresetBand(frequency: 80, bandwidth: 0.8, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, bandwidth: 0.9, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, bandwidth: 1.0, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 400, bandwidth: 1.0, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1600, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, bandwidth: 0.8, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, bandwidth: 0.8, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, bandwidth: 1.0, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.1, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, bandwidth: 1.2, gain: 2, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Electronic", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -3.5,
                outputGain: 0,
                activeBandCount: 13,
                bands: bands
            )
        )
    }()

    /// Jazz - warm and smooth for classic jazz sound.
    static let jazz: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 63, bandwidth: 1.2, gain: 2, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 125, bandwidth: 1.1, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 250, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, bandwidth: 1.0, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.2, gain: -1, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Jazz", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -1.5,
                outputGain: 0,
                activeBandCount: 10,
                bands: bands
            )
        )
    }()

    /// Podcast/Voice - optimized for spoken word content.
    static let podcast: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 60, bandwidth: 1.5, gain: -10, filterType: .highPass, bypass: false),
            PresetBand(frequency: 100, bandwidth: 1.0, gain: -6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 180, bandwidth: 0.9, gain: -3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 300, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 600, bandwidth: 1.0, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 0.8, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, bandwidth: 0.7, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, bandwidth: 0.8, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6000, bandwidth: 1.0, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 14000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Podcast", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -0.5,
                outputGain: 0,
                activeBandCount: 12,
                bands: bands
            )
        )
    }()

    /// Classical - neutral and refined for orchestral music.
    static let classical: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 50, bandwidth: 1.3, gain: 1, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 125, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 315, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, bandwidth: 1.1, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, bandwidth: 1.2, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, bandwidth: 1.2, gain: -1, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Classical", isFactoryPreset: true),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -0.5,
                outputGain: 0,
                activeBandCount: 9,
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
    private static let factoryPresetVersion = 7  // Bump when factory presets change
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
                    try savePresetWithoutReload(factoryPreset)
                } catch {
                    // Ignore errors - factory presets are optional
                }
            } else if let existingIndex = presets.firstIndex(where: { $0.metadata.name == factoryPreset.metadata.name }) {
                // Ensure existing factory presets retain factory flag
                let existingPreset = presets[existingIndex]
                if !existingPreset.metadata.isFactoryPreset {
                    var updatedPreset = existingPreset
                    updatedPreset.metadata.isFactoryPreset = true
                    try? savePresetWithoutReload(updatedPreset)
                }
            }
        }

        if needsReinstall {
            UserDefaults.standard.set(Self.factoryPresetVersion, forKey: Self.factoryVersionKey)
        }
        
        // Reload once after all factory presets are saved
        loadAllPresets()
    }
}
