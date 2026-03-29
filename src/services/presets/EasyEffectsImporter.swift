import Foundation
import os.log

/// Errors that can occur during EasyEffects import.
enum EasyEffectsImportError: LocalizedError {
    case readFailed(Error)
    case invalidJSON(Error)
    case missingEqualizerSection
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .invalidJSON(let error):
            return "Invalid JSON format: \(error.localizedDescription)"
        case .missingEqualizerSection:
            return "No equalizer section found in the preset file"
        case .unsupportedVersion:
            return "Unsupported EasyEffects preset version"
        }
    }
}

/// Result of an EasyEffects import operation.
struct EasyEffectsImportResult {
    let preset: Preset
    let warnings: [String]
}

/// Imports EasyEffects presets into the native format.
///
/// EasyEffects is a Linux audio effects application that stores presets in JSON format.
/// This importer extracts the equalizer settings and converts them to our native format.
///
/// **Mappable fields:**
/// - `frequency` → direct copy
/// - `gain` → direct copy
/// - `q` → direct copy (EasyEffects uses Q natively)
/// - `type` → maps to `AVAudioUnitEQFilterType`
/// - `mute` → maps to `bypass`
/// - `input-gain`, `output-gain` → direct copy
///
/// **Ignored on import (not supported by AUNBandEQ):**
/// - `mode` - filter topology (RLC BT, RLC MT, etc.)
/// - `slope` - filter order (x1, x2, x4)
/// - `solo` - not implemented
/// - `split-channels` - per-channel EQ not supported
/// - Non-EQ plugins (compressor, limiter, gate) - app is EQ-only
enum EasyEffectsImporter {
    private static let logger = Logger(subsystem: "net.knage.equaliser", category: "EasyEffectsImporter")

    // MARK: - Public API

    /// Imports an EasyEffects preset from a file URL.
    ///
    /// - Parameter url: The URL of the EasyEffects JSON file.
    /// - Returns: An import result containing the converted preset and any warnings.
    static func importPreset(from url: URL) throws -> EasyEffectsImportResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EasyEffectsImportError.readFailed(error)
        }

        return try importPreset(from: data, name: url.deletingPathExtension().lastPathComponent)
    }

    /// Imports an EasyEffects preset from JSON data.
    ///
    /// - Parameters:
    ///   - data: The JSON data.
    ///   - name: The name to use for the preset.
    /// - Returns: An import result containing the converted preset and any warnings.
    static func importPreset(from data: Data, name: String) throws -> EasyEffectsImportResult {
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EasyEffectsImportError.invalidJSON(NSError(domain: "EasyEffectsImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Root object is not a dictionary"]))
            }
            json = parsed
        } catch {
            throw EasyEffectsImportError.invalidJSON(error)
        }

        return try parseEasyEffectsJSON(json, name: name)
    }

    // MARK: - JSON Parsing

    /// Finds an equalizer section in a dictionary, supporting both exact "equalizer" key
    /// and numbered keys like "equalizer#0", "equalizer#1", etc.
    private static func findEqualizerSection(in dict: [String: Any]) -> [String: Any]? {
        // First try exact match
        if let eq = dict["equalizer"] as? [String: Any] {
            return eq
        }
        // Then look for numbered equalizers (equalizer#0, equalizer#1, etc.)
        // EasyEffects supports multiple equalizers and names them this way
        for key in dict.keys.sorted() {
            if key.hasPrefix("equalizer#"),
               let eq = dict[key] as? [String: Any] {
                return eq  // Return the first one found
            }
        }
        return nil
    }

    private static func parseEasyEffectsJSON(_ json: [String: Any], name: String) throws -> EasyEffectsImportResult {
        var warnings: [String] = []

        // EasyEffects presets can have different structures depending on version
        // Try to find the equalizer section in various possible locations

        var eqSection: [String: Any]?
        var inputGain: Float = 0
        var outputGain: Float = 0

        // Try new EasyEffects format (output -> equalizer or output -> equalizer#N)
        if let output = json["output"] as? [String: Any],
           let equalizer = findEqualizerSection(in: output) {
            eqSection = equalizer
            inputGain = (equalizer["input-gain"] as? NSNumber)?.floatValue ?? 0
            outputGain = (equalizer["output-gain"] as? NSNumber)?.floatValue ?? 0
        }
        // Try alternate path (effects -> equalizer or effects -> equalizer#N)
        else if let effects = json["effects"] as? [String: Any],
                let equalizer = findEqualizerSection(in: effects) {
            eqSection = equalizer
            inputGain = (equalizer["input-gain"] as? NSNumber)?.floatValue ?? 0
            outputGain = (equalizer["output-gain"] as? NSNumber)?.floatValue ?? 0
        }
        // Try legacy PulseEffects format
        else if let spectrum = json["spectrum"] as? [String: Any],
                let equalizer = findEqualizerSection(in: spectrum) {
            eqSection = equalizer
            warnings.append("Legacy PulseEffects format detected; some settings may not import correctly")
        }

        guard let eq = eqSection else {
            throw EasyEffectsImportError.missingEqualizerSection
        }

        // Parse bands - EasyEffects stores bands inside "left" and "right" sections
        let maxBands = EQConfiguration.maxBandCount

        // Check for split-channels flag to determine channel mode
        let splitChannels = eq["split-channels"] as? Bool ?? false

        // Try to get bands from "left" section first (standard EasyEffects format)
        let leftSection = eq["left"] as? [String: Any]
        let rightSection = eq["right"] as? [String: Any]

        // Parse left channel bands
        var leftBands: [PresetBand] = []
        let leftSource: [String: Any] = leftSection ?? eq

        var bandIndex = 0
        while bandIndex < maxBands {
            let bandKey = "band\(bandIndex)"
            guard let bandData = leftSource[bandKey] as? [String: Any] else {
                break
            }
            leftBands.append(parseBand(bandData, index: bandIndex, warnings: &warnings))
            bandIndex += 1
        }

        // If no bands found with "band0" format, try numbered format
        if leftBands.isEmpty {
            for i in 0..<maxBands {
                if let bandData = leftSource["\(i)"] as? [String: Any] {
                    leftBands.append(parseBand(bandData, index: i, warnings: &warnings))
                }
            }
        }

        // Parse right channel bands if in stereo mode
        var rightBands: [PresetBand]
        var channelMode: String

        if splitChannels, let right = rightSection {
            // Stereo mode: parse right channel separately
            rightBands = []
            var rightIndex = 0
            while rightIndex < maxBands {
                let bandKey = "band\(rightIndex)"
                guard let bandData = right[bandKey] as? [String: Any] else {
                    break
                }
                rightBands.append(parseBand(bandData, index: rightIndex, warnings: &warnings))
                rightIndex += 1
            }
            // If no bands found with "band0" format, try numbered format
            if rightBands.isEmpty {
                for i in 0..<maxBands {
                    if let bandData = right["\(i)"] as? [String: Any] {
                        rightBands.append(parseBand(bandData, index: i, warnings: &warnings))
                    }
                }
            }
            channelMode = "stereo"
        } else {
            // Linked mode: copy left bands to right
            rightBands = leftBands
            channelMode = "linked"
        }

        logger.info("Imported \(leftBands.count) bands from EasyEffects preset (channelMode: \(channelMode))")

        if leftBands.isEmpty {
            warnings.append("No EQ bands found in preset")
        }

        let settings = PresetSettings(
            globalBypass: false,
            inputGain: inputGain,
            outputGain: outputGain,
            activeBandCount: leftBands.count,
            channelMode: channelMode,
            leftBands: leftBands,
            rightBands: rightBands
        )

        let preset = Preset(
            metadata: PresetMetadata(name: name),
            settings: settings
        )

        return EasyEffectsImportResult(preset: preset, warnings: warnings)
    }

    private static func parseBand(_ data: [String: Any], index: Int, warnings: inout [String]) -> PresetBand {
        // Extract raw values with defaults
        let rawFrequency = (data["frequency"] as? NSNumber)?.floatValue ?? defaultFrequency(for: index)
        let rawGain = (data["gain"] as? NSNumber)?.floatValue ?? 0
        let rawQ = (data["q"] as? NSNumber)?.floatValue ?? 1.41 // Default ~1 octave
        let mute = data["mute"] as? Bool ?? false
        let typeString = data["type"] as? String ?? "Bell"

        // Validate and clamp values using AudioConstants (single source of truth)
        let frequency = AudioConstants.clampFrequency(rawFrequency)
        let gain = AudioConstants.clampGain(rawGain)
        let q = BandwidthConverter.clampQ(rawQ)

        // Convert filter type
        let filterType = mapFilterType(typeString)

        // Warn if values were clamped
        if frequency != rawFrequency {
            warnings.append("Band \(index): frequency clamped from \(rawFrequency) Hz to \(frequency) Hz")
        }
        if gain != rawGain {
            warnings.append("Band \(index): gain clamped from \(rawGain) dB to \(gain) dB")
        }
        if q != rawQ {
            warnings.append("Band \(index): Q adjusted from \(rawQ) to \(q)")
        }

        // Check for ignored parameters
        if data["solo"] as? Bool == true {
            warnings.append("Band \(index): Solo mode is ignored")
        }

        return PresetBand(
            frequency: frequency,
            q: q,
            gain: gain,
            filterType: filterType,
            bypass: mute
        )
    }

    // MARK: - Type Mapping

    private static func mapFilterType(_ typeString: String) -> FilterType {
        switch typeString.lowercased() {
        case "bell", "peaking":
            return .parametric
        case "lo-pass", "lowpass", "low-pass", "lp":
            return .lowPass
        case "hi-pass", "highpass", "high-pass", "hp":
            return .highPass
        case "lo-shelf", "lowshelf", "low-shelf", "ls":
            return .lowShelf
        case "hi-shelf", "highshelf", "high-shelf", "hs":
            return .highShelf
        case "band-pass", "bandpass", "bp":
            return .bandPass
        case "notch", "band-stop", "bandstop":
            return .notch
        default:
            return .parametric
        }
    }

    private static func defaultFrequency(for index: Int) -> Float {
        // Generate a reasonable default frequency if not specified
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let steps = 31 // Default to 32-band spacing
        let ratio = pow(maxFreq / minFreq, 1 / Float(steps))
        return minFreq * pow(ratio, Float(index))
    }
}
