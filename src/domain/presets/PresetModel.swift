import Foundation

/// Coding user info key for preset version.
/// Allows nested decoders to know which format version they're parsing.
enum PresetCodingKey {
    static let version = CodingUserInfoKey(rawValue: "presetVersion")!
}

/// Decoder wrapper that injects preset version into userInfo.
private struct VersionedDecoder: Decoder {
    let wrapped: Decoder
    let version: Int

    var userInfo: [CodingUserInfoKey: Any] {
        var info = wrapped.userInfo
        info[PresetCodingKey.version] = version
        return info
    }

    var codingPath: [CodingKey] { wrapped.codingPath }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        try wrapped.container(keyedBy: type)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        try wrapped.unkeyedContainer()
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        try wrapped.singleValueContainer()
    }
}

/// Metadata for a preset (name, timestamps).
struct PresetMetadata: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case name
        case createdAt
        case modifiedAt
        case isFactoryPreset
    }

    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var isFactoryPreset: Bool

    init(name: String, createdAt: Date = Date(), modifiedAt: Date = Date(), isFactoryPreset: Bool = false) {
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isFactoryPreset = isFactoryPreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        isFactoryPreset = try container.decodeIfPresent(Bool.self, forKey: .isFactoryPreset) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(isFactoryPreset, forKey: .isFactoryPreset)
    }
}

/// Settings snapshot for a preset, mirrors EQConfiguration state.
struct PresetSettings: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case globalBypass
        case inputGain
        case outputGain
        case activeBandCount  // v1 only: v2 derives from leftBands.count
        case leftBands
        case channelMode
        case rightBands
        case bands  // v1: decode as leftBands and rightBands
    }

    var globalBypass: Bool
    var inputGain: Float
    var outputGain: Float
    var activeBandCount: Int  // v1: stored explicitly; v2: derived from leftBands.count
    var channelMode: String
    var leftBands: [PresetBand]
    var rightBands: [PresetBand]

    /// Creates PresetSettings with default values (empty bands).
    init(
        globalBypass: Bool = false,
        inputGain: Float = 0,
        outputGain: Float = 0,
        channelMode: String = "linked",
        leftBands: [PresetBand] = [],
        rightBands: [PresetBand] = []
    ) {
        self.globalBypass = globalBypass
        self.inputGain = inputGain
        self.outputGain = outputGain
        self.channelMode = channelMode
        self.leftBands = leftBands
        self.rightBands = rightBands
        // Derive activeBandCount from left bands (linked mode uses same count for both)
        self.activeBandCount = leftBands.count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalBypass = try container.decode(Bool.self, forKey: .globalBypass)
        inputGain = try container.decode(Float.self, forKey: .inputGain)
        outputGain = try container.decode(Float.self, forKey: .outputGain)

        // Get version from userInfo (defaults to current version)
        let version = decoder.userInfo[PresetCodingKey.version] as? Int ?? Preset.currentVersion

        if version >= 2 {
            // v2: channelMode, leftBands, rightBands present; activeBandCount derived from bands
            channelMode = try container.decode(String.self, forKey: .channelMode)

            // Manually decode bands with version awareness
            var leftBandsArray: [PresetBand] = []
            var leftContainer = try container.nestedUnkeyedContainer(forKey: .leftBands)
            while !leftContainer.isAtEnd {
                let bandContainer = try leftContainer.nestedContainer(keyedBy: PresetBand.CodingKeys.self)
                leftBandsArray.append(try PresetBand(from: bandContainer, version: version))
            }
            leftBands = leftBandsArray

            var rightBandsArray: [PresetBand] = []
            var rightContainer = try container.nestedUnkeyedContainer(forKey: .rightBands)
            while !rightContainer.isAtEnd {
                let bandContainer = try rightContainer.nestedContainer(keyedBy: PresetBand.CodingKeys.self)
                rightBandsArray.append(try PresetBand(from: bandContainer, version: version))
            }
            rightBands = rightBandsArray

            // Derive activeBandCount from band arrays
            // For linked mode: both arrays have same count
            // For stereo mode: use left band count (UI shows max of both)
            activeBandCount = leftBands.count
        } else {
            // v1: activeBandCount stored explicitly, bands only, no channelMode
            activeBandCount = try container.decode(Int.self, forKey: .activeBandCount)
            channelMode = "linked"

            // Manually decode bands with version awareness
            var bandsArray: [PresetBand] = []
            var bandsContainer = try container.nestedUnkeyedContainer(forKey: .bands)
            while !bandsContainer.isAtEnd {
                let bandContainer = try bandsContainer.nestedContainer(keyedBy: PresetBand.CodingKeys.self)
                bandsArray.append(try PresetBand(from: bandContainer, version: version))
            }
            leftBands = bandsArray
            rightBands = bandsArray
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalBypass, forKey: .globalBypass)
        try container.encode(inputGain, forKey: .inputGain)
        try container.encode(outputGain, forKey: .outputGain)
        // Note: activeBandCount not encoded for v2 - derived from leftBands.count
        try container.encode(channelMode, forKey: .channelMode)
        try container.encode(leftBands, forKey: .leftBands)
        try container.encode(rightBands, forKey: .rightBands)
        // Note: We don't encode the legacy "bands" key - clean break for new saves
    }
}

/// A single band in a preset (simplified from EQBandConfiguration for preset storage).
///
/// Q (quality factor) is stored natively. Legacy presets with `bandwidth` are
/// converted to Q on load using `BandwidthConverter.bandwidthToQ()`.
struct PresetBand: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case frequency
        case q
        case bandwidth  // v1: AVAudioUnitEQ uses bandwidth
        case gain
        case filterType
        case bypass
    }

    var frequency: Float
    var q: Float
    var gain: Float
    var filterType: FilterType
    var bypass: Bool

    init(
        frequency: Float,
        q: Float,
        gain: Float,
        filterType: FilterType = .parametric,
        bypass: Bool = false
    ) {
        self.frequency = frequency
        self.q = q
        self.gain = gain
        self.filterType = filterType
        self.bypass = bypass
    }

    /// Creates a PresetBand by decoding from a container with version awareness.
    init(from container: KeyedDecodingContainer<CodingKeys>, version: Int) throws {
        frequency = try container.decode(Float.self, forKey: .frequency)
        gain = try container.decode(Float.self, forKey: .gain)
        bypass = try container.decode(Bool.self, forKey: .bypass)

        // Decode filterType based on version
        if version >= 2 {
            // v2: filterType as String
            let typeString = try container.decode(String.self, forKey: .filterType)
            filterType = FilterType(fromCodingKey: typeString)
        } else {
            // v1: filterType as Int
            let typeInt = try container.decode(Int.self, forKey: .filterType)
            filterType = FilterType(validatedRawValue: typeInt) ?? .parametric
        }

        // Decode Q based on version
        if version >= 2 {
            // v2: q field required
            q = try container.decode(Float.self, forKey: .q)
        } else {
            // v1: bandwidth field, convert to Q
            let bandwidth = try container.decode(Float.self, forKey: .bandwidth)
            q = BandwidthConverter.bandwidthToQ(bandwidth)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Default to current version when decoder doesn't have version in userInfo
        let version = decoder.userInfo[PresetCodingKey.version] as? Int ?? Preset.currentVersion
        try self.init(from: container, version: version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(q, forKey: .q)
        try container.encode(gain, forKey: .gain)
        try container.encode(filterType.abbreviation, forKey: .filterType)  // v2: String
        try container.encode(bypass, forKey: .bypass)
    }

    /// Converts from EQBandConfiguration.
    init(from eqBand: EQBandConfiguration) {
        self.frequency = eqBand.frequency
        self.q = eqBand.q
        self.gain = eqBand.gain
        self.filterType = eqBand.filterType
        self.bypass = eqBand.bypass
    }

    /// Converts to EQBandConfiguration.
    func toEQBandConfiguration() -> EQBandConfiguration {
        EQBandConfiguration(
            frequency: frequency,
            q: q,
            gain: gain,
            filterType: filterType,
            bypass: bypass
        )
    }
}

/// A complete preset with version, metadata, and settings.
struct Preset: Codable, Sendable, Identifiable {
    static let currentVersion = 2

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

        // Only store active bands (not the full 64-band array)
        let leftActiveCount = config.leftState.userEQ.activeBandCount
        let rightActiveCount = config.rightState.userEQ.activeBandCount

        self.settings = PresetSettings(
            globalBypass: config.globalBypass,
            inputGain: inputGain,
            outputGain: outputGain,
            channelMode: config.channelMode.rawValue,
            leftBands: config.leftState.userEQ.bands.prefix(leftActiveCount).map { PresetBand(from: $0) },
            rightBands: config.rightState.userEQ.bands.prefix(rightActiveCount).map { PresetBand(from: $0) }
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

// MARK: - Codable with version propagation

extension Preset {
    enum CodingKeys: String, CodingKey {
        case version
        case metadata
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        metadata = try container.decode(PresetMetadata.self, forKey: .metadata)

        // Pass version to nested decoders via userInfo
        let settingsDecoder = VersionedDecoder(
            wrapped: try container.superDecoder(forKey: .settings),
            version: version
        )
        settings = try PresetSettings(from: settingsDecoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Preset.currentVersion, forKey: .version)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(settings, forKey: .settings)
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
