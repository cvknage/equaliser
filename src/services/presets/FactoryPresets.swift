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
                inputGain: 0,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Bass Boost - adds punch and warmth without mud.
    static let bassBoost: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 25, q: 1.22, gain: 4, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 40, q: 1.53, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 63, q: 1.66, gain: 8, filterType: .parametric, bypass: false),
            PresetBand(frequency: 100, q: 1.53, gain: 7, filterType: .parametric, bypass: false),
            PresetBand(frequency: 160, q: 1.41, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 250, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 400, q: 1.41, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 630, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Bass Boost", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -8,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Treble Boost - adds brightness and air without harshness.
    static let trebleBoost: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 80, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, q: 1.41, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1600, q: 1.41, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, q: 1.53, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, q: 1.66, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, q: 1.53, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, q: 1.30, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, q: 1.16, gain: 3, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Treble Boost", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -6,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Vocal Presence - makes vocals cut through with clarity.
    static let vocalPresence: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 50, q: 1.04, gain: -8, filterType: .highPass, bypass: false),
            PresetBand(frequency: 80, q: 1.41, gain: -6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, q: 1.41, gain: -4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, q: 1.53, gain: -2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 315, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, q: 1.66, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1250, q: 1.85, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, q: 1.85, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, q: 1.66, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, q: 1.53, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, q: 1.41, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Vocal Presence", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -6,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Loudness - Fletcher-Munson compensation for low-level listening.
    static let loudness: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 32, q: 1.10, gain: 6, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 50, q: 1.41, gain: 8, filterType: .parametric, bypass: false),
            PresetBand(frequency: 80, q: 1.41, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, q: 1.22, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, q: 1.16, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, q: 1.30, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, q: 1.22, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.10, gain: 5, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Loudness", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -8,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Acoustic - warm, natural sound for acoustic instruments.
    static let acoustic: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 50, q: 1.16, gain: 3, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 80, q: 1.30, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 315, q: 1.41, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1250, q: 1.53, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, q: 1.66, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, q: 1.41, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, q: 1.22, gain: 1, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Acoustic", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -3,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Rock - aggressive and punchy with scooped mids.
    static let rock: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 40, q: 1.30, gain: 4, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 80, q: 1.53, gain: 6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, q: 1.41, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 250, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, q: 1.41, gain: -2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.53, gain: -4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1600, q: 1.53, gain: -3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2500, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, q: 1.53, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6300, q: 1.53, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, q: 1.41, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 14000, q: 1.30, gain: 2, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Rock", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -6,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Electronic/EDM - tight bass and bright highs for modern electronic music.
    static let electronic: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 30, q: 1.41, gain: 4, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 50, q: 1.85, gain: 7, filterType: .parametric, bypass: false),
            PresetBand(frequency: 80, q: 1.66, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 125, q: 1.53, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 200, q: 1.41, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 400, q: 1.41, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1600, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, q: 1.66, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, q: 1.66, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, q: 1.41, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.30, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, q: 1.22, gain: 2, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Electronic", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -7,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Jazz - warm and smooth for classic jazz sound.
    static let jazz: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 63, q: 1.22, gain: 2, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 125, q: 1.30, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 250, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 500, q: 1.41, gain: 2, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 3150, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.22, gain: -1, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Jazz", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -2,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Podcast/Voice - optimized for spoken word content.
    static let podcast: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 60, q: 1.04, gain: -10, filterType: .highPass, bypass: false),
            PresetBand(frequency: 100, q: 1.41, gain: -6, filterType: .parametric, bypass: false),
            PresetBand(frequency: 180, q: 1.53, gain: -3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 300, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 600, q: 1.41, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.66, gain: 3, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, q: 1.85, gain: 5, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, q: 1.66, gain: 4, filterType: .parametric, bypass: false),
            PresetBand(frequency: 6000, q: 1.41, gain: -1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 14000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Podcast", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -5,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
            )
        )
    }()

    /// Classical - neutral and refined for orchestral music.
    static let classical: Preset = {
        let bands: [PresetBand] = [
            PresetBand(frequency: 50, q: 1.16, gain: 1, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 125, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 315, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 800, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 2000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 5000, q: 1.30, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 8000, q: 1.22, gain: 1, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.41, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 16000, q: 1.22, gain: -1, filterType: .highShelf, bypass: false),
        ]
        return Preset(
            metadata: PresetMetadata(name: "Classical", isFactoryPreset: true),
            settings: PresetSettings(
                inputGain: -1,
                outputGain: 0,
                leftBands: bands,
                rightBands: bands
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
                q: EQConfiguration.defaultQ,
                gain: gainAdjustments[index] ?? 0,
                filterType: .parametric,
                bypass: false
            )
        }
    }
}

// MARK: - PresetManager Extension

extension PresetManager {
    private static let factoryPresetVersion = 10  // Bump when factory presets change (v2 format)
    private static let factoryVersionKey = "equalizer.factoryPresetVersion"

    /// Installs factory presets if they don't exist or version changed.
    func installFactoryPresetsIfNeeded() {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.factoryVersionKey)
        let needsReinstall = currentVersion < Self.factoryPresetVersion

        for factoryPreset in FactoryPresets.all {
            let existingIndex = presets.firstIndex(where: { $0.metadata.name == factoryPreset.metadata.name })

            if needsReinstall {
                if let index = existingIndex {
                    let existingPreset = presets[index]
                    if existingPreset.metadata.isFactoryPreset {
                        // Pristine factory preset - safe to replace with updated version
                        try? savePresetWithoutReload(factoryPreset)
                    }
                    // else: user-modified preset, skip to preserve changes
                } else {
                    // New factory preset (added in this version), install it
                    try? savePresetWithoutReload(factoryPreset)
                }
            }
            // When !needsReinstall: do nothing - preserve user's presets
        }

        if needsReinstall {
            UserDefaults.standard.set(Self.factoryPresetVersion, forKey: Self.factoryVersionKey)
        }

        // Reload once after all factory presets are saved
        loadAllPresets()
    }
}