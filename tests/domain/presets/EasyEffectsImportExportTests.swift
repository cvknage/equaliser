import XCTest
@testable import Equaliser

final class EasyEffectsImportExportTests: XCTestCase {
    // MARK: - Import Basic Tests

    func testImport_basicPreset() throws {
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "input-gain": 0.0,
                    "output-gain": 0.0,
                    "left": {
                        "band0": {
                            "frequency": 1000.0,
                            "gain": 3.0,
                            "q": 1.41,
                            "type": "Bell",
                            "mute": false
                        }
                    },
                    "right": {
                        "band0": {
                            "frequency": 1000.0,
                            "gain": 3.0,
                            "q": 1.41,
                            "type": "Bell",
                            "mute": false
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")

        XCTAssertEqual(result.preset.metadata.name, "Test")
        XCTAssertEqual(result.preset.settings.leftBands.count, 1)
        XCTAssertEqual(result.preset.settings.activeBandCount, 1)

        let band = result.preset.settings.leftBands[0]
        XCTAssertEqual(band.frequency, 1000.0)
        XCTAssertEqual(band.gain, 3.0)
        XCTAssertEqual(band.filterType, .parametric)
        XCTAssertFalse(band.bypass)
    }

    func testImport_filterTypeMapping() throws {
        // Test various filter type mappings
        let filterTypeTests: [(String, FilterType)] = [
            ("Bell", .parametric),
            ("Peaking", .parametric),
            ("Lo-pass", .lowPass),
            ("Hi-pass", .highPass),
            ("Lo-shelf", .lowShelf),
            ("Hi-shelf", .highShelf),
            ("Band-pass", .bandPass),
            ("Notch", .notch)
        ]

        for (easyEffectsType, expectedType) in filterTypeTests {
            let json = """
            {
                "output": {
                    "equalizer#0": {
                        "left": {
                            "band0": {
                                "frequency": 1000.0,
                                "gain": 0.0,
                                "q": 1.0,
                                "type": "\(easyEffectsType)",
                                "mute": false
                            }
                        }
                    }
                }
            }
            """.data(using: .utf8)!

            let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")
            XCTAssertEqual(result.preset.settings.leftBands[0].filterType, expectedType,
                           "Filter type '\(easyEffectsType)' should map to \(expectedType)")
        }
    }

    func testImport_qConversion() throws {
        // Q = 1.41 should convert to approximately 1.0 octave bandwidth
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "left": {
                        "band0": {
                            "frequency": 1000.0,
                            "gain": 0.0,
                            "q": 1.41,
                            "type": "Bell",
                            "mute": false
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")
        let q = result.preset.settings.leftBands[0].q

        // Q should be preserved from the import
        XCTAssertEqual(q, 1.41, accuracy: 0.01)
    }

    func testImport_multipleBands() throws {
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "left": {
                        "band0": { "frequency": 100.0, "gain": -3.0, "q": 1.0, "type": "Bell", "mute": false },
                        "band1": { "frequency": 1000.0, "gain": 0.0, "q": 1.41, "type": "Bell", "mute": false },
                        "band2": { "frequency": 10000.0, "gain": 2.0, "q": 2.0, "type": "Bell", "mute": false }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")

        XCTAssertEqual(result.preset.settings.leftBands.count, 3)
        XCTAssertEqual(result.preset.settings.activeBandCount, 3)

        // Verify order is preserved
        XCTAssertEqual(result.preset.settings.leftBands[0].frequency, 100.0)
        XCTAssertEqual(result.preset.settings.leftBands[1].frequency, 1000.0)
        XCTAssertEqual(result.preset.settings.leftBands[2].frequency, 10000.0)
    }

    func testImport_muteToBypass() throws {
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "left": {
                        "band0": { "frequency": 1000.0, "gain": 0.0, "q": 1.0, "type": "Bell", "mute": true }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")

        XCTAssertTrue(result.preset.settings.leftBands[0].bypass)
    }

    func testImport_inputOutputGain() throws {
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "input-gain": -3.0,
                    "output-gain": 2.0,
                    "left": {
                        "band0": { "frequency": 1000.0, "gain": 0.0, "q": 1.0, "type": "Bell", "mute": false }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")

        XCTAssertEqual(result.preset.settings.inputGain, -3.0)
        XCTAssertEqual(result.preset.settings.outputGain, 2.0)
    }

    func testImport_missingEqualizerSection_throws() {
        let json = """
        {
            "output": {
                "compressor": {}
            }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try EasyEffectsImporter.importPreset(from: json, name: "Test")) { error in
            guard case EasyEffectsImportError.missingEqualizerSection = error else {
                XCTFail("Expected missingEqualizerSection error")
                return
            }
        }
    }

    func testImport_invalidJSON_throws() {
        let invalidJSON = "not valid json".data(using: .utf8)!

        XCTAssertThrowsError(try EasyEffectsImporter.importPreset(from: invalidJSON, name: "Test")) { error in
            guard case EasyEffectsImportError.invalidJSON = error else {
                XCTFail("Expected invalidJSON error")
                return
            }
        }
    }

    // MARK: - Export Tests

    func testExport_producesValidJSON() throws {
        let preset = Preset(
            metadata: PresetMetadata(name: "Export Test"),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: 0,
                outputGain: 0,
                activeBandCount: 1,
                leftBands: [PresetBand(frequency: 1000, q: 1.41, gain: 3.0, filterType: .parametric, bypass: false)],
                rightBands: [PresetBand(frequency: 1000, q: 1.41, gain: 3.0, filterType: .parametric, bypass: false)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["output"])
    }

    func testExport_qPreserved() throws {
        // Q is stored natively, so it should round-trip unchanged
        let preset = Preset(
            metadata: PresetMetadata(name: "Test"),
            settings: PresetSettings(
                activeBandCount: 1,
                leftBands: [PresetBand(frequency: 1000, q: 1.41, gain: 0, filterType: .parametric, bypass: false)],
                rightBands: [PresetBand(frequency: 1000, q: 1.41, gain: 0, filterType: .parametric, bypass: false)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Navigate to the Q value
        let output = json["output"] as! [String: Any]
        let equalizer = output["equalizer#0"] as! [String: Any]
        let left = equalizer["left"] as! [String: Any]
        let band0 = left["band0"] as! [String: Any]
        let q = band0["q"] as! Double

        // Q should be preserved exactly
        XCTAssertEqual(q, 1.41, accuracy: 0.01)
    }

    func testExport_filterTypeMapping() throws {
        let filterTypeMappings: [(FilterType, String)] = [
            (.parametric, "Bell"),
            (.lowPass, "Lo-pass"),
            (.highPass, "Hi-pass"),
            (.lowShelf, "Lo-shelf"),
            (.highShelf, "Hi-shelf"),
            (.bandPass, "Band-pass"),
            (.notch, "Notch")
        ]

        for (filterType, expectedString) in filterTypeMappings {
            let preset = Preset(
                metadata: PresetMetadata(name: "Test"),
                settings: PresetSettings(
                    activeBandCount: 1,
                    leftBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: filterType, bypass: false)],
                    rightBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: filterType, bypass: false)]
                )
            )

            let data = try EasyEffectsExporter.export(preset)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            let output = json["output"] as! [String: Any]
            let equalizer = output["equalizer#0"] as! [String: Any]
            let left = equalizer["left"] as! [String: Any]
            let band0 = left["band0"] as! [String: Any]
            let typeString = band0["type"] as! String

            XCTAssertEqual(typeString, expectedString, "Filter type \(filterType) should export as '\(expectedString)'")
        }
    }

    func testExport_bypassToMute() throws {
        let preset = Preset(
            metadata: PresetMetadata(name: "Test"),
            settings: PresetSettings(
                activeBandCount: 1,
                leftBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: true)],
                rightBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: true)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["output"] as! [String: Any]
        let equalizer = output["equalizer#0"] as! [String: Any]
        let left = equalizer["left"] as! [String: Any]
        let band0 = left["band0"] as! [String: Any]
        let mute = band0["mute"] as! Bool

        XCTAssertTrue(mute)
    }

    func testExport_inputOutputGain() throws {
        let preset = Preset(
            metadata: PresetMetadata(name: "Test"),
            settings: PresetSettings(
                inputGain: -2.0,
                outputGain: 3.0,
                activeBandCount: 1,
                leftBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: false)],
                rightBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: false)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["output"] as! [String: Any]
        let equalizer = output["equalizer#0"] as! [String: Any]
        let inputGain = equalizer["input-gain"] as! Double
        let outputGain = equalizer["output-gain"] as! Double

        XCTAssertEqual(inputGain, -2.0)
        XCTAssertEqual(outputGain, 3.0)
    }

    // MARK: - Round-Trip Tests

    func testExportImport_roundTrip() throws {
        let originalBands = [
            PresetBand(frequency: 60, q: 0.8, gain: 4.0, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 250, q: 1.0, gain: -2.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 0.67, gain: 0, filterType: .parametric, bypass: true),
            PresetBand(frequency: 4000, q: 1.2, gain: 3.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 1.5, gain: 2.0, filterType: .highShelf, bypass: false)
        ]

        let original = Preset(
            metadata: PresetMetadata(name: "Round Trip Test"),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -1.5,
                outputGain: 2.0,
                activeBandCount: 5,
                leftBands: originalBands,
                rightBands: originalBands
            )
        )

        // Export to EasyEffects format
        let exportedData = try EasyEffectsExporter.export(original)

        // Import back
        let importResult = try EasyEffectsImporter.importPreset(from: exportedData, name: original.metadata.name)
        let imported = importResult.preset

        // Verify settings
        XCTAssertEqual(imported.settings.inputGain, original.settings.inputGain, accuracy: 0.01)
        XCTAssertEqual(imported.settings.outputGain, original.settings.outputGain, accuracy: 0.01)
        XCTAssertEqual(imported.settings.activeBandCount, original.settings.activeBandCount)

        // Verify each left band
        for (index, importedBand) in imported.settings.leftBands.enumerated() {
            let originalBand = original.settings.leftBands[index]

            XCTAssertEqual(importedBand.frequency, originalBand.frequency, accuracy: 0.01,
                           "Band \(index) frequency mismatch")
            XCTAssertEqual(importedBand.gain, originalBand.gain, accuracy: 0.01,
                           "Band \(index) gain mismatch")
            XCTAssertEqual(importedBand.filterType, originalBand.filterType,
                           "Band \(index) filter type mismatch")
            XCTAssertEqual(importedBand.bypass, originalBand.bypass,
                           "Band \(index) bypass mismatch")

            // Q may have slight rounding due to conversion
            XCTAssertEqual(importedBand.q, originalBand.q, accuracy: 0.02,
                           "Band \(index) q mismatch")
        }
    }

    func testExportImport_roundTrip_qValues() throws {
        // Test specific Q values that should round-trip accurately
        let testQValues: [Float] = [0.707, 1.0, 1.41, 2.0, 4.36]

        for q in testQValues {
            let preset = Preset(
                metadata: PresetMetadata(name: "Q Test"),
                settings: PresetSettings(
                    activeBandCount: 1,
                    leftBands: [PresetBand(frequency: 1000, q: q, gain: 0, filterType: .parametric, bypass: false)],
                    rightBands: [PresetBand(frequency: 1000, q: q, gain: 0, filterType: .parametric, bypass: false)]
                )
            )

            let exportedData = try EasyEffectsExporter.export(preset)
            let importResult = try EasyEffectsImporter.importPreset(from: exportedData, name: "Q Test")

            let importedQ = importResult.preset.settings.leftBands[0].q

            XCTAssertEqual(importedQ, q, accuracy: 0.02, "Q value \(q) failed round-trip")
        }
    }

    // MARK: - Filename Tests

    func testExporter_fileExtension() {
        XCTAssertEqual(EasyEffectsExporter.fileExtension, "json")
    }

    func testExporter_filename() {
        let preset = Preset(
            metadata: PresetMetadata(name: "My Preset"),
            settings: PresetSettings()
        )

        XCTAssertEqual(EasyEffectsExporter.filename(for: preset), "My Preset.json")
    }

    func testExporter_filename_sanitizesSpecialCharacters() {
        let preset = Preset(
            metadata: PresetMetadata(name: "Test/Preset:Name"),
            settings: PresetSettings()
        )

        XCTAssertEqual(EasyEffectsExporter.filename(for: preset), "Test-Preset-Name.json")
    }

    // MARK: - Split Channel Tests

    func testImport_splitChannelsFalse_importsAsLinked() throws {
        // Preset with split-channels: false should import as linked mode
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "input-gain": 0.0,
                    "output-gain": 0.0,
                    "split-channels": false,
                    "left": {
                        "band0": { "frequency": 1000.0, "gain": 3.0, "q": 1.41, "type": "Bell", "mute": false }
                    },
                    "right": {
                        "band0": { "frequency": 1000.0, "gain": 3.0, "q": 1.41, "type": "Bell", "mute": false }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")

        XCTAssertEqual(result.preset.settings.channelMode, "linked")
        // Both channels should have the same bands (copied from left)
        XCTAssertEqual(result.preset.settings.leftBands.count, 1)
        XCTAssertEqual(result.preset.settings.rightBands.count, 1)
        XCTAssertEqual(result.preset.settings.leftBands[0].frequency, 1000.0)
        XCTAssertEqual(result.preset.settings.rightBands[0].frequency, 1000.0)
    }

    func testImport_splitChannelsTrue_importsAsStereo() throws {
        // Preset with split-channels: true should import as stereo mode with different L/R
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "input-gain": 0.0,
                    "output-gain": 0.0,
                    "split-channels": true,
                    "left": {
                        "band0": { "frequency": 100.0, "gain": 4.0, "q": 1.0, "type": "Bell", "mute": false },
                        "band1": { "frequency": 1000.0, "gain": 2.0, "q": 1.41, "type": "Bell", "mute": false }
                    },
                    "right": {
                        "band0": { "frequency": 200.0, "gain": -2.0, "q": 1.0, "type": "Bell", "mute": false },
                        "band1": { "frequency": 2000.0, "gain": 1.0, "q": 1.41, "type": "Bell", "mute": false }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Stereo Test")

        XCTAssertEqual(result.preset.settings.channelMode, "stereo")
        XCTAssertEqual(result.preset.settings.leftBands.count, 2)
        XCTAssertEqual(result.preset.settings.rightBands.count, 2)

        // Left channel
        XCTAssertEqual(result.preset.settings.leftBands[0].frequency, 100.0)
        XCTAssertEqual(result.preset.settings.leftBands[0].gain, 4.0)
        XCTAssertEqual(result.preset.settings.leftBands[1].frequency, 1000.0)

        // Right channel
        XCTAssertEqual(result.preset.settings.rightBands[0].frequency, 200.0)
        XCTAssertEqual(result.preset.settings.rightBands[0].gain, -2.0)
        XCTAssertEqual(result.preset.settings.rightBands[1].frequency, 2000.0)
    }

    func testImport_noSplitChannelsKey_importsAsLinked() throws {
        // Preset without split-channels key should default to linked mode
        let json = """
        {
            "output": {
                "equalizer#0": {
                    "input-gain": 0.0,
                    "output-gain": 0.0,
                    "left": {
                        "band0": { "frequency": 500.0, "gain": 0.0, "q": 1.0, "type": "Bell", "mute": false }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let result = try EasyEffectsImporter.importPreset(from: json, name: "Test")

        XCTAssertEqual(result.preset.settings.channelMode, "linked")
        // Right bands should be copied from left
        XCTAssertEqual(result.preset.settings.rightBands.count, 1)
        XCTAssertEqual(result.preset.settings.rightBands[0].frequency, 500.0)
    }

    func testExport_linkedMode_setsSplitChannelsFalse() throws {
        let preset = Preset(
            metadata: PresetMetadata(name: "Linked Test"),
            settings: PresetSettings(
                activeBandCount: 1,
                channelMode: "linked",
                leftBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: false)],
                rightBands: [PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: false)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["output"] as! [String: Any]
        let equalizer = output["equalizer#0"] as! [String: Any]
        let splitChannels = equalizer["split-channels"] as! Bool

        XCTAssertFalse(splitChannels)
    }

    func testExport_stereoMode_setsSplitChannelsTrue() throws {
        let preset = Preset(
            metadata: PresetMetadata(name: "Stereo Test"),
            settings: PresetSettings(
                activeBandCount: 1,
                channelMode: "stereo",
                leftBands: [PresetBand(frequency: 100, q: 1.0, gain: 4.0, filterType: .parametric, bypass: false)],
                rightBands: [PresetBand(frequency: 200, q: 1.0, gain: -2.0, filterType: .parametric, bypass: false)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let output = json["output"] as! [String: Any]
        let equalizer = output["equalizer#0"] as! [String: Any]
        let splitChannels = equalizer["split-channels"] as! Bool

        XCTAssertTrue(splitChannels)

        // Verify left and right bands are different
        let left = equalizer["left"] as! [String: Any]
        let right = equalizer["right"] as! [String: Any]
        let leftBand0 = left["band0"] as! [String: Any]
        let rightBand0 = right["band0"] as! [String: Any]

        XCTAssertEqual(leftBand0["frequency"] as? Double, 100.0)
        XCTAssertEqual(rightBand0["frequency"] as? Double, 200.0)
        XCTAssertEqual(leftBand0["gain"] as? Double, 4.0)
        XCTAssertEqual(rightBand0["gain"] as? Double, -2.0)
    }

    func testExport_stereoRoundTrip_preservesDifferentChannels() throws {
        // Create a stereo preset with different L/R bands
        let original = Preset(
            metadata: PresetMetadata(name: "Stereo Round Trip"),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -2.0,
                outputGain: 1.0,
                activeBandCount: 2,
                channelMode: "stereo",
                leftBands: [
                    PresetBand(frequency: 100, q: 1.0, gain: 4.0, filterType: .lowShelf, bypass: false),
                    PresetBand(frequency: 8000, q: 1.41, gain: -3.0, filterType: .highShelf, bypass: false),
                ],
                rightBands: [
                    PresetBand(frequency: 200, q: 0.83, gain: 2.0, filterType: .parametric, bypass: false),
                    PresetBand(frequency: 6000, q: 1.2, gain: -1.0, filterType: .highPass, bypass: false),
                ]
            )
        )

        // Export to EasyEffects format
        let exportedData = try EasyEffectsExporter.export(original)

        // Import back
        let importResult = try EasyEffectsImporter.importPreset(from: exportedData, name: original.metadata.name)
        let imported = importResult.preset

        // Verify channel mode is stereo
        XCTAssertEqual(imported.settings.channelMode, "stereo")

        // Verify left channel preserved
        XCTAssertEqual(imported.settings.leftBands.count, 2)
        XCTAssertEqual(imported.settings.leftBands[0].frequency, 100.0)
        XCTAssertEqual(imported.settings.leftBands[0].gain, 4.0)
        XCTAssertEqual(imported.settings.leftBands[0].filterType, .lowShelf)
        XCTAssertEqual(imported.settings.leftBands[1].frequency, 8000.0)

        // Verify right channel preserved
        XCTAssertEqual(imported.settings.rightBands.count, 2)
        XCTAssertEqual(imported.settings.rightBands[0].frequency, 200.0)
        XCTAssertEqual(imported.settings.rightBands[0].gain, 2.0)
        XCTAssertEqual(imported.settings.rightBands[1].frequency, 6000.0)
    }
}
