import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool

    var displayName: String { name }
}

@MainActor
final class DeviceManager: ObservableObject {
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []

    private nonisolated(unsafe) var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private let listenerBlockQueue = DispatchQueue(label: "com.example.EqualizerApp.DeviceManager.listener")

    init() {
        refreshDevices()
        setupDeviceChangeListener()
    }

    nonisolated func cleanupListener() {
        guard let block = deviceListenerBlock else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerBlockQueue,
            block
        )
    }

    deinit {
        cleanupListener()
    }

    private func setupDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        deviceListenerBlock = block

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerBlockQueue,
            block
        )

        if status != noErr {
            print("DeviceManager: Failed to add device change listener: \(status)")
        }
    }

    func refreshDevices() {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize) == noErr else {
            return
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs) == noErr else {
            return
        }

        var inputs: [AudioDevice] = []
        var outputs: [AudioDevice] = []

        for deviceID in deviceIDs {
            if let device = makeDevice(from: deviceID) {
                if device.isInput { inputs.append(device) }
                if device.isOutput { outputs.append(device) }
            }
        }

        inputDevices = inputs.sorted { $0.name < $1.name }
        outputDevices = outputs.sorted { $0.name < $1.name }
    }

    private func makeDevice(from id: AudioDeviceID) -> AudioDevice? {
        guard let uid = fetchStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID),
              let name = fetchStringProperty(id: id, selector: kAudioDevicePropertyDeviceNameCFString)
        else { return nil }

        guard shouldIncludeDevice(name: name) else {
            return nil
        }

        let hasInput = hasStreams(id: id, scope: kAudioDevicePropertyScopeInput)
        let hasOutput = hasStreams(id: id, scope: kAudioDevicePropertyScopeOutput)

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            isInput: hasInput,
            isOutput: hasOutput
        )
    }

    func shouldIncludeDevice(name: String) -> Bool {
        !name.hasPrefix("CADefaultDeviceAggregate")
    }

    private func getTransportType(id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &transportType) == noErr else {
            return 0
        }
        return transportType
    }

    private func fetchStringProperty(id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<UInt8>.alignment)
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, buffer) == noErr else {
            return nil
        }

        let unmanaged = buffer.bindMemory(to: Unmanaged<CFString>.self, capacity: 1)
        return unmanaged.pointee.takeRetainedValue() as String
    }

    private func hasStreams(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &address, 0, nil, &propertySize) != noErr {
            return false
        }
        return propertySize > 0
    }

    // MARK: - UID Resolution

    /// Returns the AudioDeviceID for a given UID, or nil if not found.
    /// - Parameter uid: The unique identifier string of the device.
    /// - Returns: The corresponding AudioDeviceID, or nil if no matching device exists.
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        // Check input devices first, then output devices
        if let device = inputDevices.first(where: { $0.uid == uid }) {
            return device.id
        }
        if let device = outputDevices.first(where: { $0.uid == uid }) {
            return device.id
        }
        return nil
    }

    /// Returns the AudioDevice for a given UID, or nil if not found.
    /// - Parameter uid: The unique identifier string of the device.
    /// - Returns: The corresponding AudioDevice, or nil if no matching device exists.
    func device(forUID uid: String) -> AudioDevice? {
        if let device = inputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        if let device = outputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        return nil
    }
}
