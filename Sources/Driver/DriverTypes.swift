// DriverTypes.swift
// Shared types for driver management

import Foundation

// MARK: - Driver Status

/// Driver installation status
public enum DriverStatus: Equatable {
    case notInstalled
    case installed(version: String)
    case needsUpdate(currentVersion: String, bundledVersion: String)
    case error(String)
}

// MARK: - Driver Error

/// Driver-related errors
public enum DriverError: LocalizedError {
    case driverNotFoundInBundle
    case installationFailed(String)
    case uninstallationFailed(String)
    case deviceNotFound
    case propertySetFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .driverNotFoundInBundle:
            return "Driver not found in application bundle"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallationFailed(let message):
            return "Uninstallation failed: \(message)"
        case .deviceNotFound:
            return "Driver device not found in CoreAudio"
        case .propertySetFailed(let message):
            return "Failed to set driver property: \(message)"
        }
    }
}