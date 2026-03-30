import XCTest
@testable import Equaliser

final class PresetCodableTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // MARK: - EQBandConfiguration Tests

    func testEQBandConfiguration_roundTrip() throws {
        let original = EQBandConfiguration(
            frequency: 1000.0,
            q: 1.41,
            gain: 3.5,
            filterType: .parametric,
            bypass: false
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(EQBandConfiguration.self, from: data)

        XCTAssertEqual(decoded.frequency, original.frequency)
        XCTAssertEqual(decoded.q, original.q)
        XCTAssertEqual(decoded.gain, original.gain)
        XCTAssertEqual(decoded.filterType, original.filterType)
        XCTAssertEqual(decoded.bypass, original.bypass)
    }

    func testEQBandConfiguration_allFilterTypes() throws {
        let filterTypes: [FilterType] = [
            .parametric,
            .lowPass,
            .highPass,
            .resonantLowPass,
            .resonantHighPass,
            .bandPass,
            .notch,
            .lowShelf,
            .highShelf,
            .resonantLowShelf,
            .resonantHighShelf
        ]

        for filterType in filterTypes {
            let band = EQBandConfiguration(
                frequency: 1000.0,
                q: 1.0,
                gain: 0,
                filterType: filterType,
                bypass: false
            )

            let data = try encoder.encode(band)
            let decoded = try decoder.decode(EQBandConfiguration.self, from: data)

            XCTAssertEqual(decoded.filterType, filterType, "Filter type \(filterType.rawValue) failed round-trip")
        }
    }

    func testEQBandConfiguration_unknownFilterType() throws {
        // Simulate decoding with an unknown filter type raw value
        let json = """
        {
            "frequency": 1000.0,
            "q": 1.0,
            "gain": 0.0,
            "filterType": 999,
            "bypass": false
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(EQBandConfiguration.self, from: json)

        // Unknown filter types should fall back to parametric
        XCTAssertEqual(decoded.filterType, .parametric)
        XCTAssertEqual(decoded.frequency, 1000.0)
        XCTAssertEqual(decoded.q, 1.0)
        XCTAssertEqual(decoded.gain, 0.0)
        XCTAssertFalse(decoded.bypass)
    }

    func testEQBandConfiguration_parametricFactory() {
        let band = EQBandConfiguration.parametric(frequency: 440.0)

        XCTAssertEqual(band.frequency, 440.0)
        XCTAssertEqual(band.q, EQConfiguration.defaultQ)
        XCTAssertEqual(band.gain, 0)
        XCTAssertEqual(band.filterType, .parametric)
        XCTAssertFalse(band.bypass)
    }

    func testEQBandConfiguration_parametricFactory_customQ() {
        let band = EQBandConfiguration.parametric(frequency: 440.0, q: 2.0)

        XCTAssertEqual(band.frequency, 440.0)
        XCTAssertEqual(band.q, 2.0)
    }

    // MARK: - PresetBand Tests

    func testPresetBand_roundTrip() throws {
        let original = PresetBand(
            frequency: 2000.0,
            q: 1.0,
            gain: -6.0,
            filterType: .highShelf,
            bypass: true
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PresetBand.self, from: data)

        XCTAssertEqual(decoded.frequency, original.frequency)
        XCTAssertEqual(decoded.q, original.q)
        XCTAssertEqual(decoded.gain, original.gain)
        XCTAssertEqual(decoded.filterType, original.filterType)
        XCTAssertEqual(decoded.bypass, original.bypass)
    }

    func testPresetBand_unknownFilterType() throws {
        // v2 format: filterType as string (abbreviation), unknown types fall back to parametric
        let json = """
        {
            "frequency": 500.0,
            "q": 0.5,
            "gain": 2.0,
            "filterType": "Unknown",
            "bypass": false
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(PresetBand.self, from: json)

        // Unknown filter types should fall back to parametric
        XCTAssertEqual(decoded.filterType, .parametric)
        XCTAssertEqual(decoded.frequency, 500.0)
        XCTAssertEqual(decoded.q, 0.5)
        XCTAssertEqual(decoded.gain, 2.0)
        XCTAssertFalse(decoded.bypass)
    }

    func testPresetBand_conversionFromEQBandConfiguration() {
        let eqBand = EQBandConfiguration(
            frequency: 3000.0,
            q: 0.8,
            gain: 4.0,
            filterType: .lowShelf,
            bypass: true
        )

        let presetBand = PresetBand(from: eqBand)

        XCTAssertEqual(presetBand.frequency, eqBand.frequency)
        XCTAssertEqual(presetBand.q, eqBand.q)
        XCTAssertEqual(presetBand.gain, eqBand.gain)
        XCTAssertEqual(presetBand.filterType, eqBand.filterType)
        XCTAssertEqual(presetBand.bypass, eqBand.bypass)
    }

    func testPresetBand_conversionToEQBandConfiguration() {
        let presetBand = PresetBand(
            frequency: 4000.0,
            q: 1.2,
            gain: -2.0,
            filterType: .bandPass,
            bypass: false
        )

        let eqBand = presetBand.toEQBandConfiguration()

        XCTAssertEqual(eqBand.frequency, presetBand.frequency)
        XCTAssertEqual(eqBand.q, presetBand.q)
        XCTAssertEqual(eqBand.gain, presetBand.gain)
        XCTAssertEqual(eqBand.filterType, presetBand.filterType)
        XCTAssertEqual(eqBand.bypass, presetBand.bypass)
    }

    // MARK: - PresetMetadata Tests

    func testPresetMetadata_roundTrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1700000000)
        let modifiedAt = Date(timeIntervalSince1970: 1700001000)

        let original = PresetMetadata(name: "Test Preset", createdAt: createdAt, modifiedAt: modifiedAt, isFactoryPreset: true)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PresetMetadata.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.modifiedAt.timeIntervalSince1970, modifiedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(decoded.isFactoryPreset)
    }

    func testPresetMetadata_defaultTimestamps() {
        let beforeCreation = Date()
        let metadata = PresetMetadata(name: "New Preset")
        let afterCreation = Date()

        XCTAssertEqual(metadata.name, "New Preset")
        XCTAssertFalse(metadata.isFactoryPreset)
        XCTAssertGreaterThanOrEqual(metadata.createdAt, beforeCreation)
        XCTAssertLessThanOrEqual(metadata.createdAt, afterCreation)
        XCTAssertGreaterThanOrEqual(metadata.modifiedAt, beforeCreation)
        XCTAssertLessThanOrEqual(metadata.modifiedAt, afterCreation)
    }

    func testPresetMetadata_decodesMissingFactoryFlag() throws {
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {
            "name": "Legacy",
            "createdAt": "2023-11-11T00:00:00Z",
            "modifiedAt": "2023-11-12T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(PresetMetadata.self, from: json)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertFalse(decoded.isFactoryPreset)
        decoder.dateDecodingStrategy = .deferredToDate
    }

    // MARK: - PresetSettings Tests

    func testPresetSettings_roundTrip() throws {
        let leftBands = [
            PresetBand(frequency: 100, q: 1.0, gain: -3.0, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 1000, q: 1.41, gain: 2.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 10000, q: 1.0, gain: -1.0, filterType: .highShelf, bypass: true)
        ]

        let original = PresetSettings(
            globalBypass: true,
            inputGain: -3.0,
            outputGain: 1.5,
            leftBands: leftBands,
            rightBands: leftBands
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PresetSettings.self, from: data)

        XCTAssertEqual(decoded.globalBypass, original.globalBypass)
        XCTAssertEqual(decoded.inputGain, original.inputGain)
        XCTAssertEqual(decoded.outputGain, original.outputGain)
        // activeBandCount is derived from leftBands.count
        XCTAssertEqual(decoded.activeBandCount, leftBands.count)
        XCTAssertEqual(decoded.leftBands.count, original.leftBands.count)
        XCTAssertEqual(decoded.rightBands.count, original.rightBands.count)
    }

    func testPresetSettings_defaultValues() {
        let settings = PresetSettings()

        XCTAssertFalse(settings.globalBypass)
        XCTAssertEqual(settings.inputGain, 0)
        XCTAssertEqual(settings.outputGain, 0)
        // activeBandCount is derived from leftBands.count (empty = 0)
        XCTAssertEqual(settings.activeBandCount, 0)
        XCTAssertTrue(settings.leftBands.isEmpty)
        XCTAssertTrue(settings.rightBands.isEmpty)
        XCTAssertEqual(settings.channelMode, "linked")
    }

    // MARK: - Preset Tests

    func testPreset_roundTrip_fullPreset() throws {
        let leftBands = [
            PresetBand(frequency: 60, q: 1.2, gain: 4.0, filterType: .lowShelf, bypass: false),
            PresetBand(frequency: 250, q: 1.0, gain: -2.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 1000, q: 1.0, gain: 0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 4000, q: 1.41, gain: 3.0, filterType: .parametric, bypass: false),
            PresetBand(frequency: 12000, q: 0.83, gain: 2.0, filterType: .highShelf, bypass: false)
        ]

        let settings = PresetSettings(
            globalBypass: false,
            inputGain: -2.0,
            outputGain: 1.0,
            leftBands: leftBands,
            rightBands: leftBands
        )

        let original = Preset(
            version: Preset.currentVersion,
            metadata: PresetMetadata(name: "Full Test Preset", isFactoryPreset: true),
            settings: settings
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.metadata.name, original.metadata.name)
        XCTAssertEqual(decoded.settings.globalBypass, original.settings.globalBypass)
        XCTAssertEqual(decoded.settings.inputGain, original.settings.inputGain)
        XCTAssertEqual(decoded.settings.outputGain, original.settings.outputGain)
        // activeBandCount is derived from leftBands.count
        XCTAssertEqual(decoded.settings.activeBandCount, leftBands.count)
        XCTAssertEqual(decoded.settings.leftBands.count, original.settings.leftBands.count)
        XCTAssertEqual(decoded.settings.rightBands.count, original.settings.rightBands.count)
        XCTAssertTrue(decoded.metadata.isFactoryPreset)

        // Verify individual left bands
        for (index, decodedBand) in decoded.settings.leftBands.enumerated() {
            let originalBand = original.settings.leftBands[index]
            XCTAssertEqual(decodedBand.frequency, originalBand.frequency, "Band \(index) frequency mismatch")
            XCTAssertEqual(decodedBand.q, originalBand.q, "Band \(index) q mismatch")
            XCTAssertEqual(decodedBand.gain, originalBand.gain, "Band \(index) gain mismatch")
            XCTAssertEqual(decodedBand.filterType, originalBand.filterType, "Band \(index) filterType mismatch")
            XCTAssertEqual(decodedBand.bypass, originalBand.bypass, "Band \(index) bypass mismatch")
        }
    }

    func testPreset_currentVersion() {
        XCTAssertEqual(Preset.currentVersion, 2)
    }

    func testPreset_fileExtension() {
        XCTAssertEqual(Preset.fileExtension, "eqpreset")
    }

    func testPreset_filename() {
        let preset = Preset(
            metadata: PresetMetadata(name: "My Preset", isFactoryPreset: true),
            settings: PresetSettings()
        )

        XCTAssertEqual(preset.filename, "My Preset.eqpreset")
    }

    func testPreset_filename_sanitizesSpecialCharacters() {
        let preset = Preset(
            metadata: PresetMetadata(name: "Test/Preset:Name", isFactoryPreset: true),
            settings: PresetSettings()
        )

        XCTAssertEqual(preset.filename, "Test-Preset-Name.eqpreset")
    }

    func testPreset_id() {
        let preset = Preset(
            metadata: PresetMetadata(name: "Unique Name", isFactoryPreset: true),
            settings: PresetSettings()
        )

        XCTAssertEqual(preset.id, "Unique Name")
    }

    func testPreset_withUpdatedTimestamp() {
        let originalDate = Date(timeIntervalSince1970: 1700000000)
        let preset = Preset(
            metadata: PresetMetadata(name: "Test", createdAt: originalDate, modifiedAt: originalDate, isFactoryPreset: true),
            settings: PresetSettings()
        )

        let beforeUpdate = Date()
        let updated = preset.withUpdatedTimestamp()
        let afterUpdate = Date()

        // Created date should remain the same
        XCTAssertEqual(updated.metadata.createdAt.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 0.001)

        // Modified date should be updated
        XCTAssertGreaterThanOrEqual(updated.metadata.modifiedAt, beforeUpdate)
        XCTAssertLessThanOrEqual(updated.metadata.modifiedAt, afterUpdate)
    }

    func testPreset_renamed() {
        let originalDate = Date(timeIntervalSince1970: 1700000000)
        let preset = Preset(
            metadata: PresetMetadata(name: "Original Name", createdAt: originalDate, modifiedAt: originalDate, isFactoryPreset: true),
            settings: PresetSettings()
        )

        let beforeRename = Date()
        let renamed = preset.renamed(to: "New Name")
        let afterRename = Date()

        // Name should be updated
        XCTAssertEqual(renamed.metadata.name, "New Name")

        // Created date should remain the same
        XCTAssertEqual(renamed.metadata.createdAt.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 0.001)

        // Modified date should be updated
        XCTAssertGreaterThanOrEqual(renamed.metadata.modifiedAt, beforeRename)
        XCTAssertLessThanOrEqual(renamed.metadata.modifiedAt, afterRename)
    }
}
