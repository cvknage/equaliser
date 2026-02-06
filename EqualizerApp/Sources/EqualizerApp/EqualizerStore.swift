import Foundation

@MainActor
final class EqualizerStore: ObservableObject {
    @Published var isBypassed: Bool = false {
        didSet {
            persist()
            audioEngine?.setBypassed(isBypassed)
        }
    }

    @Published var selectedInputDeviceID: String? {
        didSet { persist() }
    }

    @Published var selectedOutputDeviceID: String? {
        didSet { persist() }
    }

    private let smoother = ParameterSmoother()

    var audioEngine: AudioEngineManager? {
        didSet {
            audioEngine?.setBypassed(isBypassed)
        }
    }

    private let storage = UserDefaults.standard
    private enum Keys {
        static let bypass = "equalizer.bypass"
        static let inputDevice = "equalizer.input"
        static let outputDevice = "equalizer.output"
    }

    init() {
        isBypassed = storage.bool(forKey: Keys.bypass)
        selectedInputDeviceID = storage.string(forKey: Keys.inputDevice)
        selectedOutputDeviceID = storage.string(forKey: Keys.outputDevice)
    }

    private func persist() {
        storage.set(isBypassed, forKey: Keys.bypass)
        storage.set(selectedInputDeviceID, forKey: Keys.inputDevice)
        storage.set(selectedOutputDeviceID, forKey: Keys.outputDevice)
    }
}
