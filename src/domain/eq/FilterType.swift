/// Custom filter type enum replacing AVAudioUnitEQFilterType.
/// Lives in domain layer — no framework dependencies.
/// Raw values 0-6 cover all filter types. Q/resonance is controlled via parameter.
enum FilterType: Int, Codable, Sendable, CaseIterable {
    case parametric = 0   // Peaking EQ (bell)
    case lowPass = 1      // 2nd-order low pass (Q controls resonance)
    case highPass = 2     // 2nd-order high pass (Q controls resonance)
    case lowShelf = 3     // Low shelf (Q controls slope)
    case highShelf = 4    // High shelf (Q controls slope)
    case bandPass = 5     // Band pass (constant 0 dB peak gain)
    case notch = 6       // Band stop / notch

    /// Creates a FilterType from a raw value.
    /// Returns nil if the raw value is outside the valid range.
    /// Migrates legacy resonant types (7-10) to their non-resonant equivalents.
    init?(validatedRawValue rawValue: Int) {
        // Migrate legacy resonant filter types
        let migratedValue: Int
        switch rawValue {
        case 7: migratedValue = 1  // resonantLowPass → lowPass
        case 8: migratedValue = 2  // resonantHighPass → highPass
        case 9: migratedValue = 3  // resonantLowShelf → lowShelf
        case 10: migratedValue = 4 // resonantHighShelf → highShelf
        default: migratedValue = rawValue
        }

        guard (0...6).contains(migratedValue) else { return nil }
        self.init(rawValue: migratedValue)
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
        }
    }

    /// All filter types in UI display order.
    static var allCasesInUIOrder: [FilterType] {
        [.parametric, .lowPass, .highPass, .lowShelf, .highShelf, .bandPass, .notch]
    }
}

// MARK: - Coding Key

extension FilterType {
    /// Creates FilterType from a coding key string (abbreviation).
    /// Returns .parametric for unknown strings.
    /// Migrates legacy resonant abbreviations to non-resonant equivalents.
    init(fromCodingKey key: String) {
        switch key {
        case "Bell": self = .parametric
        case "LP": self = .lowPass
        case "HP": self = .highPass
        case "LS": self = .lowShelf
        case "HS": self = .highShelf
        case "BP": self = .bandPass
        case "Notch": self = .notch
        // Legacy resonant abbreviations (migrated to non-resonant)
        case "RLP": self = .lowPass
        case "RHP": self = .highPass
        case "RLS": self = .lowShelf
        case "RHS": self = .highShelf
        default: self = .parametric
        }
    }
}