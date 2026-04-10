import Foundation

/// Compare mode for EQ vs Flat comparison.
enum CompareMode: Int, Codable, Sendable {
    case eq = 0
    case flat = 1
}