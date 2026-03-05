import SwiftUI

/// The menu bar popover content - quick access controls.
struct MenuBarContentView: View {
    @EnvironmentObject var store: EqualizerStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "slider.vertical.3")
                    .font(.title3)
                Text("Equalizer")
                    .font(.headline)
                Spacer()
            }

            Divider()
                .padding(.vertical, 4)

                // Control strip - status indicator + controls grouped together
            HStack(alignment: .top, spacing: 12) {
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Toggle controls (stacked vertically)
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("EQ", isOn: Binding(
                        get: { !store.isBypassed },
                        set: { store.isBypassed = !$0 }
                    ))
                    .controlSize(.small)
                    .toggleStyle(.switch)

                    Toggle("Routing", isOn: Binding(
                        get: { store.routingStatus.isActive },
                        set: { newValue in
                            if newValue {
                                store.reconfigureRouting()
                            } else {
                                store.stopRouting()
                            }
                        }
                    ))
                    .controlSize(.small)
                    .toggleStyle(.switch)
                    .disabled(store.routingStatus == .idle
                              && (store.selectedInputDeviceID == nil
                                  || store.selectedOutputDeviceID == nil))
                    .errorTint({
                        if case .error = store.routingStatus { return true }
                        return false
                    }())
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Device Pickers
            DevicePickerView(layout: .vertical)

            Divider()
                .padding(.vertical, 4)

            // Preset Picker
            CompactPresetPicker()

            Divider()
                .padding(.vertical, 4)

            // Open Equaliser Button
            Button("Open Equaliser App") {
                openWindow(id: "eq-settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            // Footer
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(width: 280, height: 370)
    }

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
            return store.isBypassed ? "Bypassed" : "Running"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualizerStore())
}
