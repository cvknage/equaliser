/// Custom filter type enum replacing AVAudioUnitEQFilterType.
/// Lives in domain layer — no framework dependencies.
/// Raw values 0-10 match AVAudioUnitEQFilterType raw values for backward compatibility.
enum FilterType: Int, Codable, Sendable, CaseIterable {
    case parametric = 0       // Peaking EQ (bell)
    case lowPass = 1          // 2nd-order low pass
    case highPass = 2         // 2nd-order high pass
    case lowShelf = 3         // Low shelf
    case highShelf = 4        // High shelf
    case bandPass = 5         // Band pass (constant 0 dB peak gain)
    case notch = 6            // Band stop / notch
    case resonantLowPass = 7  // Low pass with resonance
    case resonantHighPass = 8 // High pass with resonance
    case resonantLowShelf = 9 // Low shelf with Q control
    case resonantHighShelf = 10 // High shelf with Q control

    /// Creates a FilterType from an AVAudioUnitEQFilterType raw value.
    /// Returns nil if the raw value is outside the valid range.
    init?(validatedRawValue rawValue: Int) {
        guard (0...10).contains(rawValue) else { return nil }
        self.init(rawValue: rawValue)
    }
}

// MARK: - Display Names

extension FilterType {
    /// User-facing display name for the filter type.
    var displayName: String {
        switch self {
        case .parametric:
            return "Parametric"
        case .lowPass:
            return "Low Pass"
        case .highPass:
            return "High Pass"
        case .lowShelf:
            return "Low Shelf"
        case .highShelf:
            return "High Shelf"
        case .bandPass:
            return "Band Pass"
        case .notch:
            return "Notch"
        case .resonantLowPass:
            return "Resonant Low Pass"
        case .resonantHighPass:
            return "Resonant High Pass"
        case .resonantLowShelf:
            return "Resonant Low Shelf"
        case .resonantHighShelf:
            return "Resonant High Shelf"
        }
    }

    /// Short abbreviation for the filter type (used in compact UI).
    var abbreviation: String {
        switch self {
        case .parametric:
            return "Bell"
        case .lowPass:
            return "LP"
        case .highPass:
            return "HP"
        case .lowShelf:
            return "LS"
        case .highShelf:
            return "HS"
        case .bandPass:
            return "BP"
        case .notch:
            return "Notch"
        case .resonantLowPass:
            return "RLP"
        case .resonantHighPass:
            return "RHP"
        case .resonantLowShelf:
            return "RLS"
        case .resonantHighShelf:
            return "RHS"
        }
    }

    /// All filter types in UI display order.
    static var allCasesInUIOrder: [FilterType] {
        [
            .parametric, .lowPass, .highPass, .lowShelf, .highShelf,
            .bandPass, .notch, .resonantLowPass, .resonantHighPass,
            .resonantLowShelf, .resonantHighShelf
        ]
    }
}

// MARK: - Coding Key

extension FilterType {
    /// Creates FilterType from a coding key string (abbreviation).
    /// Returns .parametric for unknown strings.
    init(fromCodingKey key: String) {
        switch key {
        case "Bell": self = .parametric
        case "LP": self = .lowPass
        case "HP": self = .highPass
        case "LS": self = .lowShelf
        case "HS": self = .highShelf
        case "BP": self = .bandPass
        case "Notch": self = .notch
        case "RLP": self = .resonantLowPass
        case "RHP": self = .resonantHighPass
        case "RLS": self = .resonantLowShelf
        case "RHS": self = .resonantHighShelf
        default: self = .parametric
        }
    }
}