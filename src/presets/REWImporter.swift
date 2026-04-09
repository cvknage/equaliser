import Foundation
import os.log

/// Errors that can occur during REW import.
enum REWImportError: LocalizedError {
    case readFailed(Error)
    case invalidFormat(String)
    case noFiltersFound

    var errorDescription: String? {
        switch self {
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .invalidFormat(let message):
            return "Invalid REW format: \(message)"
        case .noFiltersFound:
            return "No filter settings found in file"
        }
    }
}

/// Result of an REW import operation.
struct REWImportResult {
    let bands: [PresetBand]
    let warnings: [String]
}

/// Imports REW (Room EQ Wizard) filter settings files.
///
/// REW exports filter settings as text files with the following format:
/// - Header lines (version, date, notes, equalizer type)
/// - Filter lines: `Filter N: ON/OFF Type Fc FreqHz GainXdB [BW/60 Y | Q Z]`
///
/// This importer extracts peaking, shelf, and crossover filters and converts
/// them to PresetBand values.
enum REWImporter {
    private static let logger = Logger(subsystem: "net.knage.equaliser", category: "REWImporter")

    // MARK: - Public API

    /// Imports REW filter settings from a file URL.
    /// - Parameter url: The URL of the REW .txt file.
    /// - Returns: An import result containing the bands and any warnings.
    static func importBands(from url: URL) throws -> REWImportResult {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw REWImportError.readFailed(error)
        }
        return try parseREWText(content, filename: url.lastPathComponent)
    }

    // MARK: - Parsing

    private static func parseREWText(_ text: String, filename: String) throws -> REWImportResult {
        var warnings: [String] = []
        var bands: [PresetBand] = []

        // Parse filter lines
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Filter") else { continue }

            if let band = parseFilterLine(line: trimmed, warnings: &warnings) {
                bands.append(band)
            }
        }

        guard !bands.isEmpty else {
            throw REWImportError.noFiltersFound
        }

        logger.info("Imported \(bands.count) filters from REW file '\(filename)'")
        return REWImportResult(bands: bands, warnings: warnings)
    }

    private static func parseFilterLine(line: String, warnings: inout [String]) -> PresetBand? {
        // REW filter line format:
        // Filter N: ON/OFF Type Fc FreqHz [Band info] Gain XdB [BW/60 Y | Q Z]
        // Examples:
        //   Filter 1: ON  PK   Fc   129.1Hz (  125 +2 )   Gain -18.5dB  BW/60  4.0
        //   Filter 2: ON  LS   Fc    99.1Hz (  100 -1 )   Gain  -3.5dB  Q  1.41
        //   Filter 3: ON  None
        //   Filter 4: ON  PA   Fc    36.8Hz              Gain -15.5dB  BW/60 10.0

        let tokens = tokenizeLine(line)

        // Find the filter number
        guard let filterIndex = tokens.firstIndex(of: "Filter"),
              filterIndex + 1 < tokens.count else { return nil }

        // Find ON/OFF status
        guard let statusIndex = tokens.firstIndex(where: { $0 == "ON" || $0 == "OFF" }),
              statusIndex > filterIndex else { return nil }

        let isOn = tokens[statusIndex] == "ON"

        // Filter type is the token after ON/OFF
        let typeIndex = statusIndex + 1
        guard typeIndex < tokens.count else { return nil }
        let rawType = tokens[typeIndex]

        // Skip "None" filters (unused slots)
        if rawType.uppercased() == "NONE" {
            return nil
        }

        // Find Fc and extract frequency
        guard let fcIndex = tokens.firstIndex(of: "Fc"),
              fcIndex + 1 < tokens.count else { return nil }

        // Frequency token may be "129.1Hz" or have Hz separate
        var freqString = tokens[fcIndex + 1]
        freqString = freqString.replacingOccurrences(of: "Hz", with: "")
        guard let frequency = Float(freqString) else { return nil }

        // Find Gain and extract value (may be absent for crossover filters)
        let gain: Float
        if let gainIndex = tokens.firstIndex(where: { $0.hasPrefix("Gain") || $0 == "Gain" }),
           gainIndex + 1 < tokens.count {
            var gainString = tokens[gainIndex + 1]
            gainString = gainString.replacingOccurrences(of: "dB", with: "")
            guard let parsedGain = Float(gainString) else { return nil }
            gain = parsedGain
        } else {
            // Default gain for filters without explicit gain (e.g., HP, LP)
            gain = 0.0
        }

        // Determine Q value
        let q: Float
        if let qIndex = tokens.firstIndex(of: "Q"),
           qIndex + 1 < tokens.count {
            // Direct Q value
            guard let qValue = Float(tokens[qIndex + 1]) else { return nil }
            q = BandwidthConverter.clampQ(qValue)
            if q != qValue {
                warnings.append("Filter at \(Int(frequency)) Hz: Q clamped from \(String(format: "%.2f", qValue)) to \(String(format: "%.2f", q))")
            }
        } else if let bwIndex = tokens.firstIndex(of: "BW/60"),
                  bwIndex + 1 < tokens.count {
            // BW/60 format - convert to Q
            guard let bw60 = Float(tokens[bwIndex + 1]) else { return nil }
            let convertedQ = bw60ToQ(bw60)
            q = BandwidthConverter.clampQ(convertedQ)
            if abs(q - convertedQ) > 0.01 {
                warnings.append("Filter at \(Int(frequency)) Hz: Q clamped from \(String(format: "%.2f", convertedQ)) to \(String(format: "%.2f", q))")
            }
        } else {
            // Default Q for approximately 1 octave
            q = 1.41
        }

        // Map filter type
        let filterType = mapFilterType(rawType)

        // Clamp frequency and gain
        let clampedFreq = AudioConstants.clampFrequency(frequency)
        let clampedGain = AudioConstants.clampGain(gain)

        if clampedFreq != frequency {
            warnings.append("Filter at \(Int(frequency)) Hz: frequency clamped to \(Int(clampedFreq)) Hz")
        }
        if clampedGain != gain {
            warnings.append("Filter at \(Int(frequency)) Hz: gain clamped from \(gain) dB to \(clampedGain) dB")
        }

        return PresetBand(
            frequency: clampedFreq,
            q: q,
            gain: clampedGain,
            filterType: filterType,
            bypass: !isOn
        )
    }

    /// Tokenizes a REW filter line into components.
    /// Handles the special case where "Gain" and "-18.5dB" might be separate tokens,
    /// or combined like "Gain-18.5dB".
    private static func tokenizeLine(_ line: String) -> [String] {
        // First split by whitespace
        let rawTokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var tokens: [String] = []
        for token in rawTokens {
            // Handle "Gain-18.5dB" → ["Gain", "-18.5dB"]
            // Handle "Gain" as standalone
            if token.hasPrefix("Gain") && token.count > 4 {
                // Split "Gain-18.5dB" into "Gain" and the rest
                let gainPart = String(token.dropFirst(4))
                tokens.append("Gain")
                tokens.append(gainPart)
            } else {
                tokens.append(token)
            }
        }
        return tokens
    }

    /// Converts BW/60 to Q factor.
    /// BW/60 is the bandwidth in 60ths of an octave used by Behringer DSP1124P.
    /// Formula: Q = 60 / (BW/60 × sqrt(2))
    private static func bw60ToQ(_ bw60: Float) -> Float {
        guard bw60 > 0 else { return 1.41 }
        return 60.0 / (bw60 * sqrt(2))
    }

    private static func mapFilterType(_ raw: String) -> FilterType {
        switch raw.uppercased() {
        case "PK", "PEQ", "PA", "PARAMETRIC":
            return .parametric
        case "LS", "LOWSHELF", "LOW-SHELF":
            return .lowShelf
        case "HS", "HIGHSHELF", "HIGH-SHELF":
            return .highShelf
        case "LP", "LOWPASS", "LOW-PASS":
            return .lowPass
        case "HP", "HIGHPASS", "HIGH-PASS":
            return .highPass
        case "BP", "BANDPASS", "BAND-PASS":
            return .bandPass
        case "NOTCH", "BANDSTOP", "BAND-STOP":
            return .notch
        default:
            return .parametric
        }
    }
}