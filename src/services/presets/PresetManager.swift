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
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "PresetManager")
    private let storage: UserDefaults

    private enum Keys {
        static let selectedPreset = "equalizer.selectedPreset"
    }

    /// The directory where presets are stored.
    private var presetsDirectory: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback to Documents directory if Application Support is unavailable
            logger.warning("Application Support directory not found, falling back to Documents")
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Equaliser/Presets", isDirectory: true)
        }
        return appSupport.appendingPathComponent("Equaliser/Presets", isDirectory: true)
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

        // Select Flat preset by default if none selected
        if selectedPresetName == nil && presetExists(named: "Flat") {
            selectPreset(named: "Flat")
            logger.debug("Auto-selected Flat preset as default")
        }
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
    /// If saving over a factory preset, marks it as user-owned (isFactoryPreset=false).
    func savePreset(_ preset: Preset) throws {
        var presetToSave = preset

        // If overwriting a factory preset, mark as user-owned
        if let existing = self.preset(named: preset.metadata.name), existing.metadata.isFactoryPreset {
            presetToSave.metadata.isFactoryPreset = false
        }

        try savePresetWithoutReload(presetToSave)
        loadAllPresets()
    }
    
    /// Saves a preset without reloading the list (for batch operations).
    internal func savePresetWithoutReload(_ preset: Preset) throws {
        guard !preset.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PresetError.invalidPresetName
        }

        let fileURL = fileURL(for: preset.metadata.name)

        do {
            let data = try encoder.encode(preset)
            try data.write(to: fileURL, options: .atomic)
            logger.debug("Saved preset: \(preset.metadata.name)")
        } catch let error as EncodingError {
            throw PresetError.encodingFailed(error)
        } catch {
            throw PresetError.writeFailed(error)
        }
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

    /// Loads a preset by name with graceful fallback.
    /// If the named preset isn't found, returns the "Flat" preset or creates a default.
    /// - Parameter name: The preset name.
    /// - Returns: The preset (never nil).
    func loadPresetWithFallback(named name: String) -> Preset {
        // Try to find the named preset
        if let preset = preset(named: name) {
            logger.debug("Loaded preset: \(name)")
            return preset
        }
        
        // Log warning
        logger.warning("Preset '\(name)' not found, searching for fallback")
        
        // Fallback 1: Try "Flat" preset
        if let flatPreset = preset(named: "Flat") {
            logger.warning("Using 'Flat' preset as fallback")
            return flatPreset
        }
        
        // Fallback 2: Create a default flat preset
        logger.warning("No presets available, creating default flat preset")
        return createDefaultFlatPreset()
    }

    /// Creates a default flat preset with all bands at 0dB.
    @MainActor
    private func createDefaultFlatPreset() -> Preset {
        let config = EQConfiguration(initialBandCount: EQConfiguration.defaultBandCount)
        return Preset(name: "Default", from: config, inputGain: 0.0, outputGain: 0.0)
    }

    // MARK: - Preset Creation and Application

    /// Creates a new preset from the current EQ configuration.
    /// Note: New presets always have isFactoryPreset=false (user-owned).
    @MainActor
    func createPreset(named name: String, from config: EQConfiguration, inputGain: Float, outputGain: Float) throws -> Preset {
        var preset = Preset(name: name, from: config, inputGain: inputGain, outputGain: outputGain)
        preset.metadata.isFactoryPreset = false  // Explicit: user presets are never factory
        try savePreset(preset)
        return preset
    }

    /// Applies a preset to an EQ configuration.
    func applyPreset(_ preset: Preset, to config: EQConfiguration) {
        // Apply channel mode
        if let channelMode = ChannelMode(rawValue: preset.settings.channelMode) {
            config.setChannelMode(channelMode)
        }

        // Derive band counts from band arrays
        let leftBandCount = preset.settings.leftBands.count
        let rightBandCount = preset.settings.rightBands.count

        // Set band count based on channel mode
        switch config.channelMode {
        case .linked:
            config.setActiveBandCount(leftBandCount)
        case .stereo:
            config.setActiveBandCount(leftBandCount, channel: .left)
            config.setActiveBandCount(rightBandCount, channel: .right)
        }

        // Apply left channel band settings
        for (index, band) in preset.settings.leftBands.enumerated() {
            guard index < config.bands.count else { break }
            config.updateBandFrequency(index: index, frequency: band.frequency)
            config.updateBandQ(index: index, q: band.q)
            config.updateBandGain(index: index, gain: band.gain)
            config.updateBandFilterType(index: index, filterType: band.filterType)
            config.updateBandBypass(index: index, bypass: band.bypass)
        }

        // Apply right channel band settings
        for (index, band) in preset.settings.rightBands.enumerated() {
            guard index < config.rightState.userEQ.bands.count else { break }
            config.updateBandFrequency(index: index, frequency: band.frequency, channel: .right)
            config.updateBandQ(index: index, q: band.q, channel: .right)
            config.updateBandGain(index: index, gain: band.gain, channel: .right)
            config.updateBandFilterType(index: index, filterType: band.filterType, channel: .right)
            config.updateBandBypass(index: index, bypass: band.bypass, channel: .right)
        }
    }

    /// Sets the selected preset and persists the selection.
    func selectPreset(named name: String?) {
        selectedPresetName = name
        isModified = false
        objectWillChange.send()
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
            objectWillChange.send()
        }
    }

    /// Compares current settings to the selected preset to determine if modified.
    /// Returns true if no preset is selected (nothing to be modified from).
    func settingsMatchSelectedPreset(
        activeBandCount: Int,
        bands: [EQBandConfiguration],
        inputGain: Float,
        outputGain: Float
    ) -> Bool {
        guard let presetName = selectedPresetName,
              let preset = preset(named: presetName) else {
            return true
        }

        let settings = preset.settings

        guard settings.activeBandCount == activeBandCount,
              settings.inputGain == inputGain,
              settings.outputGain == outputGain else {
            return false
        }

        for i in 0..<activeBandCount {
            let currentBand = bands[i]
            let presetBand = settings.leftBands[i]

            guard currentBand.frequency == presetBand.frequency,
                  currentBand.gain == presetBand.gain,
                  currentBand.q == presetBand.q,
                  currentBand.filterType == presetBand.filterType,
                  currentBand.bypass == presetBand.bypass else {
                return false
            }
        }

        return true
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
