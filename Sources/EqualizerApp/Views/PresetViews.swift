import AppKit
import SwiftUI

// MARK: - Preset Picker

/// A picker for selecting presets, with modified indicator.
struct PresetPicker: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                if store.presetManager.presets.isEmpty {
                    Text("No presets")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.presetManager.presets) { preset in
                        Button {
                            store.loadPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.metadata.name)
                                if preset.metadata.name == store.presetManager.selectedPresetName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Reset to Flat") {
                    store.resetToDefaults()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPresetLabel)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)
                    if store.presetManager.isModified {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(minWidth: 100)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var currentPresetLabel: String {
        if let name = store.presetManager.selectedPresetName {
            return name
        }
        return "Custom"
    }
}

// MARK: - Save Preset Sheet

/// A sheet for saving a new preset or renaming an existing one.
struct SavePresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: EqualizerStore

    @State private var presetName: String = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    let isRenaming: Bool
    let existingName: String?

    init(existingName: String? = nil) {
        self.existingName = existingName
        self.isRenaming = existingName != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isRenaming ? "Rename Preset" : "Save Preset")
                .font(.headline)

            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit(save)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(isRenaming ? "Rename" : "Save") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            if let existing = existingName {
                presetName = existing
            } else if let selected = store.presetManager.selectedPresetName {
                presetName = selected
            }
            isNameFieldFocused = true
        }
    }

    private func save() {
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a preset name"
            return
        }

        do {
            if isRenaming, let oldName = existingName {
                // Renaming existing preset
                try store.presetManager.renamePreset(from: oldName, to: trimmedName)
            } else {
                // Check if overwriting
                if store.presetManager.presetExists(named: trimmedName) {
                    // Overwrite existing
                    try store.saveCurrentAsPreset(named: trimmedName)
                } else {
                    // Create new
                    try store.saveCurrentAsPreset(named: trimmedName)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preset Toolbar

/// A toolbar with preset controls for the main EQ window.
struct PresetToolbar: View {
    @EnvironmentObject var store: EqualizerStore
    @State private var showingSaveSheet = false
    @State private var showingRenameSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingImportWarning = false
    @State private var importWarnings: [String] = []
    @State private var presetToRename: String?

    var body: some View {
        HStack(spacing: 8) {
            Text("Preset")
                .font(.headline)
                .foregroundStyle(.secondary)

            PresetPicker()

            // New preset button
            Button {
                store.createNewPreset()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("New preset")

            // More options menu
            Menu {
                Button("Save") {
                    if store.presetManager.selectedPresetName != nil && store.presetManager.isModified {
                        do {
                            try store.updateCurrentPreset()
                        } catch {
                            showingSaveSheet = true
                        }
                    } else {
                        showingSaveSheet = true
                    }
                }

                Button("Save As...") {
                    showingSaveSheet = true
                }

                if store.presetManager.selectedPresetName != nil {
                    Button("Rename...") {
                        presetToRename = store.presetManager.selectedPresetName
                        showingRenameSheet = true
                    }

                    Button("Delete", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }

                Divider()

                Button("Import EasyEffects Preset...") {
                    importEasyEffectsPreset()
                }

                if store.presetManager.selectedPresetName != nil,
                   let preset = store.presetManager.preset(named: store.presetManager.selectedPresetName!) {
                    Button("Export to EasyEffects...") {
                        exportEasyEffectsPreset(preset)
                    }
                }

                Divider()

                Button("Import Preset...") {
                    importNativePreset()
                }

                if store.presetManager.selectedPresetName != nil,
                   let preset = store.presetManager.preset(named: store.presetManager.selectedPresetName!) {
                    Button("Export Preset...") {
                        exportNativePreset(preset)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .sheet(isPresented: $showingSaveSheet) {
            SavePresetSheet()
        }
        .sheet(isPresented: $showingRenameSheet) {
            if let name = presetToRename {
                SavePresetSheet(existingName: name)
            }
        }
        .alert("Delete Preset?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let name = store.presetManager.selectedPresetName {
                    try? store.presetManager.deletePreset(named: name)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(store.presetManager.selectedPresetName ?? "")'? This cannot be undone.")
        }
        .alert("Import Warnings", isPresented: $showingImportWarning) {
            Button("OK") {}
        } message: {
            Text(importWarnings.joined(separator: "\n"))
        }
    }

    // MARK: - Import/Export

    private func importNativePreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: Preset.fileExtension)!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a preset file to import"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let preset = try store.presetManager.importPreset(from: url)
                store.loadPreset(preset)
            } catch {
                // Show error alert
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func exportNativePreset(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: Preset.fileExtension)!]
        panel.nameFieldStringValue = preset.filename
        panel.message = "Export preset"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.presetManager.exportPreset(preset, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func importEasyEffectsPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an EasyEffects preset file"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let result = try EasyEffectsImporter.importPreset(from: url)
                try store.presetManager.savePreset(result.preset)
                store.loadPreset(result.preset)

                if !result.warnings.isEmpty {
                    importWarnings = result.warnings
                    showingImportWarning = true
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func exportEasyEffectsPreset(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = EasyEffectsExporter.filename(for: preset)
        panel.message = "Export to EasyEffects format"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try EasyEffectsExporter.export(preset, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

// MARK: - Compact Preset Picker (for Menu Bar)

/// A compact preset picker suitable for the menu bar popover.
struct CompactPresetPicker: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        HStack {
            Text("Preset")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                if store.presetManager.presets.isEmpty {
                    Text("No presets")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.presetManager.presets) { preset in
                        Button {
                            store.loadPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.metadata.name)
                                if preset.metadata.name == store.presetManager.selectedPresetName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Reset to Flat") {
                    store.resetToDefaults()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPresetLabel)
                        .lineLimit(1)
                    if store.presetManager.isModified {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var currentPresetLabel: String {
        if let name = store.presetManager.selectedPresetName {
            return name
        }
        return "Custom"
    }
}

// MARK: - Bandwidth Display Mode Picker

/// A picker for selecting between octaves and Q factor display.
struct BandwidthDisplayModePicker: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        HStack {
            Text("Display")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $store.bandwidthDisplayMode) {
                ForEach(BandwidthDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}
