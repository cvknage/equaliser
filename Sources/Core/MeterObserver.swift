import Foundation

/// Identifies which meter type an observer wants to subscribe to.
enum MeterType: CaseIterable {
    case inputPeakLeft
    case inputPeakRight
    case inputRMSLeft
    case inputRMSRight
    case outputPeakLeft
    case outputPeakRight
    case outputRMSLeft
    case outputRMSRight
}

/// Protocol for objects that receive meter updates directly from MeterStore.
/// This bypasses SwiftUI's observation system for better performance.
@MainActor
protocol MeterObserver: AnyObject {
    /// Called when meter values change.
    /// - Parameters:
    ///   - value: The current peak or RMS value (normalized 0-1)
    ///   - hold: The peak hold value (normalized 0-1)
    ///   - clipping: Whether clipping is currently detected
    func meterUpdated(value: Float, hold: Float, clipping: Bool)
}

/// Wrapper to store weak references to observers.
struct WeakMeterObserver {
    weak var observer: MeterObserver?
}
