// AudioDevice.swift
// Audio device model for CoreAudio device representation

import CoreAudio
import Foundation

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
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

    /// Returns true if this device is the Equaliser driver.
    var isDriver: Bool {
        uid.hasPrefix("Equaliser")
    }

    /// Returns true if this device is valid for selection.
    /// Only excludes the driver - trust user's choices for everything else.
    var isValidForSelection: Bool {
        !isDriver
    }

    /// Returns true if this is a real physical device (not driver, virtual, or aggregate).
    /// Used for fallback selection when no user preference exists.
    var isRealDevice: Bool {
        !isDriver && !isVirtual && !isAggregate
    }

    /// Returns true if this device has built-in transport type.
    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }
}