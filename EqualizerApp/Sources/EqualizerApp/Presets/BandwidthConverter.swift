import Foundation

/// User preference for how to display bandwidth values.
enum BandwidthDisplayMode: String, Codable, CaseIterable, Sendable {
    case octaves = "octaves"
    case qFactor = "qFactor"

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

/// Utilities for converting between Q factor and bandwidth (octaves).
///
/// These formulas are the standard conversions used in audio engineering:
/// - Q is a dimensionless value representing filter selectivity
/// - Bandwidth in octaves represents the frequency range between -3dB points
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

    /// Formats a bandwidth value for display based on the selected mode.
    ///
    /// - Parameters:
    ///   - bandwidth: The bandwidth in octaves (internal storage format).
    ///   - mode: The display mode preference.
    /// - Returns: A formatted string with unit.
    static func format(bandwidth: Float, mode: BandwidthDisplayMode) -> String {
        switch mode {
        case .octaves:
            return String(format: "%.2f oct", bandwidth)
        case .qFactor:
            let q = bandwidthToQ(bandwidth)
            return String(format: "Q %.2f", q)
        }
    }

    /// Formats a bandwidth value for input field based on the selected mode.
    ///
    /// - Parameters:
    ///   - bandwidth: The bandwidth in octaves (internal storage format).
    ///   - mode: The display mode preference.
    /// - Returns: A formatted string without unit (for text field input).
    static func formatForInput(bandwidth: Float, mode: BandwidthDisplayMode) -> String {
        switch mode {
        case .octaves:
            return String(format: "%.2f", bandwidth)
        case .qFactor:
            let q = bandwidthToQ(bandwidth)
            return String(format: "%.2f", q)
        }
    }

    /// Converts a user-input value to bandwidth in octaves based on display mode.
    ///
    /// - Parameters:
    ///   - value: The user-entered value.
    ///   - mode: The display mode that determines how to interpret the value.
    /// - Returns: Bandwidth in octaves, or nil if the value is invalid.
    static func parseInput(_ value: String, mode: BandwidthDisplayMode) -> Float? {
        guard let floatValue = Float(value), floatValue > 0 else {
            return nil
        }

        switch mode {
        case .octaves:
            return floatValue
        case .qFactor:
            return qToBandwidth(floatValue)
        }
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
