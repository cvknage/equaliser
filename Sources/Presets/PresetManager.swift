import Combine
import Foundation
import os.log

/// Error types for preset operations.
enum PresetError: LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)
    case deleteFailed(Error)
    case renameFailed(Error)
    case presetNotFound(String)
    case presetAlreadyExists(String)
    case invalidPresetName

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create presets directory: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode preset: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode preset: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write preset file: \(error.localizedDescription)"
        case .readFailed(let error):
            return "Failed to read preset file: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete preset: \(error.localizedDescription)"
        case .renameFailed(let error):
            return "Failed to rename preset: \(error.localizedDescription)"
        case .presetNotFound(let name):
            return "Preset '\(name)' not found"
        case .presetAlreadyExists(let name):
            return "Preset '\(name)' already exists"
        case .invalidPresetName:
            return "Invalid preset name"
        }
    }
}

/// Manages preset storage, loading, and saving.
@MainActor
final class PresetManager: ObservableObject {
    // MARK: - Published Properties

    /// All loaded presets, sorted by name.
    @Published private(set) var presets: [Preset] = [] {
        didSet {
            factoryPresets = presets.filter { $0.metadata.isFactoryPreset }
            customPresets = presets.filter { !$0.metadata.isFactoryPreset }
        }
    }

    /// Built-in presets bundled with the app.
    @Published private(set) var factoryPresets: [Preset] = []

    /// Presets created or imported by the user.
    @Published private(set) var customPresets: [Preset] = []

    /// The currently selected preset name (nil if no preset is selected or if modified).
    @Published var selectedPresetName: String?

    /// Whether the current EQ settings have been modified from the loaded preset.
    @Published var isModified: Bool = false

    // MARK: - Private Properties

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.example.EqualizerApp", category: "PresetManager")
    private let storage: UserDefaults

    private enum Keys {
        static let selectedPreset = "equalizer.selectedPreset"
    }

    /// The directory where presets are stored.
    private var presetsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Equalizer/Presets", isDirectory: true)
    }

    // MARK: - Initialization

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Restore selected preset name
        selectedPresetName = storage.string(forKey: Keys.selectedPreset)

        // Ensure directory exists and load presets
        ensureDirectoryExists()
        installFactoryPresetsIfNeeded()
        loadAllPresets()
    }

    // MARK: - Directory Management

    private func ensureDirectoryExists() {
        do {
            try fileManager.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
            logger.debug("Presets directory ready: \(self.presetsDirectory.path)")
        } catch {
            logger.error("Failed to create presets directory: \(error.localizedDescription)")
        }
    }

    /// Returns factory presets bundled with the app.
    var builtInPresets: [Preset] {
        factoryPresets
    }

    /// Returns presets created or imported by the user.
    var userPresets: [Preset] {
        customPresets
    }

    // MARK: - Loading Presets

    /// Loads all presets from the presets directory.
    func loadAllPresets() {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: presetsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles
            )

            let presetFiles = contents.filter { $0.pathExtension == Preset.fileExtension }
            var loadedPresets: [Preset] = []

            for fileURL in presetFiles {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let preset = try decoder.decode(Preset.self, from: data)
                    loadedPresets.append(preset)
                } catch {
                    logger.warning("Failed to load preset from \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            presets = loadedPresets.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
            factoryPresets = presets.filter { $0.metadata.isFactoryPreset }
            customPresets = presets.filter { !$0.metadata.isFactoryPreset }
            logger.info("Loaded \(self.presets.count) presets")
        } catch {
            logger.error("Failed to enumerate presets directory: \(error.localizedDescription)")
            presets = []
        }
    }

    /// Returns the URL for a preset file.
    private func fileURL(for presetName: String) -> URL {
        let safeName = presetName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return presetsDirectory.appendingPathComponent("\(safeName).\(Preset.fileExtension)")
    }

    // MARK: - CRUD Operations

    /// Saves a preset to disk.
    func savePreset(_ preset: Preset) throws {
        guard !preset.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PresetError.invalidPresetName
        }

        let fileURL = fileURL(for: preset.metadata.name)

        do {
            let data = try encoder.encode(preset)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved preset: \(preset.metadata.name)")
        } catch let error as EncodingError {
            throw PresetError.encodingFailed(error)
        } catch {
            throw PresetError.writeFailed(error)
        }

        // Reload to update the list
        loadAllPresets()
    }

    /// Deletes a preset by name.
    func deletePreset(named name: String) throws {
        let fileURL = fileURL(for: name)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw PresetError.presetNotFound(name)
        }

        do {
            try fileManager.removeItem(at: fileURL)
            logger.info("Deleted preset: \(name)")
        } catch {
            throw PresetError.deleteFailed(error)
        }

        // Clear selection if the deleted preset was selected
        if selectedPresetName == name {
            selectedPresetName = nil
            storage.removeObject(forKey: Keys.selectedPreset)
        }

        loadAllPresets()
    }

    /// Renames a preset.
    func renamePreset(from oldName: String, to newName: String) throws {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PresetError.invalidPresetName
        }

        let oldFileURL = fileURL(for: oldName)
        let newFileURL = fileURL(for: newName)

        guard fileManager.fileExists(atPath: oldFileURL.path) else {
            throw PresetError.presetNotFound(oldName)
        }

        guard !fileManager.fileExists(atPath: newFileURL.path) else {
            throw PresetError.presetAlreadyExists(newName)
        }

        // Load the preset, rename it, and save with new name
        do {
            let data = try Data(contentsOf: oldFileURL)
            var preset = try decoder.decode(Preset.self, from: data)
            preset = preset.renamed(to: newName)

            let newData = try encoder.encode(preset)
            try newData.write(to: newFileURL, options: .atomic)
            try fileManager.removeItem(at: oldFileURL)

            logger.info("Renamed preset: \(oldName) -> \(newName)")
        } catch {
            throw PresetError.renameFailed(error)
        }

        // Update selection if the renamed preset was selected
        if selectedPresetName == oldName {
            selectedPresetName = newName
            storage.set(newName, forKey: Keys.selectedPreset)
        }

        loadAllPresets()
    }

    /// Returns a preset by name.
    func preset(named name: String) -> Preset? {
        presets.first { $0.metadata.name == name }
    }

    /// Checks if a preset with the given name exists.
    func presetExists(named name: String) -> Bool {
        presets.contains { $0.metadata.name == name }
    }

    // MARK: - Preset Creation and Application

    /// Creates a new preset from the current EQ configuration.
    func createPreset(named name: String, from config: EQConfiguration, inputGain: Float, outputGain: Float) throws -> Preset {
        let preset = Preset(name: name, from: config, inputGain: inputGain, outputGain: outputGain)
        try savePreset(preset)
        return preset
    }

    /// Applies a preset to an EQ configuration.
    func applyPreset(_ preset: Preset, to config: EQConfiguration) {
        // Apply global settings
        config.globalBypass = preset.settings.globalBypass
        config.globalGain = preset.settings.globalGain

        // Apply band count
        config.setActiveBandCount(preset.settings.activeBandCount)

        // Apply band settings
        for (index, band) in preset.settings.bands.enumerated() {
            guard index < config.bands.count else { break }
            config.updateBandFrequency(index: index, frequency: band.frequency)
            config.updateBandBandwidth(index: index, bandwidth: band.bandwidth)
            config.updateBandGain(index: index, gain: band.gain)
            config.updateBandFilterType(index: index, filterType: band.filterType)
            config.updateBandBypass(index: index, bypass: band.bypass)
        }
    }

    /// Sets the selected preset and persists the selection.
    func selectPreset(named name: String?) {
        selectedPresetName = name
        isModified = false
        if let name = name {
            storage.set(name, forKey: Keys.selectedPreset)
        } else {
            storage.removeObject(forKey: Keys.selectedPreset)
        }
    }

    /// Marks the current preset as modified.
    func markAsModified() {
        if selectedPresetName != nil {
            isModified = true
        }
    }

    // MARK: - Import/Export

    /// Imports a preset from a file URL.
    func importPreset(from url: URL) throws -> Preset {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PresetError.readFailed(error)
        }

        let preset: Preset
        do {
            preset = try decoder.decode(Preset.self, from: data)
        } catch {
            throw PresetError.decodingFailed(error)
        }

        try savePreset(preset)
        return preset
    }

    /// Exports a preset to a file URL.
    func exportPreset(_ preset: Preset, to url: URL) throws {
        let data: Data
        do {
            data = try encoder.encode(preset)
        } catch {
            throw PresetError.encodingFailed(error)
        }

        do {
            try data.write(to: url, options: .atomic)
            logger.info("Exported preset to: \(url.path)")
        } catch {
            throw PresetError.writeFailed(error)
        }
    }
}
