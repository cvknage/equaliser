import AVFoundation
import Foundation

/// Metadata for a preset (name, timestamps).
struct PresetMetadata: Codable, Sendable {
    var name: String
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// Settings snapshot for a preset, mirrors EQConfiguration state.
struct PresetSettings: Codable, Sendable {
    var globalBypass: Bool
    var globalGain: Float
    var inputGain: Float
    var outputGain: Float
    var activeBandCount: Int
    var bands: [PresetBand]

    init(
        globalBypass: Bool = false,
        globalGain: Float = 0,
        inputGain: Float = 0,
        outputGain: Float = 0,
        activeBandCount: Int = EQConfiguration.defaultBandCount,
        bands: [PresetBand] = []
    ) {
        self.globalBypass = globalBypass
        self.globalGain = globalGain
        self.inputGain = inputGain
        self.outputGain = outputGain
        self.activeBandCount = activeBandCount
        self.bands = bands
    }
}

/// A single band in a preset (simplified from EQBandConfiguration for preset storage).
struct PresetBand: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case frequency
        case bandwidth
        case gain
        case filterType
        case bypass
    }

    var frequency: Float
    var bandwidth: Float
    var gain: Float
    var filterType: AVAudioUnitEQFilterType
    var bypass: Bool

    init(
        frequency: Float,
        bandwidth: Float,
        gain: Float,
        filterType: AVAudioUnitEQFilterType = .parametric,
        bypass: Bool = false
    ) {
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.gain = gain
        self.filterType = filterType
        self.bypass = bypass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(Float.self, forKey: .frequency)
        bandwidth = try container.decode(Float.self, forKey: .bandwidth)
        gain = try container.decode(Float.self, forKey: .gain)
        let filterTypeRaw = try container.decode(Int.self, forKey: .filterType)
        filterType = AVAudioUnitEQFilterType(validatedRawValue: filterTypeRaw) ?? .parametric
        bypass = try container.decode(Bool.self, forKey: .bypass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(bandwidth, forKey: .bandwidth)
        try container.encode(gain, forKey: .gain)
        try container.encode(filterType.rawValue, forKey: .filterType)
        try container.encode(bypass, forKey: .bypass)
    }

    /// Converts from EQBandConfiguration.
    init(from eqBand: EQBandConfiguration) {
        self.frequency = eqBand.frequency
        self.bandwidth = eqBand.bandwidth
        self.gain = eqBand.gain
        self.filterType = eqBand.filterType
        self.bypass = eqBand.bypass
    }

    /// Converts to EQBandConfiguration.
    func toEQBandConfiguration() -> EQBandConfiguration {
        EQBandConfiguration(
            frequency: frequency,
            bandwidth: bandwidth,
            gain: gain,
            filterType: filterType,
            bypass: bypass
        )
    }
}

/// A complete preset with version, metadata, and settings.
struct Preset: Codable, Sendable, Identifiable {
    static let currentVersion = 1

    var version: Int
    var metadata: PresetMetadata
    var settings: PresetSettings

    var id: String { metadata.name }

    init(
        version: Int = Preset.currentVersion,
        metadata: PresetMetadata,
        settings: PresetSettings
    ) {
        self.version = version
        self.metadata = metadata
        self.settings = settings
    }

    /// Creates a preset from the current EQConfiguration state.
    @MainActor
    init(name: String, from config: EQConfiguration, inputGain: Float = 0, outputGain: Float = 0) {
        self.version = Preset.currentVersion
        self.metadata = PresetMetadata(name: name)
        self.settings = PresetSettings(
            globalBypass: config.globalBypass,
            globalGain: config.globalGain,
            inputGain: inputGain,
            outputGain: outputGain,
            activeBandCount: config.activeBandCount,
            bands: config.bands.map { PresetBand(from: $0) }
        )
    }

    /// Creates a copy of the preset with an updated modification timestamp.
    func withUpdatedTimestamp() -> Preset {
        var copy = self
        copy.metadata.modifiedAt = Date()
        return copy
    }

    /// Creates a copy of the preset with a new name.
    func renamed(to newName: String) -> Preset {
        var copy = self
        copy.metadata.name = newName
        copy.metadata.modifiedAt = Date()
        return copy
    }
}

/// File extension for native preset files.
extension Preset {
    static let fileExtension = "eqpreset"

    /// Generates a safe filename from the preset name.
    var filename: String {
        let safeName = metadata.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safeName).\(Preset.fileExtension)"
    }
}
