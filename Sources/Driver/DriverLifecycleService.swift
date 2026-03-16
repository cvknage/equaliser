// DriverLifecycleService.swift
// Driver installation and lifecycle management

import Foundation
import CoreAudio
import OSLog

/// Manages driver installation, uninstallation, and status.
@MainActor
public final class DriverLifecycleService: ObservableObject, DriverLifecycleManaging {
    
    // MARK: - Published Properties
    
    @Published public private(set) var status: DriverStatus = .notInstalled
    @Published public var isInstalling: Bool = false
    @Published public var installError: String?
    
    // MARK: - Private Properties
    
    private var installedVersion: String?
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DriverLifecycleService")
    
    // MARK: - Computed Properties
    
    public var isReady: Bool {
        if case .installed(_) = status {
            return true
        }
        
        // Fallback: check if driver actually exists on disk
        // This handles race conditions during app initialization
        let exists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        return exists
    }
    
    // MARK: - Initialization
    
    public init() {
        checkInstallationStatus()
    }
    
    // MARK: - Installation
    
    public func installDriver() async throws {
        guard !isInstalling else { return }
        
        isInstalling = true
        installError = nil
        
        do {
            guard let bundledURL = Bundle.main.url(forResource: "Equaliser", withExtension: "driver") else {
                throw DriverError.driverNotFoundInBundle
            }
            
            logger.info("Installing driver from \(bundledURL.path)")
            
            let script = "if [ -d '\(DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(DRIVER_BUNDLE_PATH)'; fi; mkdir -p '\(DRIVER_INSTALL_PATH)'; cp -R '\(bundledURL.path)' '\(DRIVER_BUNDLE_PATH)'; chown -R root:wheel '\(DRIVER_BUNDLE_PATH)'; chmod -R 755 '\(DRIVER_BUNDLE_PATH)'; killall coreaudiod"
            
            try await executeWithAdminPrivileges(script: script)
            
            try await Task.sleep(for: .seconds(2))
            
            checkInstallationStatus()
            
            if case .notInstalled = status {
                throw DriverError.installationFailed("Driver not found after installation")
            }
            
            logger.info("Driver installed successfully")
            
            // Notify that driver was installed so DeviceManager can refresh
            NotificationCenter.default.post(name: .driverDidInstall, object: nil)
            
        } catch {
            isInstalling = false
            throw error
        }
        
        isInstalling = false
    }
    
    public func uninstallDriver() async throws {
        guard !isInstalling else { return }
        
        isInstalling = true
        
        do {
            let script = "if [ -d '\(DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(DRIVER_BUNDLE_PATH)'; killall coreaudiod; fi"
            
            try await executeWithAdminPrivileges(script: script)
            
            try await Task.sleep(for: .seconds(1))
            
            checkInstallationStatus()
            
            logger.info("Driver uninstalled successfully")
            
            // Notify that driver was uninstalled so DeviceManager can refresh
            NotificationCenter.default.post(name: .driverDidUninstall, object: nil)
            
        } catch {
            isInstalling = false
            throw error
        }
        
        isInstalling = false
    }
    
    // MARK: - Status Checking
    
    public func checkInstallationStatus() {
        logger.debug("Checking installation status...")
        logger.debug("Driver bundle path: \(DRIVER_BUNDLE_PATH)")
        
        let fileExists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        logger.debug("Driver bundle exists: \(fileExists)")
        
        guard fileExists else {
            logger.warning("Driver not found at \(DRIVER_BUNDLE_PATH)")
            status = .notInstalled
            return
        }
        
        installedVersion = getInstalledDriverVersion()
        let versionStr = installedVersion ?? "unknown"
        logger.debug("Installed version: \(versionStr)")
        
        if let version = installedVersion {
            let bundledVersion = getBundledDriverVersion()
            logger.debug("Bundled version: \(bundledVersion)")
            if version < bundledVersion {
                status = .needsUpdate(currentVersion: version, bundledVersion: bundledVersion)
            } else {
                status = .installed(version: version)
            }
        } else {
            status = .installed(version: "unknown")
        }
        
        let statusStr = String(describing: status)
        logger.info("Installation status: \(statusStr)")
    }
    
    // MARK: - Private Helpers
    
    private func getBundledDriverVersion() -> String {
        // Read from bundled driver in app's Resources folder
        guard let resourcePath = Bundle.main.resourcePath else { return "1.0" }
        let driverInfoPath = resourcePath + "/Equaliser.driver/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: driverInfoPath),
              let version = info["CFBundleShortVersionString"] as? String else {
            return "1.0"
        }
        return version
    }
    
    private func getInstalledDriverVersion() -> String? {
        let infoPath = DRIVER_BUNDLE_PATH + "/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }
    
    private func executeWithAdminPrivileges(script: String) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw DriverError.installationFailed("Script failed (status \(task.terminationStatus)): \(errorMessage)")
        }
    }
}