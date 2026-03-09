import Foundation

/// Represents the current state of audio routing.
enum RoutingStatus: Equatable {
    case idle
    case starting
    case active(inputName: String, outputName: String)
    case error(String)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
