import Foundation

/// User preference for how to display bandwidth values.
enum BandwidthDisplayMode: String, Codable, CaseIterable, Sendable {
    case qFactor = "qFactor"
    case octaves = "octaves"

    var displayName: String {
        switch self {
        case .octaves:
            return "Bandwidth (octaves)"
        case .qFactor:
            return "Q Factor"
        }
    }

    var abbreviation: String {
        switch self {
        case .octaves:
            return "oct"
        case .qFactor:
            return "Q"
        }
    }
}

/// Utilities for converting between Q factor and bandwidth (octaves), and for
/// formatting and parsing those values for display.
///
/// Q factor is the internal storage format used throughout the model. Bandwidth
/// in octaves is a display preference only. The standard conversion formulas are:
/// - Q is a dimensionless value representing filter selectivity
/// - Bandwidth in octaves represents the frequency range between -3 dB points
///
/// Reference: https://www.rane.com/note170.html
enum BandwidthConverter {
    // MARK: - Conversion Functions

    /// Converts Q factor to bandwidth in octaves.
    ///
    /// Formula: BW = 2 * asinh(1 / (2 * Q)) / ln(2)
    ///
    /// - Parameter q: The Q factor (must be > 0).
    /// - Returns: Bandwidth in octaves.
    static func qToBandwidth(_ q: Float) -> Float {
        guard q > 0 else { return 0 }
        return 2 * asinh(1 / (2 * q)) / log(2)
    }

    /// Converts bandwidth in octaves to Q factor.
    ///
    /// Formula: Q = 1 / (2 * sinh(ln(2) * BW / 2))
    ///
    /// - Parameter bandwidth: Bandwidth in octaves (must be > 0).
    /// - Returns: Q factor.
    static func bandwidthToQ(_ bandwidth: Float) -> Float {
        guard bandwidth > 0 else { return 0 }
        return 1 / (2 * sinh(log(2) * bandwidth / 2))
    }

    // MARK: - Formatting Functions

    /// Formats a Q factor value for display based on the selected mode.
    ///
    /// - Parameters:
    ///   - q: The Q factor (internal storage format).
    ///   - mode: The display mode preference.
    /// - Returns: A formatted string with unit.
    static func format(q: Float, mode: BandwidthDisplayMode) -> String {
        switch mode {
        case .octaves:
            return String(format: "%.2f oct", qToBandwidth(q))
        case .qFactor:
            return String(format: "Q %.2f", q)
        }
    }

    /// Formats a Q factor value for a text input field based on the selected mode.
    ///
    /// - Parameters:
    ///   - q: The Q factor (internal storage format).
    ///   - mode: The display mode preference.
    /// - Returns: A formatted string without unit (for text field input).
    static func formatForInput(q: Float, mode: BandwidthDisplayMode) -> String {
        switch mode {
        case .octaves:
            return String(format: "%.2f", qToBandwidth(q))
        case .qFactor:
            return String(format: "%.2f", q)
        }
    }

    /// Parses a user-entered string into a raw float value.
    ///
    /// Returns the raw parsed float without any unit conversion — the value is
    /// in whatever unit the current display mode represents (octaves for `.octaves`,
    /// Q factor for `.qFactor`). The caller is responsible for clamping and
    /// converting to Q for storage.
    ///
    /// - Parameters:
    ///   - value: The user-entered string.
    ///   - mode: The display mode (determines the unit of the returned value).
    /// - Returns: The parsed float, or nil if the string is not a valid positive number.
    static func parseInput(_ value: String, mode: BandwidthDisplayMode) -> Float? {
        guard let floatValue = Float(value), floatValue > 0 else {
            return nil
        }
        return floatValue
    }

    // MARK: - Reference Values

    /// Common Q values with their bandwidth equivalents for reference.
    /// Useful for understanding the relationship and for UI tooltips.
    static let referenceTable: [(q: Float, bandwidth: Float, description: String)] = [
        (0.5, qToBandwidth(0.5), "Very wide"),
        (0.707, qToBandwidth(0.707), "Butterworth"),
        (1.0, qToBandwidth(1.0), "Moderate"),
        (1.41, qToBandwidth(1.41), "~1 octave"),
        (2.0, qToBandwidth(2.0), "Narrow"),
        (4.36, qToBandwidth(4.36), "AutoEQ default"),
        (10.0, qToBandwidth(10.0), "Surgical"),
    ]

    // MARK: - Validation

    /// Validates and clamps a bandwidth value to reasonable limits.
    ///
    /// - Parameter bandwidth: The bandwidth in octaves.
    /// - Returns: Clamped bandwidth value (0.05 to 5.0 octaves).
    static func clampBandwidth(_ bandwidth: Float) -> Float {
        min(max(bandwidth, 0.05), 5.0)
    }

    /// Validates and clamps a Q factor value to reasonable limits.
    ///
    /// - Parameter q: The Q factor.
    /// - Returns: Clamped Q value (0.1 to 100).
    static func clampQ(_ q: Float) -> Float {
        min(max(q, 0.1), 100)
    }
}
