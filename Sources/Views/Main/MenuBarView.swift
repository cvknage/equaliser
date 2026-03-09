import SwiftUI

/// The menu bar popover content - quick access controls.
/// Designed with compact controls: each control (label + picker) in its own row.
struct MenuBarContentView: View {
    @EnvironmentObject var store: EqualiserStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider()
                .padding(.vertical, 12)
            
            controlGroupSection
            
            Divider()
                .padding(.vertical, 12)
            
            actionButtonsSection
        }
        .padding(16)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.vertical.3")
                .font(.title3)
            Text("Equaliser")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Control Groups (Option 27 style: each control in own row)

    private var controlGroupSection: some View {
        VStack(spacing: 12) {
            statusRow

            outputPickerRow

            presetPickerRow
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline)
            }
            Spacer()
            SystemEQToggleView(style: SystemEQToggleView.Style.menuBar)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Output Picker Row

    private var outputPickerRow: some View {
        HStack {
            Text("Output")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Section {
                    Text("Select Output")
                }
                Section {
                    ForEach(store.outputDevices) { device in
                        Button {
                            store.selectedOutputDeviceID = device.uid
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if store.selectedOutputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(displayOutputText)
            }
        }
    }

    private var displayOutputText: String {
        if let uid = store.selectedOutputDeviceID,
           let device = store.outputDevices.first(where: { $0.uid == uid }) {
            return device.displayName
        }
        return "Select Output"
    }

    // MARK: - Preset Picker Row

    private var presetPickerRow: some View {
        HStack {
            Text("Preset")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            CompactPresetPicker()
        }
    }

    // MARK: - Action Buttons (each in own section like mockup)

    private var actionButtonsSection: some View {
        VStack(spacing: 0) {
            // Open Equaliser button - full width
            Button {
                openWindow(id: "equaliser")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Open Equaliser")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            // Quit button - aligned right
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch store.routingStatus {
        case .idle:
            return .gray
        case .starting:
            return .orange
        case .active:
            return store.isBypassed ? .yellow : .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch store.routingStatus {
        case .idle:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .active:
            return store.isBypassed ? "Bypassed" : "Active"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualiserStore())
}
