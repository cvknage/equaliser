import AppKit
import SwiftUI

// MARK: - Menu Section Helper

struct MenuSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preset Picker

/// A picker for selecting presets, with modified indicator.
struct PresetPicker: View {
    @EnvironmentObject var store: EqualiserStore

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                PresetMenuContentView()
            } label: {
                PresetMenuLabelView(dotSize: 6)
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Compact Preset Picker (for Menu Bar)

/// A compact preset picker suitable for the menu bar popover.
struct CompactPresetPicker: View {
    var body: some View {
        Menu {
            PresetMenuContentView()
        } label: {
            PresetMenuLabelView(dotSize: 5, spacing: 2)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Preset Menu Helpers

struct PresetMenuLabelView: View {
    @EnvironmentObject var store: EqualiserStore
    let dotSize: CGFloat
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            Text(currentPresetLabel)
                .lineLimit(1)
            if store.presetManager.isModified {
                Circle()
                    .fill(Color.orange)
                    .frame(width: dotSize, height: dotSize)
            }
        }
    }

    private var currentPresetLabel: String {
        store.presetManager.selectedPresetName ?? "Custom"
    }
}

struct PresetMenuContentView: View {
    @EnvironmentObject var store: EqualiserStore

    var body: some View {
        if store.presetManager.presets.isEmpty {
            Text("No presets")
                .foregroundStyle(.secondary)
        } else {
            if !store.presetManager.builtInPresets.isEmpty {
                presetSection(title: "Built-in Presets", presets: store.presetManager.builtInPresets)
            }

            if !store.presetManager.userPresets.isEmpty {
                presetSection(title: "Custom Presets", presets: store.presetManager.userPresets)
            }
        }

        Divider()
    }

    @ViewBuilder
    private func presetSection(title: String, presets: [Preset]) -> some View {
        Section(title) {
            ForEach(presets) { preset in
                presetRow(for: preset)
            }
        }
    }

    @ViewBuilder
    private func presetRow(for preset: Preset) -> some View {
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

// MARK: - Save Preset Sheet

/// A sheet for saving a new preset or renaming an existing one.
struct SavePresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: EqualiserStore

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
                .font(.caption)

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
    @EnvironmentObject var store: EqualiserStore
    @State private var showingSaveSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingImportWarning = false
    @State private var showingEasyEffectsImportWarning = false
    @State private var importWarnings: [String] = []
    @State private var presetToRename: PresetRenameItem?

    struct PresetRenameItem: Identifiable {
        let id = UUID()
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preset")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                PresetPicker()

                // New preset button
                Button {
                    store.createNewPreset()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 16)
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
                            if let name = store.presetManager.selectedPresetName {
                                presetToRename = PresetRenameItem(name: name)
                            }
                        }

                        Button("Delete", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }

                    Divider()

                    Button("Import EasyEffects Preset...") {
                        showingEasyEffectsImportWarning = true
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
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SavePresetSheet()
        }
        .sheet(item: $presetToRename) { item in
            SavePresetSheet(existingName: item.name)
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
        .sheet(isPresented: $showingEasyEffectsImportWarning) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Limited Functionality")
                    .font(.headline)
                
                Text("""
                Importing from EasyEffects has limitations:
                
                • Only the equalizer bands are imported
                • Filter mode (RLC BT/MT, etc.) and slope (x1, x2, x4) are not supported
                • Per-channel (split) EQ is not supported - mono EQ is used
                • Non-EQ plugins (compressor, limiter, reverb) are not imported
                • Input/output gain and some band settings may differ slightly
                
                The imported preset will only contain the equalizer bands.
                """)
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingEasyEffectsImportWarning = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Continue") {
                        showingEasyEffectsImportWarning = false
                        importEasyEffectsPreset()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 500)
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

