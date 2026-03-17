// DriverLifecycleManaging.swift
// Protocol for driver lifecycle management

import Foundation

/// Protocol for driver installation and lifecycle management.
@MainActor
protocol DriverLifecycleManaging: ObservableObject {
    /// Current driver installation status
    var status: DriverStatus { get }
    
    /// Whether installation is in progress
    var isInstalling: Bool { get set }
    
    /// Last installation error, if any (settable for UI)
    var installError: String? { get set }
    
    /// Whether the driver is installed and ready
    var isReady: Bool { get }
    
    /// Installs the driver with admin privileges
    func installDriver() async throws
    
    /// Uninstalls the driver with admin privileges
    func uninstallDriver() async throws
    
    /// Checks and updates the installation status
    func checkInstallationStatus()
}