// PresetViewModel.swift
// Presentation logic for preset management

import SwiftUI

/// View model for preset management UI.
/// Derives presentation state from EqualiserStore without containing business logic.
@MainActor
@Observable
final class PresetViewModel {
    private unowned let store: EqualiserStore
    
    init(store: EqualiserStore) {
        self.store = store
    }
    
    // MARK: - Preset List
    
    /// Sorted list of preset names for display.
    var presetNames: [String] {
        store.presetManager.presets
            .map { $0.metadata.name }
            .sorted()
    }
    
    /// All presets sorted alphabetically by name.
    var presets: [Preset] {
        store.presetManager.presets.sorted { $0.metadata.name < $1.metadata.name }
    }
    
    /// Whether any presets exist.
    var hasPresets: Bool {
        !store.presetManager.presets.isEmpty
    }
    
    // MARK: - Current Preset
    
    /// Name of currently selected preset, or "Custom" if none.
    var currentPresetName: String {
        store.presetManager.selectedPresetName ?? "Custom"
    }
    
    /// Whether current settings differ from saved preset.
    var isModified: Bool {
        store.presetManager.isModified
    }
    
    /// Whether the current preset can be updated (must have a selected preset).
    var canUpdateCurrent: Bool {
        store.presetManager.selectedPresetName != nil
    }
    
    /// Currently selected preset name, if any.
    var selectedPresetName: String? {
        store.presetManager.selectedPresetName
    }
    
    // MARK: - Bandwidth Display Mode
    
    /// User preference for displaying bandwidth (octaves or Q factor).
    var bandwidthDisplayMode: BandwidthDisplayMode {
        get { store.bandwidthDisplayMode }
        set { store.bandwidthDisplayMode = newValue }
    }
    
    // MARK: - Actions
    
    /// Loads a preset by name.
    func selectPreset(named name: String) {
        store.loadPreset(named: name)
    }
    
    /// Creates a new blank preset.
    func createNew() {
        store.createNewPreset()
    }
    
    /// Saves current settings as a new preset.
    func saveAsNew(name: String) throws {
        try store.saveCurrentAsPreset(named: name)
    }
    
    /// Updates the currently selected preset with current settings.
    func updateCurrent() throws {
        try store.updateCurrentPreset()
    }
}