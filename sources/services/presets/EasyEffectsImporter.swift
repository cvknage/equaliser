import AVFoundation
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
/// - `q` → convert to bandwidth using standard formula
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

        // Check for ignored parameters and add warnings
        if eq["split-channels"] as? Bool == true {
            warnings.append("Split channels mode is not supported - using mono EQ")
        }

        // Parse bands - EasyEffects stores bands inside "left" and "right" sections
        var bands: [PresetBand] = []
        let maxBands = EQConfiguration.maxBandCount

        // Try to get bands from "left" section first (standard EasyEffects format)
        let leftSection = eq["left"] as? [String: Any]
        let rightSection = eq["right"] as? [String: Any]

        // Use left channel as primary, fall back to direct band keys for older formats
        let bandSource: [String: Any]
        if let left = leftSection {
            bandSource = left

            // Check if right channel differs from left and warn
            if let right = rightSection {
                let channelDifferences = compareChannels(left: left, right: right)
                if !channelDifferences.isEmpty {
                    warnings.append("Left and right channels differ - using left channel only. Differences: \(channelDifferences.joined(separator: ", "))")
                }
            }
        } else {
            // Fall back to bands directly in equalizer section (legacy format)
            bandSource = eq
        }

        // Parse bands from the selected source
        var bandIndex = 0
        while bandIndex < maxBands {
            let bandKey = "band\(bandIndex)"
            guard let bandData = bandSource[bandKey] as? [String: Any] else {
                break
            }

            let band = parseBand(bandData, index: bandIndex, warnings: &warnings)
            bands.append(band)
            bandIndex += 1
        }

        // If no bands found with "band0" format, try numbered format
        if bands.isEmpty {
            for i in 0..<maxBands {
                if let bandData = bandSource["\(i)"] as? [String: Any] {
                    let band = parseBand(bandData, index: i, warnings: &warnings)
                    bands.append(band)
                }
            }
        }

        logger.info("Imported \(bands.count) bands from EasyEffects preset")

        if bands.isEmpty {
            warnings.append("No EQ bands found in preset")
        }

        let settings = PresetSettings(
            globalBypass: false,
            inputGain: inputGain,
            outputGain: outputGain,
            activeBandCount: bands.count,
            bands: bands
        )

        let preset = Preset(
            metadata: PresetMetadata(name: name),
            settings: settings
        )

        return EasyEffectsImportResult(preset: preset, warnings: warnings)
    }

    /// Compares left and right channel bands and returns a list of differences.
    private static func compareChannels(left: [String: Any], right: [String: Any]) -> [String] {
        var differences: [String] = []

        // Get all band keys from both channels
        let leftBandKeys = left.keys.filter { $0.hasPrefix("band") }.sorted()
        let rightBandKeys = right.keys.filter { $0.hasPrefix("band") }.sorted()

        if leftBandKeys.count != rightBandKeys.count {
            differences.append("band count (\(leftBandKeys.count) vs \(rightBandKeys.count))")
            return differences
        }

        // Compare each band
        for bandKey in leftBandKeys {
            guard let leftBand = left[bandKey] as? [String: Any],
                  let rightBand = right[bandKey] as? [String: Any] else {
                continue
            }

            // Compare key properties
            let leftFreq = (leftBand["frequency"] as? NSNumber)?.floatValue ?? 0
            let rightFreq = (rightBand["frequency"] as? NSNumber)?.floatValue ?? 0
            let leftGain = (leftBand["gain"] as? NSNumber)?.floatValue ?? 0
            let rightGain = (rightBand["gain"] as? NSNumber)?.floatValue ?? 0
            let leftQ = (leftBand["q"] as? NSNumber)?.floatValue ?? 0
            let rightQ = (rightBand["q"] as? NSNumber)?.floatValue ?? 0

            if abs(leftFreq - rightFreq) > 0.01 || abs(leftGain - rightGain) > 0.01 || abs(leftQ - rightQ) > 0.01 {
                differences.append(bandKey)
            }
        }

        return differences
    }

    private static func parseBand(_ data: [String: Any], index: Int, warnings: inout [String]) -> PresetBand {
        // Extract values with defaults
        let frequency = (data["frequency"] as? NSNumber)?.floatValue ?? defaultFrequency(for: index)
        let gain = (data["gain"] as? NSNumber)?.floatValue ?? 0
        let q = (data["q"] as? NSNumber)?.floatValue ?? 1.41 // Default ~1 octave
        let mute = data["mute"] as? Bool ?? false
        let typeString = data["type"] as? String ?? "Bell"

        // Convert Q to bandwidth
        let bandwidth = BandwidthConverter.qToBandwidth(q)

        // Convert filter type
        let filterType = mapFilterType(typeString)

        // Check for ignored parameters
        if data["slope"] != nil || data["mode"] != nil {
            // Only warn once per preset, not per band
        }
        if data["solo"] as? Bool == true {
            warnings.append("Band \(index): Solo mode is ignored")
        }

        return PresetBand(
            frequency: frequency,
            bandwidth: BandwidthConverter.clampBandwidth(bandwidth),
            gain: gain,
            filterType: filterType,
            bypass: mute
        )
    }

    // MARK: - Type Mapping

    private static func mapFilterType(_ typeString: String) -> AVAudioUnitEQFilterType {
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
            return .bandStop
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
