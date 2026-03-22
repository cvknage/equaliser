// DriverManager.swift
// Facade for driver-related services - maintains backward compatibility

import Foundation
import CoreAudio
import OSLog

private let log = Logger(subsystem: "net.knage.equaliser", category: "DriverManager")

// MARK: - Driver Manager Facade

/// Facade for driver-related services.
/// Maintains backward compatibility while delegating to specialised services.
@MainActor
public final class DriverManager: ObservableObject, DriverAccessing {
    
    // MARK: - Singleton
    
    public static let shared = DriverManager()
    
    // MARK: - Services (internal for testing)
    
    let lifecycleService: DriverLifecycleService
    let propertyService: DriverPropertyService
    let deviceRegistry: DriverDeviceRegistry
    
    // MARK: - Published Properties (forwarded from services)
    
    public var status: DriverStatus { lifecycleService.status }
    public var isInstalling: Bool {
        get { lifecycleService.isInstalling }
        set { lifecycleService.isInstalling = newValue }
    }
    public var installError: String? {
        get { lifecycleService.installError }
        set { lifecycleService.installError = newValue }
    }
    public var deviceID: AudioObjectID? { deviceRegistry.deviceID }
    
    public var isReady: Bool {
        // Check cached status first
        if case .installed(_) = lifecycleService.status {
            return true
        }
        
        // Fallback: check if driver actually exists on disk
        // This handles race conditions during app initialization
        let exists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        
        if exists && deviceID == nil {
            // Driver exists but we haven't found the device yet - refresh status
            lifecycleService.checkInstallationStatus()
            // Re-check status after refresh
            if case .installed(_) = lifecycleService.status {
                return true
            }
        }
        
        return exists
    }
    
    public var driverSampleRate: Float64? { propertyService.driverSampleRate }
    
    // MARK: - Initialization
    
    private init() {
        let registry = DriverDeviceRegistry()
        self.deviceRegistry = registry
        self.lifecycleService = DriverLifecycleService()
        self.propertyService = DriverPropertyService(registry: registry)
    }
    
    // MARK: - Lifecycle (pass-through)
    
    public func installDriver() async throws {
        try await lifecycleService.installDriver()
    }
    
    public func uninstallDriver() async throws {
        try await lifecycleService.uninstallDriver()
    }
    
    public func checkInstallationStatus() {
        lifecycleService.checkInstallationStatus()
    }
    
    // MARK: - Device Discovery (pass-through)
    
    public func isDriverVisible() -> Bool {
        deviceRegistry.isDriverVisible()
    }
    
    public func findDriverDeviceWithRetry(
        initialDelayMs: Int = 100,
        maxAttempts: Int = 6
    ) async -> AudioDeviceID? {
        await deviceRegistry.findDriverDeviceWithRetry(
            initialDelayMs: initialDelayMs,
            maxAttempts: maxAttempts
        )
    }
    
    // MARK: - Device Properties (pass-through)
    
    @discardableResult
    public func setDeviceName(_ name: String) -> Bool {
        propertyService.setDeviceName(name)
    }
    
    public func getDeviceName() -> String? {
        propertyService.getDeviceName()
    }
    
    @discardableResult
    public func setDriverSampleRate(matching targetRate: Float64) -> Float64? {
        propertyService.setDriverSampleRate(matching: targetRate)
    }
    
    // MARK: - System Default Device (pass-through)
    
    @discardableResult
    public func setAsDefaultOutputDevice() -> Bool {
        deviceRegistry.setAsDefaultOutputDevice()
    }
    
    @discardableResult
    public func restoreToBuiltInSpeakers() -> Bool {
        deviceRegistry.restoreToBuiltInSpeakers()
    }
}