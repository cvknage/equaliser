// DeviceEnumerator.swift
// Device enumeration and discovery service

import Foundation
import CoreAudio
import os.log

/// Device enumeration service.
/// Provides cached lists of audio input/output devices and device lookup.
@MainActor
final class DeviceEnumerator: ObservableObject, DeviceEnumerating {
    
    // MARK: - Published Properties
    
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var jackConnectionListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedJackDeviceID: AudioDeviceID?
    private let listenerBlockQueue = DispatchQueue(label: "net.knage.equaliser.DeviceEnumerator.listener")
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceEnumerator")
    
    // MARK: - Initialization
    
    init() {
        refreshDevices()
        setupDeviceChangeListener()
        setupDefaultOutputListener()
        setupDriverInstallNotification()
    }
    
    deinit {
        cleanupListener()
    }
    
    // MARK: - Listener Setup
    
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
            assertionFailure("DeviceEnumerator: Failed to add device change listener: \(status)")
        }
    }

    private func setupDefaultOutputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .systemDefaultOutputDidChange, object: nil)
            }
        }

        defaultOutputListenerBlock = block

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerBlockQueue,
            block
        )

        if status != noErr {
            assertionFailure("DeviceEnumerator: Failed to add default output listener: \(status)")
        }
    }

    private func setupDriverInstallNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(driverDidInstall),
            name: .driverDidInstall,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(driverDidUninstall),
            name: .driverDidUninstall,
            object: nil
        )
    }

    @objc private func driverDidInstall() {
        refreshDevices()
    }

    @objc private func driverDidUninstall() {
        refreshDevices()
    }
    
    // MARK: - Cleanup
    
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

        if let defaultBlock = defaultOutputListenerBlock {
            var defaultAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddress,
                listenerBlockQueue,
                defaultBlock
            )
        }
        
        // Note: Jack connection listener is cleaned up separately via cleanupJackConnectionListener()
        // which is called from AudioRoutingCoordinator.stopPipeline()
    }
    
    // MARK: - Device Enumeration

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
                // Exclude Equaliser driver from outputs (can't route to itself)
                if device.isOutput && device.uid != DRIVER_DEVICE_UID { outputs.append(device) }
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
        let transportType = fetchTransportType(id: id)

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            isInput: hasInput,
            isOutput: hasOutput,
            transportType: transportType
        )
    }
    
    func shouldIncludeDevice(name: String) -> Bool {
        !name.hasPrefix("CADefaultDeviceAggregate")
    }
    
    // MARK: - Device Lookup
    
    func findDeviceByUID(_ uid: String) -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let cfUid: CFString = uid as CFString
        let uidPtr = Unmanaged.passUnretained(cfUid).toOpaque()

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<CFString>.size),
            uidPtr,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        // If found in enumeration, return cached device
        if let cached = inputDevices.first(where: { $0.uid == uid }) {
            return cached
        }
        if let cached = outputDevices.first(where: { $0.uid == uid }) {
            return cached
        }

        // Build device from ID for hidden devices
        return makeDevice(from: deviceID)
    }
    
    func device(forUID uid: String) -> AudioDevice? {
        if let device = inputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        if let device = outputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        // Fallback: try hidden device lookup via CoreAudio
        return findDeviceByUID(uid)
    }
    
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        // Check input devices first, then output devices
        if let device = inputDevices.first(where: { $0.uid == uid }) {
            return device.id
        }
        if let device = outputDevices.first(where: { $0.uid == uid }) {
            return device.id
        }
        // Fallback: try hidden device lookup via CoreAudio
        if let device = findDeviceByUID(uid) {
            return device.id
        }
        logger.warning("Device not found for UID: \(uid)")
        return nil
    }
    
    // MARK: - Special Device Discovery
    
    func findEqualiserDriverDevice() -> AudioDevice? {
        // Try exact UID match first
        if let device = inputDevices.first(where: { $0.uid == DRIVER_DEVICE_UID }) {
            return device
        }
        // Fallback: match by name (handles UID format variations)
        if let device = inputDevices.first(where: { $0.name == DRIVER_DEFAULT_NAME || $0.name == "Equaliser" }) {
            return device
        }

        // Fallback: find hidden device via CoreAudio TranslateUIDToDevice
        return findDeviceByUID(DRIVER_DEVICE_UID)
    }
    
    func findBuiltInAudioDevice() -> AudioDevice? {
        // Find built-in output device using transport type
        return outputDevices.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
    }
    
    func findBlackHoleDevice() -> AudioDevice? {
        inputDevices.first { $0.name.contains("BlackHole") }
    }
    
    func bestInputDeviceForEQ() -> AudioDevice? {
        if let driver = findEqualiserDriverDevice() {
            return driver
        }
        if let blackHole = findBlackHoleDevice() {
            return blackHole
        }
        return inputDevices.first
    }
    
    // MARK: - Default Device
    
    func defaultOutputDevice() -> AudioDevice? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }

        // Get the system default but exclude virtual devices (Equaliser driver, BlackHole)
        let systemDefault = outputDevices.first { $0.id == deviceID }
        if let device = systemDefault, !device.isVirtual {
            return device
        }

        // Fall back to first non-virtual output device
        return outputDevices.first(where: { !$0.isVirtual })
    }
    
    func currentSystemDefaultOutputDevice() -> AudioDevice? {
        defaultOutputDevice()
    }
    
    // MARK: - Jack Connection Listener (Intel Macs)
    
    /// Sets up a listener for jack connection changes on the specified built-in audio device.
    /// Posts .jackConnectionChanged notification when jack state changes.
    /// - Parameter deviceID: The audio device ID to monitor (should be built-in device)
    func setupJackConnectionListener(for deviceID: AudioDeviceID) {
        cleanupJackConnectionListener()
        
        // Check if device supports jack connection property
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyJackIsConnected,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectHasProperty(deviceID, &address) else {
            // Apple Silicon doesn't support this property - uses device enumeration changes instead
            return
        }
        
        // Log current jack state for diagnostics
        if let connected = isJackConnected(deviceID) {
            logger.debug("Jack listener set up, current state: \(connected ? "connected" : "disconnected")")
        }
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleJackConnectionChange()
            }
        }
        
        jackConnectionListenerBlock = block
        observedJackDeviceID = deviceID
        
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            listenerBlockQueue,
            block
        )
        
        if status != noErr {
            logger.error("Failed to set up jack listener: \(status)")
        }
    }
    
    private func handleJackConnectionChange() {
        guard observedJackDeviceID != nil else { return }
        
        // Post notification for AudioRoutingCoordinator to handle
        NotificationCenter.default.post(name: .jackConnectionChanged, object: nil)
    }
    
    func cleanupJackConnectionListener() {
        guard let deviceID = observedJackDeviceID else { return }
        
        if let block = jackConnectionListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyJackIsConnected,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, listenerBlockQueue, block)
            jackConnectionListenerBlock = nil
        }
        
        observedJackDeviceID = nil
    }
}