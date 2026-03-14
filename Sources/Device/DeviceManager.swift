import Foundation
import CoreAudio
import os.log

// MARK: - CoreAudio Constants
// These are defined in CoreAudio headers but not directly accessible in Swift
private let kAudioHardwareServiceDeviceProperty_VirtualMasterVolume: AudioObjectPropertySelector = 0x00006d76  // mvmt
private let kAudioHardwareServiceDeviceProperty_VirtualMasterMute: AudioObjectPropertySelector = 0x00006d6d  // mdmt
private let kAudioDevicePropertyOwnedObjects: AudioObjectPropertySelector = 0x6f6f776e  // oown

// MARK: - Transport Type Constants
// CoreAudio device transport types (4-char codes as UInt32)
private let kAudioDeviceTransportTypeVirtual: UInt32 = 0x76697274    // 'virt'
private let kAudioDeviceTransportTypeAggregate: UInt32 = 0x61676720  // 'agg '

extension Notification.Name {
    static let systemDefaultOutputDidChange = Notification.Name("net.knage.equaliser.systemDefaultOutputDidChange")
}

struct AudioDevice: Identifiable, Equatable {
     let id: AudioDeviceID
     let uid: String
     let name: String
     let isInput: Bool
     let isOutput: Bool
     let transportType: UInt32

     var displayName: String { name }
     
     /// Returns true if this device is a virtual device (not physical hardware).
     /// Uses transport type when available, falls back to UID prefix for known virtual drivers.
     var isVirtual: Bool {
         // Primary: Check transport type
         if transportType == kAudioDeviceTransportTypeVirtual {
             return true
         }
         // Fallback: Known virtual device UIDs (for drivers that don't set transport type)
         return uid.hasPrefix("Equaliser") || uid.hasPrefix("BlackHole")
     }
     
     /// Returns true if this device is an aggregate or multi-output device.
     /// Uses CoreAudio transport type for reliable detection.
     var isAggregate: Bool {
         transportType == kAudioDeviceTransportTypeAggregate
     }
}

@MainActor
final class DeviceManager: ObservableObject {
     @Published private(set) var inputDevices: [AudioDevice] = []
     @Published private(set) var outputDevices: [AudioDevice] = []

     private nonisolated(unsafe) var deviceListenerBlock: AudioObjectPropertyListenerBlock?
     private nonisolated(unsafe) var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
     private let listenerBlockQueue = DispatchQueue(label: "net.knage.equaliser.DeviceManager.listener")
     private let logger = Logger(subsystem: "net.knage.equaliser", category: "DeviceManager")

     init() {
         refreshDevices()
         setupDeviceChangeListener()
         setupDefaultOutputListener()
         setupDriverInstallNotification()
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
             assertionFailure("DeviceManager: Failed to add device change listener: \(status)")
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
             assertionFailure("DeviceManager: Failed to add default output listener: \(status)")
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
        // Refresh devices after driver installation
        refreshDevices()
    }

    @objc private func driverDidUninstall() {
        // Refresh devices after driver uninstallation
        refreshDevices()
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

    private func fetchTransportType(id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transportType) == noErr else {
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

    /// Finds a device by UID, even if hidden from enumeration.
    /// Uses kAudioHardwarePropertyTranslateUIDToDevice to locate hidden devices.
    /// - Parameter uid: The device UID to search for.
    /// - Returns: The AudioDevice if found, nil otherwise.
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
        // Fallback: try hidden device lookup via CoreAudio
        if let device = findDeviceByUID(uid) {
            return device.id
        }
        logger.warning("Device not found for UID: \(uid)")
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
        // Fallback: try hidden device lookup via CoreAudio
        return findDeviceByUID(uid)
    }

    // MARK: - Default Device Detection

     /// Finds the built-in Equaliser virtual audio driver among input devices.
     /// - Returns: The Equaliser driver device if found, nil otherwise.
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
    func findBlackHoleDevice() -> AudioDevice? {
        inputDevices.first { $0.name.contains("BlackHole") }
    }

    /// Returns the best available input device for EQ routing.
    /// Priority: Equaliser driver > BlackHole > first input device
    /// - Returns: The best input device for EQ, nil if none available.
    func bestInputDeviceForEQ() -> AudioDevice? {
        if let driver = findEqualiserDriverDevice() {
            return driver
        }
        if let blackHole = findBlackHoleDevice() {
            return blackHole
        }
        return inputDevices.first
    }

     /// Returns the system default output device, excluding virtual devices.
      /// Uses kAudioHardwarePropertyDefaultOutputDevice.
      /// - Returns: The default output device if available and not a virtual device, nil otherwise.
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

     /// Returns the system default output device as AudioDevice, or nil if not available.
     /// This is a convenience wrapper around defaultOutputDevice() that ensures it returns
     /// the full AudioDevice with all metadata.
     /// - Returns: The audio device if available and not virtual, nil otherwise.
     func currentSystemDefaultOutputDevice() -> AudioDevice? {
         defaultOutputDevice()
     }
     
     // MARK: - Static Device Selection Helpers
     
     /// Selects the best fallback output device from a list of available devices.
     /// Prefers built-in speakers over other non-virtual, non-aggregate devices.
     /// - Parameter devices: Array of available output devices to choose from.
     /// - Returns: The best fallback device, or nil if no suitable device is found.
     public static func selectFallbackOutputDevice(from devices: [AudioDevice]) -> AudioDevice? {
         // Prefer built-in speakers
         if let builtIn = devices.first(where: { device in
             let name = device.name.lowercased()
             return (name.contains("built-in") || name.contains("speakers")) &&
                    !device.isVirtual &&
                    !device.isAggregate
         }) {
             return builtIn
         }
         
         // Fallback: first non-virtual, non-aggregate
         return devices.first { !$0.isVirtual && !$0.isAggregate }
     }
     
     // MARK: - Sample Rate Queries
     
     /// Returns the actual (running) sample rate of a device.
     /// - Parameter deviceID: The AudioDeviceID to query.
     /// - Returns: The sample rate in Hz, or nil if unavailable.
     func getActualSampleRate(deviceID: AudioDeviceID) -> Float64? {
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyActualSampleRate,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var rate: Float64 = 0
         var size = UInt32(MemoryLayout<Float64>.size)
         
         guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr else {
             return nil
         }
         
         return rate
     }
     
     /// Returns the nominal sample rate of a device.
     /// - Parameter deviceID: The AudioDeviceID to query.
     /// - Returns: The sample rate in Hz, or nil if unavailable.
     func getNominalSampleRate(deviceID: AudioDeviceID) -> Float64? {
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyNominalSampleRate,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var rate: Float64 = 0
         var size = UInt32(MemoryLayout<Float64>.size)
         
         guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr else {
             return nil
         }
         
         return rate
     }
     
     // MARK: - Sample Rate Change Listener
     
     private nonisolated(unsafe) var sampleRateListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
     
     /// Observes sample rate changes on a specific device.
     /// Monitors NominalSampleRate which is what users change in Audio MIDI Setup.
     /// - Parameters:
     ///   - deviceID: The device to monitor.
     ///   - handler: Called with the new sample rate when it changes.
     func observeSampleRateChanges(on deviceID: AudioDeviceID, handler: @escaping (Float64) -> Void) {
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyNominalSampleRate,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
             guard let self = self else { return }
             if let rate = self.getNominalSampleRate(deviceID: deviceID) {
                 Task { @MainActor in
                     handler(rate)
                 }
             }
         }
         
         sampleRateListenerBlocks[deviceID] = block
         
         let status = AudioObjectAddPropertyListenerBlock(
             deviceID,
             &address,
             listenerBlockQueue,
             block
         )
         
         if status != noErr {
             logger.warning("Failed to observe sample rate changes on device \(deviceID): \(status)")
         }
     }
     
     /// Stops observing sample rate changes on a device.
     /// - Parameter deviceID: The device to stop monitoring.
     func stopObservingSampleRateChanges(on deviceID: AudioDeviceID) {
         guard let block = sampleRateListenerBlocks.removeValue(forKey: deviceID) else { return }
         
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyNominalSampleRate,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         AudioObjectRemovePropertyListenerBlock(
             deviceID,
             &address,
             listenerBlockQueue,
             block
         )
     }
     
     // MARK: - Volume Control
     
     /// Gets the virtual master volume for a device (0.0 - 1.0).
     /// Uses kAudioHardwareServiceDeviceProperty_VirtualMasterVolume if available,
     /// falls back to averaging channel volumes.
     /// - Parameter deviceID: The device to query.
     /// - Returns: Volume as scalar 0.0-1.0, or nil if unavailable.
     func getVirtualMasterVolume(deviceID: AudioDeviceID) -> Float? {
         // Try virtual master volume property first (modern devices)
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
             mScope: kAudioDevicePropertyScopeOutput,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var volume: Float32 = 1.0
         var size = UInt32(MemoryLayout<Float32>.size)
         
         if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
             return volume
         }
         
         // Fall back to getting volume from control objects
         return getVolumeFromControlObject(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput)
     }
     
     /// Sets the virtual master volume for a device (0.0 - 1.0).
     /// - Parameters:
     ///   - deviceID: The device to set volume on.
     ///   - volume: Volume as scalar 0.0-1.0.
     /// - Returns: True on success.
     @discardableResult
     func setVirtualMasterVolume(deviceID: AudioDeviceID, volume: Float) -> Bool {
         // Try virtual master volume property first
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
             mScope: kAudioDevicePropertyScopeOutput,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var vol = volume
         let status = AudioObjectSetPropertyData(
             deviceID,
             &address,
             0,
             nil,
             UInt32(MemoryLayout<Float32>.size),
             &vol
         )
         
         if status == noErr {
             return true
         }
         
         // Fall back to setting volume on control objects
         return setVolumeOnControlObject(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput, volume: volume)
     }
     
     /// Gets the mute state for a device.
     /// - Parameter deviceID: The device to query.
     /// - Returns: True if muted, false if not muted, nil if unavailable.
     func getMute(deviceID: AudioDeviceID) -> Bool? {
         // Try virtual master mute property first
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterMute,
             mScope: kAudioDevicePropertyScopeOutput,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var muted: UInt32 = 0
         var size = UInt32(MemoryLayout<UInt32>.size)
         
         if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr {
             return muted != 0
         }
         
          // Fall back to mute control object
          return getMuteFromControlObject(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput)
     }
     
     // MARK: - Mute Change Listener
     
     private nonisolated(unsafe) var muteListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
     
     /// Observes mute state changes on a device.
     /// - Parameters:
     ///   - deviceID: The device to monitor.
     ///   - handler: Called with new mute state when it changes.
     func observeMuteChanges(on deviceID: AudioDeviceID, handler: @escaping (Bool) -> Void) {
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterMute,
             mScope: kAudioDevicePropertyScopeOutput,
             mElement: kAudioObjectPropertyElementMain
         )
         
         let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
             guard let self = self else { return }
             if let muted = self.getMute(deviceID: deviceID) {
                 Task { @MainActor in
                     handler(muted)
                 }
             }
         }
         
         muteListenerBlocks[deviceID] = block
         
         let status = AudioObjectAddPropertyListenerBlock(
             deviceID,
             &address,
             listenerBlockQueue,
             block
         )
         
         if status != noErr {
             logger.warning("Failed to observe mute changes on device \(deviceID): \(status)")
         }
     }
     
      /// Stops observing mute changes on a device.
      /// - Parameter deviceID: The device to stop monitoring.
      func stopObservingMuteChanges(on deviceID: AudioDeviceID) {
          guard let block = muteListenerBlocks.removeValue(forKey: deviceID) else { return }
          
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterMute,
              mScope: kAudioDevicePropertyScopeOutput,
              mElement: kAudioObjectPropertyElementMain
          )
          
          AudioObjectRemovePropertyListenerBlock(
              deviceID,
              &address,
              listenerBlockQueue,
              block
          )
      }
      
      // MARK: - Device-Level Volume (kAudioDevicePropertyVolumeScalar)
      
      private nonisolated(unsafe) var deviceVolumeListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
      
      private let kAudioDevicePropertyVolumeScalar: AudioObjectPropertySelector = 0x766F6C6D  // 'volm'
      
       func getDeviceVolumeScalar(deviceID: AudioDeviceID) -> Float? {
           // Try VolumeScalar first
           var address = AudioObjectPropertyAddress(
               mSelector: kAudioDevicePropertyVolumeScalar,
               mScope: kAudioDevicePropertyScopeOutput,
               mElement: kAudioObjectPropertyElementMain
           )
           
           var volume: Float32 = 0
           var size = UInt32(MemoryLayout<Float32>.size)
           
           if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
               return volume
           }
           
           // Fallback to VirtualMasterVolume (common for real audio output devices)
           if let vmv = getVirtualMasterVolume(deviceID: deviceID) {
               logger.debug("getDeviceVolumeScalar: using VirtualMasterVolume fallback for device \(deviceID)")
               return vmv
           }
           
           logger.warning("getDeviceVolumeScalar: failed for device \(deviceID)")
           return nil
       }
      
       @discardableResult
       func setDeviceVolumeScalar(deviceID: AudioDeviceID, volume: Float) -> Bool {
           // Try VolumeScalar first
           var address = AudioObjectPropertyAddress(
               mSelector: kAudioDevicePropertyVolumeScalar,
               mScope: kAudioDevicePropertyScopeOutput,
               mElement: kAudioObjectPropertyElementMain
           )
           
           var volumeValue = volume
           let size = UInt32(MemoryLayout<Float32>.size)
           
           if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volumeValue) == noErr {
               return true
           }
           
            // Fallback to VirtualMasterVolume (common for real audio output devices)
            logger.debug("setDeviceVolumeScalar: VolumeScalar failed for device \(deviceID), trying VirtualMasterVolume")
            return setVirtualMasterVolume(deviceID: deviceID, volume: volume)
        }
      
      func observeDeviceVolumeChanges(deviceID: AudioDeviceID, handler: @escaping (Float) -> Void) {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyVolumeScalar,
              mScope: kAudioDevicePropertyScopeOutput,
              mElement: kAudioObjectPropertyElementMain
          )
          
          let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
              guard let self = self else { return }
              if let volume = self.getDeviceVolumeScalar(deviceID: deviceID) {
                  Task { @MainActor in
                      handler(volume)
                  }
              }
          }
          
          deviceVolumeListenerBlocks[deviceID] = block
          
          let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerBlockQueue, block)
          
          if status != noErr {
              logger.error("observeDeviceVolumeChanges: Failed to register listener on device \(deviceID): error \(status)")
          } else {
              logger.info("observeDeviceVolumeChanges: Registered listener on device \(deviceID)")
          }
      }
      
      func stopObservingDeviceVolumeChanges(deviceID: AudioDeviceID) {
          guard let block = deviceVolumeListenerBlocks.removeValue(forKey: deviceID) else { return }
          
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyVolumeScalar,
              mScope: kAudioDevicePropertyScopeOutput,
              mElement: kAudioObjectPropertyElementMain
          )
          
          AudioObjectRemovePropertyListenerBlock(deviceID, &address, listenerBlockQueue, block)
      }
      
      // MARK: - Device-Level Mute
      
      private nonisolated(unsafe) var deviceMuteListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
      
      private let kAudioDevicePropertyMute: AudioObjectPropertySelector = 0x6D757465  // 'mute'
      
      func getDeviceMute(deviceID: AudioDeviceID) -> Bool? {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyMute,
              mScope: kAudioDevicePropertyScopeOutput,
              mElement: kAudioObjectPropertyElementMain
          )
          
          var muted: UInt32 = 0
          var size = UInt32(MemoryLayout<UInt32>.size)
          
          guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else {
              return nil
          }
          
          return muted != 0
      }
      
      @discardableResult
      func setDeviceMute(deviceID: AudioDeviceID, muted: Bool) -> Bool {
          var address = AudioObjectPropertyAddress(
              mSelector: kAudioDevicePropertyMute,
              mScope: kAudioDevicePropertyScopeOutput,
              mElement: kAudioObjectPropertyElementMain
          )
          
          var muteValue: UInt32 = muted ? 1 : 0
          let size = UInt32(MemoryLayout<UInt32>.size)
          
          return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muteValue) == noErr
      }
      
      // MARK: - Private Volume Control Helpers
     
     /// Gets volume from a control object owned by the device.
     private func getVolumeFromControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
         // Get owned objects (controls) for the scope
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyOwnedObjects,
             mScope: scope,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var qualifier = AudioClassID(kAudioVolumeControlClassID)
         var size: UInt32 = 0
         
         // Get size first
         guard AudioObjectGetPropertyDataSize(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size) == noErr else {
             return nil
         }
         
         let controlCount = Int(size) / MemoryLayout<AudioObjectID>.size
         guard controlCount > 0 else { return nil }
         
         var controls = [AudioObjectID](repeating: 0, count: controlCount)
         guard AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size, &controls) == noErr else {
             return nil
         }
         
         // Get volume from the first volume control
         for controlID in controls {
             if let volume = getVolumeFromControl(controlID: controlID) {
                 return volume
             }
         }
         
         return nil
     }
     
     /// Gets volume from a specific control object.
     private func getVolumeFromControl(controlID: AudioObjectID) -> Float? {
         var volumeAddress = AudioObjectPropertyAddress(
             mSelector: kAudioLevelControlPropertyScalarValue,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var volume: Float32 = 1.0
         var size = UInt32(MemoryLayout<Float32>.size)
         
         guard AudioObjectGetPropertyData(controlID, &volumeAddress, 0, nil, &size, &volume) == noErr else {
             return nil
         }
         
         return volume
     }
     
     /// Sets volume on a control object owned by the device.
     private func setVolumeOnControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, volume: Float) -> Bool {
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyOwnedObjects,
             mScope: scope,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var qualifier = AudioClassID(kAudioVolumeControlClassID)
         var size: UInt32 = 0
         
         guard AudioObjectGetPropertyDataSize(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size) == noErr else {
             return false
         }
         
         let controlCount = Int(size) / MemoryLayout<AudioObjectID>.size
         guard controlCount > 0 else { return false }
         
         var controls = [AudioObjectID](repeating: 0, count: controlCount)
         guard AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size, &controls) == noErr else {
             return false
         }
         
         // Set volume on all volume controls
         var success = false
         for controlID in controls {
             if setVolumeOnControl(controlID: controlID, volume: volume) {
                 success = true
             }
         }
         
         return success
     }
     
     /// Sets volume on a specific control object.
     private func setVolumeOnControl(controlID: AudioObjectID, volume: Float) -> Bool {
         var volumeAddress = AudioObjectPropertyAddress(
             mSelector: kAudioLevelControlPropertyScalarValue,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var vol = volume
         let status = AudioObjectSetPropertyData(
             controlID,
             &volumeAddress,
             0,
             nil,
             UInt32(MemoryLayout<Float32>.size),
             &vol
         )
         
         return status == noErr
     }
     
     /// Gets mute state from a control object owned by the device.
     private func getMuteFromControlObject(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool? {
         var address = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyOwnedObjects,
             mScope: scope,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var qualifier = AudioClassID(kAudioMuteControlClassID)
         var size: UInt32 = 0
         
         guard AudioObjectGetPropertyDataSize(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size) == noErr else {
             return nil
         }
         
         let controlCount = Int(size) / MemoryLayout<AudioObjectID>.size
         guard controlCount > 0 else { return nil }
         
         var controls = [AudioObjectID](repeating: 0, count: controlCount)
         guard AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout<AudioClassID>.size), &qualifier, &size, &controls) == noErr else {
             return nil
         }
         
         for controlID in controls {
             if let muted = getMuteFromControl(controlID: controlID) {
                 return muted
             }
         }
         
         return nil
     }
     
     /// Gets mute state from a specific control object.
     private func getMuteFromControl(controlID: AudioObjectID) -> Bool? {
         var muteAddress = AudioObjectPropertyAddress(
             mSelector: kAudioBooleanControlPropertyValue,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain
         )
         
         var muted: UInt32 = 0
         var size = UInt32(MemoryLayout<UInt32>.size)
         
         guard AudioObjectGetPropertyData(controlID, &muteAddress, 0, nil, &size, &muted) == noErr else {
             return nil
         }
         
          return muted != 0
     }
     
  }
