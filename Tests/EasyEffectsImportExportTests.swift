import AVFoundation
import XCTest
@testable import EqualiserApp

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
        XCTAssertEqual(result.preset.settings.bands.count, 1)
        XCTAssertEqual(result.preset.settings.activeBandCount, 1)

        let band = result.preset.settings.bands[0]
        XCTAssertEqual(band.frequency, 1000.0)
        XCTAssertEqual(band.gain, 3.0)
        XCTAssertEqual(band.filterType, .parametric)
        XCTAssertFalse(band.bypass)
    }

    func testImport_filterTypeMapping() throws {
        // Test various filter type mappings
        let filterTypeTests: [(String, AVAudioUnitEQFilterType)] = [
            ("Bell", .parametric),
            ("Peaking", .parametric),
            ("Lo-pass", .lowPass),
            ("Hi-pass", .highPass),
            ("Lo-shelf", .lowShelf),
            ("Hi-shelf", .highShelf),
            ("Band-pass", .bandPass),
            ("Notch", .bandStop)
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
            XCTAssertEqual(result.preset.settings.bands[0].filterType, expectedType,
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
        let bandwidth = result.preset.settings.bands[0].bandwidth

        // Q = 1.41 ≈ 1.0 octave
        XCTAssertEqual(bandwidth, 1.0, accuracy: 0.1)
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

        XCTAssertEqual(result.preset.settings.bands.count, 3)
        XCTAssertEqual(result.preset.settings.activeBandCount, 3)

        // Verify order is preserved
        XCTAssertEqual(result.preset.settings.bands[0].frequency, 100.0)
        XCTAssertEqual(result.preset.settings.bands[1].frequency, 1000.0)
        XCTAssertEqual(result.preset.settings.bands[2].frequency, 10000.0)
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

        XCTAssertTrue(result.preset.settings.bands[0].bypass)
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
                bands: [PresetBand(frequency: 1000, bandwidth: 1.0, gain: 3.0, filterType: .parametric, bypass: false)]
            )
        )

        let data = try EasyEffectsExporter.export(preset)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["output"])
    }

    func testExport_bandwidthToQConversion() throws {
        // 1.0 octave bandwidth should convert to Q ≈ 1.41
        let preset = Preset(
            metadata: PresetMetadata(name: "Test"),
            settings: PresetSettings(
                activeBandCount: 1,
                bands: [PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false)]
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

        // 1.0 octave ≈ Q of 1.41
        XCTAssertEqual(q, 1.41, accuracy: 0.1)
    }

    func testExport_filterTypeMapping() throws {
        let filterTypeMappings: [(AVAudioUnitEQFilterType, String)] = [
            (.parametric, "Bell"),
            (.lowPass, "Lo-pass"),
            (.highPass, "Hi-pass"),
            (.lowShelf, "Lo-shelf"),
            (.highShelf, "Hi-shelf"),
            (.bandPass, "Band-pass"),
            (.bandStop, "Notch")
        ]

        for (filterType, expectedString) in filterTypeMappings {
            let preset = Preset(
                metadata: PresetMetadata(name: "Test"),
                settings: PresetSettings(
                    activeBandCount: 1,
                    bands: [PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: filterType, bypass: false)]
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
                bands: [PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: true)]
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
                bands: [PresetBand(frequency: 1000, bandwidth: 1.0, gain: 0, filterType: .parametric, bypass: false)]
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
            PresetBand(frequency: 60, bandwidth: 0.8, gain: 4.0, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 250, bandwidth: 1.0, gain: -2.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, bandwidth: 0.67, gain: 0, filterType: .parametric, bypass: true),
            PresetBand(frequency: 4000, bandwidth: 1.2, gain: 3.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, bandwidth: 1.5, gain: 2.0, filterType: .highShelf, bypass: false)
        ]

        let original = Preset(
            metadata: PresetMetadata(name: "Round Trip Test"),
            settings: PresetSettings(
                globalBypass: false,
                inputGain: -1.5,
                outputGain: 2.0,
                activeBandCount: 5,
                bands: originalBands
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

        // Verify each band
        for (index, importedBand) in imported.settings.bands.enumerated() {
            let originalBand = original.settings.bands[index]

            XCTAssertEqual(importedBand.frequency, originalBand.frequency, accuracy: 0.01,
                           "Band \(index) frequency mismatch")
            XCTAssertEqual(importedBand.gain, originalBand.gain, accuracy: 0.01,
                           "Band \(index) gain mismatch")
            XCTAssertEqual(importedBand.filterType, originalBand.filterType,
                           "Band \(index) filter type mismatch")
            XCTAssertEqual(importedBand.bypass, originalBand.bypass,
                           "Band \(index) bypass mismatch")

            // Bandwidth may have slight rounding due to Q conversion
            XCTAssertEqual(importedBand.bandwidth, originalBand.bandwidth, accuracy: 0.05,
                           "Band \(index) bandwidth mismatch")
        }
    }

    func testExportImport_roundTrip_qValues() throws {
        // Test specific Q values that should round-trip accurately
        let testQValues: [Float] = [0.707, 1.0, 1.41, 2.0, 4.36]

        for q in testQValues {
            let bandwidth = BandwidthConverter.qToBandwidth(q)

            let preset = Preset(
                metadata: PresetMetadata(name: "Q Test"),
                settings: PresetSettings(
                    activeBandCount: 1,
                    bands: [PresetBand(frequency: 1000, bandwidth: bandwidth, gain: 0, filterType: .parametric, bypass: false)]
                )
            )

            let exportedData = try EasyEffectsExporter.export(preset)
            let importResult = try EasyEffectsImporter.importPreset(from: exportedData, name: "Q Test")

            let importedBandwidth = importResult.preset.settings.bands[0].bandwidth
            let roundTrippedQ = BandwidthConverter.bandwidthToQ(importedBandwidth)

            XCTAssertEqual(roundTrippedQ, q, accuracy: 0.02, "Q value \(q) failed round-trip")
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
}
