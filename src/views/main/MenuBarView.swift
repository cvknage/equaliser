import SwiftUI

/// The menu bar popover content - quick access controls.
/// Designed with compact controls: each control (label + picker) in its own row.
struct MenuBarContentView: View {
    @EnvironmentObject var store: EqualiserStore
    @Environment(\.openWindow) private var openWindow
    
    /// View model for routing status and device selection.
    private var routingViewModel: RoutingViewModel {
        RoutingViewModel(store: store)
    }

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

            // Only show output picker in manual mode
            if routingViewModel.manualModeEnabled {
                outputPickerRow
            }

            presetPickerRow
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(routingViewModel.statusColor)
                    .frame(width: 8, height: 8)
                Text(routingViewModel.simplifiedStatusText)
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
                    ForEach(routingViewModel.outputDevices) { device in
                        Button {
                            routingViewModel.selectOutputDevice(device.uid)
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if routingViewModel.selectedOutputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(routingViewModel.outputDeviceName)
            }
        }
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
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualiserStore())
}
