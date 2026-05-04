// DeviceEnumerationService.swift
// Device enumeration and discovery service

import Combine
import CoreAudio
import Foundation
import OSLog

/// Device enumeration service.
/// Provides cached lists of audio input/output devices and device lookup.
/// Emits change events when device enumeration changes in meaningful ways.
@MainActor
final class DeviceEnumerationService: ObservableObject, Enumerating {

    // MARK: - Dependencies

    /// Driver access for direct CoreAudio driver device lookup.
    /// Used to resolve driver UID without requiring input device enumeration.
    private let driverAccess: DriverAccessing?
    
    // MARK: - Published Properties
    
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    
    /// Latest device change event. Subscribers should read and clear.
    @Published private(set) var changeEvent: DeviceChangeEvent?
    
    // MARK: - State Tracking
    
    /// Previous built-in output device UIDs for Apple Silicon headphone detection.
    private var previousBuiltInDeviceUIDs: Set<String> = []
    
    /// Flag indicating if initial tracking state has been established.
    private var hasInitializedTracking = false
    
    /// The last selected output UID reported as missing.
    /// Used to avoid duplicate missing device reports.
    private var lastReportedMissingSelectedUID: String?
    
    /// Closure to get current selected output UID for missing device detection.
    var selectedOutputUIDProvider: (() -> String?)?
    
    /// Closure to check if manual mode is enabled (skips missing device detection).
    var manualModeProvider: (() -> Bool)?
    
    /// Closure to check if routing is reconfiguring (skips event emission).
    var isReconfiguringProvider: (() -> Bool)?
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var jackConnectionListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedJackDeviceID: AudioDeviceID?
    private let listenerBlockQueue = DispatchQueue(label: "net.knage.equaliser.DeviceEnumerationService.listener")
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceEnumerationService")
    
    /// Whether input devices have been enumerated yet.
    /// Input enumeration is deferred to avoid triggering TCC dialog on launch.
    private var hasEnumeratedInputDevices = false

    // MARK: - Initialization

    init(driverAccess: DriverAccessing? = nil) {
        self.driverAccess = driverAccess
        self.refreshOutputDevices()
        self.setupDeviceChangeListener()
        self.setupDefaultOutputListener()
        self.setupDriverInstallNotification()
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
            assertionFailure("DeviceEnumerationService: Failed to add device change listener: \(status)")
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
            assertionFailure("DeviceEnumerationService: Failed to add default output listener: \(status)")
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
    }
    
    // MARK: - Device Enumeration

    /// Refreshes both input and output devices.
    /// Note: Only enumerates input devices if they've been enumerated before,
    /// to avoid triggering TCC permission dialog unexpectedly.
    func refreshDevices() {
        refreshOutputDevices()
        // Only refresh input devices if they've been enumerated before
        // (permission was granted or user requested it)
        if hasEnumeratedInputDevices {
            refreshInputDevices()
        }
    }

    /// Refreshes output devices only.
    /// Safe to call during app initialization - does NOT trigger TCC dialog.
    func refreshOutputDevices() {
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

        var outputs: [AudioDevice] = []

        for deviceID in deviceIDs {
            // Only check output streams - avoids TCC trigger
            if let device = makeOutputDevice(from: deviceID) {
                outputs.append(device)
            }
        }

        outputDevices = outputs.sorted { $0.name < $1.name }

        // Process device changes and emit events
        processDeviceChanges()
    }

    /// Refreshes input devices only.
    /// May trigger TCC permission dialog for microphone access.
    /// Should only be called after microphone permission is granted or when needed.
    func refreshInputDevices() {
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

        for deviceID in deviceIDs {
            // Check input streams - may trigger TCC
            if let device = makeInputDevice(from: deviceID) {
                inputs.append(device)
            }
        }

        inputDevices = inputs.sorted { $0.name < $1.name }
        hasEnumeratedInputDevices = true

        logger.info("Enumerated \(inputs.count) input device(s)")
    }

    /// Enumerates input devices on demand.
    /// Call this when microphone permission is granted or when switching to manual mode.
    /// May trigger TCC permission dialog for microphone access.
    func enumerateInputDevices() {
        refreshInputDevices()
    }
    
    /// Processes device enumeration changes and emits appropriate events.
    /// Detects built-in device additions/removals (Apple Silicon headphone detection)
    /// and missing selected output device.
    private func processDeviceChanges() {
        // Skip event emission during reconfiguration
        guard isReconfiguringProvider?() != true else { return }
        
        // Skip event emission in manual mode (user handles device selection)
        guard manualModeProvider?() != true else { return }
        
        // Get built-in output devices
        let builtInDevices = outputDevices.filter { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        let currentBuiltInUIDs = Set(builtInDevices.map { $0.uid })
        
        // Initialize tracking on first run
        if !hasInitializedTracking {
            previousBuiltInDeviceUIDs = currentBuiltInUIDs
            hasInitializedTracking = true
            logger.debug("Initialized device tracking with \(builtInDevices.count) built-in device(s)")
            
            // Check for missing selected device on first run
            checkForMissingSelectedDevice()
            return
        }
        
        // Compute built-in device diffs (Apple Silicon headphone detection)
        let addedBuiltInUIDs = currentBuiltInUIDs.subtracting(previousBuiltInDeviceUIDs)
        let removedBuiltInUIDs = previousBuiltInDeviceUIDs.subtracting(currentBuiltInUIDs)
        
        // Log diff summary
        if !addedBuiltInUIDs.isEmpty || !removedBuiltInUIDs.isEmpty {
            logger.debug("Built-in device diff: +\(addedBuiltInUIDs.count), -\(removedBuiltInUIDs.count)")
        }
        
        // Handle single built-in device added (headphones plugged in)
        if addedBuiltInUIDs.count == 1,
           let addedUID = addedBuiltInUIDs.first,
           let addedDevice = builtInDevices.first(where: { $0.uid == addedUID }) {
            logger.info("Built-in device added: '\(addedDevice.name)'")
            changeEvent = .builtInDeviceAdded(addedDevice)
        } else if addedBuiltInUIDs.count > 1 {
            logger.debug("Multiple built-in devices added (\(addedBuiltInUIDs.count)), ignoring")
        }
        
        // Handle built-in devices removed (headphones unplugged)
        if !removedBuiltInUIDs.isEmpty {
            logger.info("Built-in device(s) removed: \(removedBuiltInUIDs.count)")
            // Clear missing tracking immediately so checkForMissingSelectedDevice()
            // can properly detect the missing device. This also ensures tracking is
            // cleared even if the Combine pipeline doesn't deliver the event.
            clearMissingTracking()
            changeEvent = .builtInDevicesRemoved
        }
        
        // Update tracking
        previousBuiltInDeviceUIDs = currentBuiltInUIDs
        
        // Check for missing selected output device
        checkForMissingSelectedDevice()
    }
    
    /// Checks if the currently selected output device is missing.
    private func checkForMissingSelectedDevice() {
        guard let selectedUID = selectedOutputUIDProvider?() else { return }
        
        let deviceExists = outputDevices.contains { $0.uid == selectedUID }
        
        if !deviceExists {
            // Only report if not already reported
            if lastReportedMissingSelectedUID != selectedUID {
                lastReportedMissingSelectedUID = selectedUID
                logger.info("Selected output device missing: \(selectedUID)")
                changeEvent = .selectedOutputMissing(uid: selectedUID)
            }
        } else {
            // Clear tracking if device is back
            if lastReportedMissingSelectedUID == selectedUID {
                lastReportedMissingSelectedUID = nil
            }
        }
    }
    
    /// Clears the missing device tracking.
    /// Call when device is restored or headphones unplugged.
    func clearMissingTracking() {
        lastReportedMissingSelectedUID = nil
    }
    
    /// Creates an AudioDevice checking ONLY output streams.
    /// Safe to call during initialization - does NOT trigger TCC.
    private func makeOutputDevice(from id: AudioDeviceID) -> AudioDevice? {
        guard let uid = fetchStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID),
              let name = fetchStringProperty(id: id, selector: kAudioDevicePropertyDeviceNameCFString)
        else { return nil }

        guard shouldIncludeDevice(name: name) else {
            return nil
        }

        // Only check output streams - avoids TCC trigger
        let hasOutput = hasStreams(id: id, scope: kAudioDevicePropertyScopeOutput)
        guard hasOutput else { return nil }

        // Exclude Equaliser driver from outputs (can't route to itself)
        guard uid != DRIVER_DEVICE_UID else { return nil }

        let transportType = fetchTransportType(id: id)

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            transportType: transportType
        )
    }

    /// Creates an AudioDevice checking ONLY input streams.
    /// May trigger TCC permission dialog.
    private func makeInputDevice(from id: AudioDeviceID) -> AudioDevice? {
        guard let uid = fetchStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID),
              let name = fetchStringProperty(id: id, selector: kAudioDevicePropertyDeviceNameCFString)
        else { return nil }

        guard shouldIncludeDevice(name: name) else {
            return nil
        }

        // Check input streams - may trigger TCC
        let hasInput = hasStreams(id: id, scope: kAudioDevicePropertyScopeInput)
        guard hasInput else { return nil }

        let transportType = fetchTransportType(id: id)

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            transportType: transportType
        )
    }
    
    func shouldIncludeDevice(name: String) -> Bool {
        !name.hasPrefix("CADefaultDeviceAggregate")
    }
    
    // MARK: - Device Lookup

    func device(forUID uid: String) -> AudioDevice? {
        // Special case: driver UID - use CoreAudio directly (driver may not be in cached list)
        // This allows driver lookup in automatic mode without enumerating input devices (TCC avoidance)
        if uid == DRIVER_DEVICE_UID, let driverID = driverAccess?.deviceID {
            return AudioDevice(
                id: driverID,
                uid: DRIVER_DEVICE_UID,
                name: DRIVER_DEFAULT_NAME,
                transportType: kAudioDeviceTransportTypeVirtual
            )
        }

        // Check output devices first (most common lookup)
        if let device = outputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        // Then check input devices
        if let device = inputDevices.first(where: { $0.uid == uid }) {
            return device
        }
        // Device not found in cached lists - log for diagnostics
        logger.warning("Device not found for UID: \(uid) - searched \(self.outputDevices.count) output devices, \(self.inputDevices.count) input devices")
        return nil
    }

    func deviceID(forUID uid: String) -> AudioDeviceID? {
        device(forUID: uid)?.id
    }
    
    // MARK: - Special Device Discovery

    func findBuiltInAudioDevice() -> AudioDevice? {
        // Find built-in output device using transport type
        return outputDevices.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
    }
    
    func findBlackHoleDevice() -> AudioDevice? {
        inputDevices.first { $0.name.contains("BlackHole") }
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

        // Get the system default but exclude the Equaliser driver
        let systemDefault = outputDevices.first { $0.id == deviceID }
        if let device = systemDefault, device.isValidForSelection {
            return device
        }

        // Fall back to first valid output device (excludes driver only)
        return outputDevices.first(where: { $0.isValidForSelection })
    }
    
    func currentSystemDefaultOutputDevice() -> AudioDevice? {
        defaultOutputDevice()
    }
    
    // MARK: - Jack Connection Listener (Intel Macs)
    
    /// Sets up a listener for jack connection changes on the specified built-in audio device.
    /// Emits .builtInDeviceAdded/.builtInDevicesRemoved events when jack state changes (Intel Macs only).
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
        guard let deviceID = observedJackDeviceID else { return }
        guard let jackConnected = isJackConnected(deviceID) else { return }
        
        // Find the built-in device by ID
        guard let builtInDevice = outputDevices.first(where: { $0.id == deviceID }) else {
            logger.warning("Jack connection changed but device not found in output list")
            return
        }
        
        if jackConnected {
            logger.info("Headphones plugged in (jack) - '\(builtInDevice.name)'")
            changeEvent = .builtInDeviceAdded(builtInDevice)
        } else {
            logger.info("Headphones unplugged (jack)")
            changeEvent = .builtInDevicesRemoved
            // Clear missing tracking so we can detect if current device is missing
            clearMissingTracking()
        }
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