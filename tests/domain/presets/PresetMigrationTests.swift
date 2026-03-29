import XCTest
@testable import Equaliser

/// Tests that preset JSON decodes correctly across format versions.
///
/// The key risk is legacy `.eqpreset` files saved before the custom DSP migration
/// (i.e. before `channelMode` and `rightBands` were added to `PresetSettings`).
/// Those files must load successfully rather than silently disappearing from the preset list.
final class PresetMigrationTests: XCTestCase {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    // MARK: - Legacy Format (pre-channel-mode)

    /// Legacy presets have no `channelMode` or `rightBands` keys.
    /// They must decode successfully and default to linked mode with rightBands copied from left.
    func testLegacyPreset_decodesWithoutChannelMode() throws {
        // JSON that mirrors what the app wrote before the custom DSP migration.
        // No "channelMode" key, no "rightBands" key — exactly as old saves look on disk.
        let json = """
        {
            "version": 1,
            "metadata": {
                "name": "Legacy Bass Boost",
                "createdAt": 0,
                "modifiedAt": 0,
                "isFactoryPreset": false
            },
            "settings": {
                "globalBypass": false,
                "inputGain": -4.0,
                "outputGain": 0.0,
                "activeBandCount": 3,
                "bands": [
                    {"frequency": 60.0, "bandwidth": 1.0, "gain": 6.0, "filterType": 0, "bypass": false},
                    {"frequency": 250.0, "bandwidth": 0.67, "gain": 3.0, "filterType": 0, "bypass": false},
                    {"frequency": 1000.0, "bandwidth": 0.67, "gain": 0.0, "filterType": 0, "bypass": true}
                ]
            }
        }
        """.data(using: .utf8)!

        let preset = try decoder.decode(Preset.self, from: json)

        XCTAssertEqual(preset.metadata.name, "Legacy Bass Boost")
        XCTAssertEqual(preset.settings.channelMode, "linked")
        XCTAssertEqual(preset.settings.activeBandCount, 3)
        XCTAssertEqual(preset.settings.leftBands.count, 3)
        // Legacy preset: rightBands should be copied from leftBands
        XCTAssertEqual(preset.settings.rightBands.count, 3)
        XCTAssertEqual(preset.settings.leftBands[0].frequency, 60.0)
        XCTAssertEqual(preset.settings.leftBands[0].gain, 6.0)
        XCTAssertEqual(preset.settings.leftBands[0].filterType, .parametric)
        XCTAssertEqual(preset.settings.leftBands[2].bypass, true)
        XCTAssertEqual(preset.settings.inputGain, -4.0)
        // Verify rightBands equals leftBands
        for (left, right) in zip(preset.settings.leftBands, preset.settings.rightBands) {
            XCTAssertEqual(left.frequency, right.frequency)
            XCTAssertEqual(left.gain, right.gain)
            XCTAssertEqual(left.q, right.q)
            XCTAssertEqual(left.filterType, right.filterType)
            XCTAssertEqual(left.bypass, right.bypass)
        }
    }

    /// Legacy presets without `isFactoryPreset` in metadata must also decode successfully.
    func testLegacyPreset_decodesWithoutIsFactoryPreset() throws {
        let json = """
        {
            "version": 1,
            "metadata": {
                "name": "Old User Preset",
                "createdAt": 0,
                "modifiedAt": 0
            },
            "settings": {
                "globalBypass": false,
                "inputGain": 0.0,
                "outputGain": 0.0,
                "activeBandCount": 1,
                "bands": [
                    {"frequency": 1000.0, "bandwidth": 0.67, "gain": 3.0, "filterType": 0, "bypass": false}
                ]
            }
        }
        """.data(using: .utf8)!

        let preset = try decoder.decode(Preset.self, from: json)

        XCTAssertEqual(preset.metadata.name, "Old User Preset")
        XCTAssertFalse(preset.metadata.isFactoryPreset)
        XCTAssertEqual(preset.settings.channelMode, "linked")
        XCTAssertEqual(preset.settings.leftBands[0].gain, 3.0)
        // rightBands should be copied from leftBands
        XCTAssertEqual(preset.settings.rightBands[0].gain, 3.0)
    }

    /// New format presets require channelMode, leftBands, and rightBands.
    /// In linked mode, both channels are saved (they're identical).
    func testNewPreset_requiresBothChannels() throws {
        let json = """
        {
            "version": 2,
            "metadata": {
                "name": "Linked Preset",
                "createdAt": 0,
                "modifiedAt": 0
            },
            "settings": {
                "globalBypass": false,
                "inputGain": 0.0,
                "outputGain": 0.0,
                "activeBandCount": 1,
                "channelMode": "linked",
                "leftBands": [
                    {"frequency": 1000.0, "q": 0.67, "gain": 0.0, "filterType": "Bell", "bypass": false}
                ],
                "rightBands": [
                    {"frequency": 1000.0, "q": 0.67, "gain": 0.0, "filterType": "Bell", "bypass": false}
                ]
            }
        }
        """.data(using: .utf8)!

        let preset = try decoder.decode(Preset.self, from: json)

        XCTAssertEqual(preset.settings.channelMode, "linked")
        XCTAssertEqual(preset.settings.leftBands.count, 1)
        XCTAssertEqual(preset.settings.rightBands.count, 1)
        // In linked mode, bands are identical
        XCTAssertEqual(preset.settings.leftBands[0].frequency, preset.settings.rightBands[0].frequency)
    }

    // MARK: - Filter Type Backward Compatibility

    /// All 11 legacy filter type raw values (0–10) must decode to the correct `FilterType`.
    /// Raw values are identical between `AVAudioUnitEQFilterType` and `FilterType`.
    func testLegacyPreset_filterTypeRawValues() throws {
        // filterType 3 = lowShelf, filterType 4 = highShelf, filterType 6 = notch
        let json = """
        {
            "version": 1,
            "metadata": {"name": "Filter Types", "createdAt": 0, "modifiedAt": 0},
            "settings": {
                "globalBypass": false,
                "inputGain": 0.0,
                "outputGain": 0.0,
                "activeBandCount": 3,
                "bands": [
                    {"frequency": 80.0,    "bandwidth": 1.0, "gain":  4.0, "filterType": 3, "bypass": false},
                    {"frequency": 12000.0, "bandwidth": 1.0, "gain": -2.0, "filterType": 4, "bypass": false},
                    {"frequency": 1000.0,  "bandwidth": 1.0, "gain":  0.0, "filterType": 6, "bypass": false}
                ]
            }
        }
        """.data(using: .utf8)!

        let preset = try decoder.decode(Preset.self, from: json)

        XCTAssertEqual(preset.settings.leftBands[0].filterType, .lowShelf)
        XCTAssertEqual(preset.settings.leftBands[1].filterType, .highShelf)
        XCTAssertEqual(preset.settings.leftBands[2].filterType, .notch)
        XCTAssertEqual(preset.settings.channelMode, "linked")
    }

    /// An unknown filter type raw value must fall back to `.parametric` rather than crashing.
    func testLegacyPreset_unknownFilterTypeFallsBackToParametric() throws {
        let json = """
        {
            "version": 1,
            "metadata": {"name": "Bad Filter", "createdAt": 0, "modifiedAt": 0},
            "settings": {
                "globalBypass": false,
                "inputGain": 0.0,
                "outputGain": 0.0,
                "activeBandCount": 1,
                "bands": [
                    {"frequency": 500.0, "bandwidth": 0.67, "gain": 1.0, "filterType": 999, "bypass": false}
                ]
            }
        }
        """.data(using: .utf8)!

        let preset = try decoder.decode(Preset.self, from: json)

        XCTAssertEqual(preset.settings.leftBands[0].filterType, .parametric)
    }

    // MARK: - Current Format Round-Trips

    /// Stereo preset with right bands encodes and decodes without data loss.
    func testCurrentPreset_stereoRoundTrip() throws {
        let original = Preset(
            metadata: PresetMetadata(name: "Stereo Test"),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2.0,
                outputGain: 1.0,
                activeBandCount: 2,
                channelMode: "stereo",
                leftBands: [
                    PresetBand(frequency: 100.0, q: 1.0, gain: 4.0, filterType: .lowShelf),
                    PresetBand(frequency: 8000.0, q: 1.41, gain: -3.0, filterType: .highShelf),
                ],
                rightBands: [
                    PresetBand(frequency: 200.0, q: 0.83, gain: 2.0, filterType: .parametric),
                    PresetBand(frequency: 6000.0, q: 1.2, gain: -1.0, filterType: .highPass),
                ]
            )
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.settings.channelMode, "stereo")
        XCTAssertEqual(decoded.settings.leftBands.count, 2)
        XCTAssertEqual(decoded.settings.leftBands[0].filterType, .lowShelf)
        XCTAssertEqual(decoded.settings.leftBands[1].filterType, .highShelf)
        XCTAssertEqual(decoded.settings.rightBands.count, 2)
        XCTAssertEqual(decoded.settings.rightBands[0].frequency, 200.0)
        XCTAssertEqual(decoded.settings.rightBands[0].filterType, .parametric)
        XCTAssertEqual(decoded.settings.rightBands[1].filterType, .highPass)
        XCTAssertEqual(decoded.settings.inputGain, -2.0)
        XCTAssertEqual(decoded.settings.outputGain, 1.0)
    }

    /// Linked mode preset round-trips with both channels having identical bands.
    func testCurrentPreset_linkedRoundTrip() throws {
        let original = Preset(
            metadata: PresetMetadata(name: "Linked Test", isFactoryPreset: true),
            settings: PresetSettings(
                activeBandCount: 1,
                channelMode: "linked",
                leftBands: [
                    PresetBand(frequency: 1000.0, q: 1.41, gain: 3.0, filterType: .parametric),
                ],
                rightBands: [
                    PresetBand(frequency: 1000.0, q: 1.41, gain: 3.0, filterType: .parametric),
                ]
            )
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.settings.channelMode, "linked")
        XCTAssertEqual(decoded.settings.rightBands.count, 1)
        XCTAssertEqual(decoded.settings.leftBands[0].gain, 3.0)
        XCTAssertTrue(decoded.metadata.isFactoryPreset)
    }

    /// All settings fields survive a full encode/decode round-trip.
    func testCurrentPreset_allFieldsRoundTrip() throws {
        let original = Preset(
            metadata: PresetMetadata(name: "Full Round Trip", isFactoryPreset: false),
            settings: PresetSettings(
                globalBypass: true,
                inputGain: -6.0,
                outputGain: 3.0,
                activeBandCount: 2,
                channelMode: "linked",
                leftBands: [
                    PresetBand(frequency: 250.0, q: 0.83, gain: 8.0, filterType: .lowShelf, bypass: false),
                    PresetBand(frequency: 4000.0, q: 1.41, gain: -4.0, filterType: .highShelf, bypass: true),
                ],
                rightBands: [
                    PresetBand(frequency: 250.0, q: 0.83, gain: 8.0, filterType: .lowShelf, bypass: false),
                    PresetBand(frequency: 4000.0, q: 1.41, gain: -4.0, filterType: .highShelf, bypass: true),
                ]
            )
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.settings.globalBypass, true)
        XCTAssertEqual(decoded.settings.inputGain, -6.0)
        XCTAssertEqual(decoded.settings.outputGain, 3.0)
        XCTAssertEqual(decoded.settings.activeBandCount, 2)
        XCTAssertEqual(decoded.settings.leftBands[0].frequency, 250.0)
        XCTAssertEqual(decoded.settings.leftBands[0].q, 0.83)
        XCTAssertEqual(decoded.settings.leftBands[0].gain, 8.0)
        XCTAssertEqual(decoded.settings.leftBands[0].filterType, .lowShelf)
        XCTAssertFalse(decoded.settings.leftBands[0].bypass)
        XCTAssertEqual(decoded.settings.leftBands[1].gain, -4.0)
        XCTAssertEqual(decoded.settings.leftBands[1].filterType, .highShelf)
        XCTAssertTrue(decoded.settings.leftBands[1].bypass)
    }
}
