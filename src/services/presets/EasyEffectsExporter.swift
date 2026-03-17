import AVFoundation
import Foundation
import os.log

/// Errors that can occur during EasyEffects export.
enum EasyEffectsExportError: LocalizedError {
    case writeFailed(Error)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed(let error):
            return "Failed to write file: \(error.localizedDescription)"
        case .encodingFailed:
            return "Failed to encode preset to JSON"
        }
    }
}

/// Exports presets to EasyEffects-compatible JSON format.
///
/// The exported format is compatible with EasyEffects (Linux audio effects application)
/// and can be loaded directly into that application.
///
/// **Exported fields:**
/// - `frequency` → direct copy
/// - `gain` → direct copy
/// - `bandwidth` → converted to `q` using standard formula
/// - `filterType` → mapped to EasyEffects type names
/// - `bypass` → mapped to `mute`
/// - `inputGain`, `outputGain` → mapped to `input-gain`, `output-gain`
///
/// **Default values (not configurable in this app):**
/// - `mode` → "RLC (BT)" (default filter topology)
/// - `slope` → "x1" (first-order slope)
/// - `solo` → false
enum EasyEffectsExporter {
    private static let logger = Logger(subsystem: "net.knage.equaliser", category: "EasyEffectsExporter")

    // MARK: - Public API

    /// Exports a preset to EasyEffects JSON format.
    ///
    /// - Parameter preset: The preset to export.
    /// - Returns: JSON data in EasyEffects format.
    static func export(_ preset: Preset) throws -> Data {
        let json = buildEasyEffectsJSON(from: preset)

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            throw EasyEffectsExportError.encodingFailed
        }

        return data
    }

    /// Exports a preset to a file URL.
    ///
    /// - Parameters:
    ///   - preset: The preset to export.
    ///   - url: The destination file URL.
    static func export(_ preset: Preset, to url: URL) throws {
        let data = try export(preset)

        do {
            try data.write(to: url, options: .atomic)
            logger.info("Exported preset to EasyEffects format: \(url.path)")
        } catch {
            throw EasyEffectsExportError.writeFailed(error)
        }
    }

    // MARK: - JSON Building

    private static func buildEasyEffectsJSON(from preset: Preset) -> [String: Any] {
        // Build band dictionaries for left and right channels (identical)
        var bands: [String: Any] = [:]
        for (index, band) in preset.settings.bands.prefix(preset.settings.activeBandCount).enumerated() {
            bands["band\(index)"] = buildBandJSON(from: band)
        }

        // Build the equalizer section with left/right channels
        let equalizer: [String: Any] = [
            "balance": 0.0,
            "bypass": preset.settings.globalBypass,
            "input-gain": Double(preset.settings.inputGain),
            "left": bands,
            "mode": "IIR",
            "num-bands": preset.settings.activeBandCount,
            "output-gain": Double(preset.settings.outputGain),
            "pitch-left": 0.0,
            "pitch-right": 0.0,
            "right": bands,  // Same as left since we don't support split channels
            "split-channels": false,
        ]

        // Build the full EasyEffects structure
        return [
            "output": [
                "blocklist": [] as [String],
                "equalizer#0": equalizer,
                "plugins_order": ["equalizer#0"],
            ]
        ]
    }

    private static func buildBandJSON(from band: PresetBand) -> [String: Any] {
        let q = BandwidthConverter.bandwidthToQ(band.bandwidth)
        let typeString = mapFilterType(band.filterType)

        return [
            "frequency": Double(band.frequency),
            "gain": Double(band.gain),
            "mode": "APO (DR)",
            "mute": band.bypass,
            "q": Double(q),
            "slope": "x1",
            "solo": false,
            "type": typeString,
            "width": 4.0,
        ]
    }

    // MARK: - Type Mapping

    private static func mapFilterType(_ type: AVAudioUnitEQFilterType) -> String {
        switch type {
        case .parametric:
            return "Bell"
        case .lowPass:
            return "Lo-pass"
        case .highPass:
            return "Hi-pass"
        case .lowShelf:
            return "Lo-shelf"
        case .highShelf:
            return "Hi-shelf"
        case .bandPass:
            return "Band-pass"
        case .bandStop:
            return "Notch"
        case .resonantLowPass:
            return "Lo-pass"
        case .resonantHighPass:
            return "Hi-pass"
        case .resonantLowShelf:
            return "Lo-shelf"
        case .resonantHighShelf:
            return "Hi-shelf"
        @unknown default:
            return "Bell"
        }
    }
}

// MARK: - File Extension

extension EasyEffectsExporter {
    /// The file extension used for EasyEffects presets.
    static let fileExtension = "json"

    /// Generates a filename for an EasyEffects export.
    static func filename(for preset: Preset) -> String {
        let safeName = preset.metadata.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safeName).\(fileExtension)"
    }
}
