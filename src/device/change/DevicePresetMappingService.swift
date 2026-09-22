// DevicePresetMappingService.swift
// Persists the device-to-preset mapping

import Foundation
import OSLog

/// Persists the device → preset mapping to UserDefaults.
/// Stored as JSON-encoded DevicePresetMap for forward-compatible schema changes.
@MainActor
final class DevicePresetMappingService {

    // MARK: - Private Properties

    private let storage: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "DevicePresetMappingService")

    private enum Keys {
        static let devicePresets = "equalizer.devicePresets"
    }

    // MARK: - Initialization

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Persistence

    /// Loads the current mapping from storage.
    /// Returns an empty map if nothing is stored or decoding fails.
    func load() -> DevicePresetMap {
        guard let data = storage.data(forKey: Keys.devicePresets) else { return DevicePresetMap() }
        do {
            return try decoder.decode(DevicePresetMap.self, from: data)
        } catch {
            logger.error("Failed to decode device preset map: \(error.localizedDescription)")
            return DevicePresetMap()
        }
    }

    /// Saves the mapping to storage.
    /// - Parameter map: The mapping to persist
    func save(_ map: DevicePresetMap) {
        do {
            let data = try encoder.encode(map)
            storage.set(data, forKey: Keys.devicePresets)
        } catch {
            logger.error("Failed to encode device preset map: \(error.localizedDescription)")
        }
    }
}