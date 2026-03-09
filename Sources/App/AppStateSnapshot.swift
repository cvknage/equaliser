import AppKit
import AVFoundation
import Foundation
import os.log

struct AppStateSnapshot: Codable, Sendable {
    // MARK: - EQ Configuration
    
    var globalBypass: Bool
    var inputGain: Float
    var outputGain: Float
    var activeBandCount: Int
    var bands: [EQBandConfiguration]
    
    // MARK: - App State
    
    var inputDeviceID: String?
    var outputDeviceID: String?
    var bandwidthDisplayMode: String
    
    // MARK: - Meter State
    
    var metersEnabled: Bool
    
    // MARK: - Defaults
    
    static var `default`: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: false,
            inputGain: 0,
            outputGain: 0,
            activeBandCount: EQConfiguration.defaultBandCount,
            bands: EQConfiguration.defaultBands(),
            inputDeviceID: nil,
            outputDeviceID: nil,
            bandwidthDisplayMode: BandwidthDisplayMode.octaves.rawValue,
            metersEnabled: true
        )
    }
}

@MainActor
final class AppStatePersistence {
    private let storage: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private weak var store: EqualiserStore?
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "AppStatePersistence")
    
    private enum Keys {
        static let appState = "equalizer.appState"
    }
    
    init(storage: UserDefaults = .standard) {
        self.storage = storage
        encoder.outputFormatting = [.sortedKeys]
        
        // Subscribe to app quit notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    func setStore(_ store: EqualiserStore) {
        self.store = store
    }
    
    func load() -> AppStateSnapshot? {
        guard let data = storage.data(forKey: Keys.appState) else { return nil }
        do {
            return try decoder.decode(AppStateSnapshot.self, from: data)
        } catch {
            logger.error("Failed to decode app state: \(error.localizedDescription)")
            return nil
        }
    }
    
    func save(_ snapshot: AppStateSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            storage.set(data, forKey: Keys.appState)
            logger.debug("Saved app state successfully")
        } catch {
            logger.error("Failed to encode app state: \(error.localizedDescription)")
        }
    }
    
    @objc private func handleAppWillTerminate(_ notification: Notification) {
        guard let store = store else { return }
        save(store.currentSnapshot)
        logger.info("Saved app state on quit")
    }
}