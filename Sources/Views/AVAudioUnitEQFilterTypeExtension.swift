import AVFoundation

extension AVAudioUnitEQFilterType {
    /// Creates a filter type from a raw value, returning nil for unknown values.
    /// Use this instead of `init(rawValue:)` when you need proper fallback behavior,
    /// since the standard initializer accepts any raw value for ObjC-bridged enums.
    init?(validatedRawValue rawValue: Int) {
        // Valid raw values: 0-10 (parametric through resonantHighShelf)
        guard (0...10).contains(rawValue) else { return nil }
        self.init(rawValue: rawValue)
    }

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
        case .bandStop:
            return "Notch"
        case .resonantLowPass:
            return "Resonant Low Pass"
        case .resonantHighPass:
            return "Resonant High Pass"
        case .resonantLowShelf:
            return "Resonant Low Shelf"
        case .resonantHighShelf:
            return "Resonant High Shelf"
        @unknown default:
            return "Unknown"
        }
    }

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
        case .bandStop:
            return "Notch"
        case .resonantLowPass:
            return "RLP"
        case .resonantHighPass:
            return "RHP"
        case .resonantLowShelf:
            return "RLS"
        case .resonantHighShelf:
            return "RHS"
        @unknown default:
            return "?"
        }
    }

    static var allCasesInUIOrder: [AVAudioUnitEQFilterType] {
        [.parametric, .lowPass, .highPass, .lowShelf, .highShelf,
         .bandPass, .bandStop, .resonantLowPass, .resonantHighPass,
         .resonantLowShelf, .resonantHighShelf]
    }
}
