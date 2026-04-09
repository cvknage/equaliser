//  DriverConstants.swift
//  Equaliser
//
//  Constants for the built-in virtual audio driver

import Foundation
import CoreAudio

// MARK: - Driver Bundle Info

/// Bundle identifier for the Equaliser driver
public let DRIVER_BUNDLE_ID = "net.knage.equaliser.driver"

/// Device UID for the Equaliser virtual device (must match driver's kDevice_UID)
/// When kHas_Driver_Name_Format is false, the driver uses: kDriver_Name "_UID"
public let DRIVER_DEVICE_UID = "Equaliser_UID"

/// Model UID for the Equaliser virtual device
public let DRIVER_MODEL_UID = "Equaliser_ModelUID"

/// Default device name
public let DRIVER_DEFAULT_NAME = "Equaliser"

// MARK: - Installation Paths

/// System path where HAL plugins are installed
public let DRIVER_INSTALL_PATH = "/Library/Audio/Plug-Ins/HAL"

/// Full path to the installed driver bundle
public let DRIVER_BUNDLE_PATH = DRIVER_INSTALL_PATH + "/Equaliser.driver"

// MARK: - Custom Property Selectors
/// These must match the 4-char codes defined in EqualiserDriver.c

/// Custom property selector for device name - 'eqnm'
public let DRIVER_PROP_NAME: AudioObjectPropertySelector = 0x65716E6D

/// Custom property selector for shared memory path (file-based) - 'eqsp'
public let DRIVER_PROP_SHARED_MEM_PATH: AudioObjectPropertySelector = 0x65717370

// Device visibility is automatic: hidden until app connects, visible when app is running

// MARK: - Notifications

extension Notification.Name {
    static let driverDidInstall = Notification.Name("driverDidInstall")
    static let driverDidUninstall = Notification.Name("driverDidUninstall")
}

// MARK: - Property Addresses

/// Address for device name property
public let DRIVER_ADDRESS_NAME = AudioObjectPropertyAddress(
    mSelector: DRIVER_PROP_NAME,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)

/// Address for shared memory path property (file-based)
public let DRIVER_ADDRESS_SHARED_MEM_PATH = AudioObjectPropertyAddress(
    mSelector: DRIVER_PROP_SHARED_MEM_PATH,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)


