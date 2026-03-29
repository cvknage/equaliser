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
    /// They must decode successfully and default to linked mode.
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
        XCTAssertNil(preset.settings.rightBands)
        XCTAssertEqual(preset.settings.activeBandCount, 3)
        XCTAssertEqual(preset.settings.bands.count, 3)
        XCTAssertEqual(preset.settings.bands[0].frequency, 60.0)
        XCTAssertEqual(preset.settings.bands[0].gain, 6.0)
        XCTAssertEqual(preset.settings.bands[0].filterType, .parametric)
        XCTAssertEqual(preset.settings.bands[2].bypass, true)
        XCTAssertEqual(preset.settings.inputGain, -4.0)
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
        XCTAssertEqual(preset.settings.bands[0].gain, 3.0)
    }

    /// A preset with `channelMode` but no `rightBands` (linked stereo save) must decode.
    func testLegacyPreset_decodesWithChannelModeButNoRightBands() throws {
        let json = """
        {
            "version": 1,
            "metadata": {
                "name": "Linked With Mode",
                "createdAt": 0,
                "modifiedAt": 0
            },
            "settings": {
                "globalBypass": false,
                "inputGain": 0.0,
                "outputGain": 0.0,
                "activeBandCount": 1,
                "bands": [
                    {"frequency": 1000.0, "bandwidth": 0.67, "gain": 0.0, "filterType": 0, "bypass": false}
                ],
                "channelMode": "linked"
            }
        }
        """.data(using: .utf8)!

        let preset = try decoder.decode(Preset.self, from: json)

        XCTAssertEqual(preset.settings.channelMode, "linked")
        XCTAssertNil(preset.settings.rightBands)
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

        XCTAssertEqual(preset.settings.bands[0].filterType, .lowShelf)
        XCTAssertEqual(preset.settings.bands[1].filterType, .highShelf)
        XCTAssertEqual(preset.settings.bands[2].filterType, .notch)
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

        XCTAssertEqual(preset.settings.bands[0].filterType, .parametric)
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
                bands: [
                    PresetBand(frequency: 100.0, bandwidth: 1.0, gain: 4.0, filterType: .lowShelf),
                    PresetBand(frequency: 8000.0, bandwidth: 0.5, gain: -3.0, filterType: .highShelf),
                ],
                channelMode: "stereo",
                rightBands: [
                    PresetBand(frequency: 200.0, bandwidth: 1.2, gain: 2.0, filterType: .parametric),
                    PresetBand(frequency: 6000.0, bandwidth: 0.8, gain: -1.0, filterType: .highPass),
                ]
            )
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.settings.channelMode, "stereo")
        XCTAssertEqual(decoded.settings.bands.count, 2)
        XCTAssertEqual(decoded.settings.bands[0].filterType, .lowShelf)
        XCTAssertEqual(decoded.settings.bands[1].filterType, .highShelf)
        XCTAssertEqual(decoded.settings.rightBands?.count, 2)
        XCTAssertEqual(decoded.settings.rightBands?[0].frequency, 200.0)
        XCTAssertEqual(decoded.settings.rightBands?[0].filterType, .parametric)
        XCTAssertEqual(decoded.settings.rightBands?[1].filterType, .highPass)
        XCTAssertEqual(decoded.settings.inputGain, -2.0)
        XCTAssertEqual(decoded.settings.outputGain, 1.0)
    }

    /// Linked mode preset round-trips without rightBands.
    func testCurrentPreset_linkedRoundTrip() throws {
        let original = Preset(
            metadata: PresetMetadata(name: "Linked Test", isFactoryPreset: true),
            settings: PresetSettings(
                activeBandCount: 1,
                bands: [
                    PresetBand(frequency: 1000.0, bandwidth: 0.67, gain: 3.0, filterType: .parametric),
                ],
                channelMode: "linked"
            )
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.settings.channelMode, "linked")
        XCTAssertNil(decoded.settings.rightBands)
        XCTAssertEqual(decoded.settings.bands[0].gain, 3.0)
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
                bands: [
                    PresetBand(frequency: 250.0, bandwidth: 1.5, gain: 8.0, filterType: .lowShelf, bypass: false),
                    PresetBand(frequency: 4000.0, bandwidth: 0.5, gain: -4.0, filterType: .highShelf, bypass: true),
                ],
                channelMode: "linked"
            )
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.settings.globalBypass, true)
        XCTAssertEqual(decoded.settings.inputGain, -6.0)
        XCTAssertEqual(decoded.settings.outputGain, 3.0)
        XCTAssertEqual(decoded.settings.activeBandCount, 2)
        XCTAssertEqual(decoded.settings.bands[0].frequency, 250.0)
        XCTAssertEqual(decoded.settings.bands[0].bandwidth, 1.5)
        XCTAssertEqual(decoded.settings.bands[0].gain, 8.0)
        XCTAssertEqual(decoded.settings.bands[0].filterType, .lowShelf)
        XCTAssertFalse(decoded.settings.bands[0].bypass)
        XCTAssertEqual(decoded.settings.bands[1].gain, -4.0)
        XCTAssertEqual(decoded.settings.bands[1].filterType, .highShelf)
        XCTAssertTrue(decoded.settings.bands[1].bypass)
    }
}
