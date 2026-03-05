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
            HStack(spacing: 8) {
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

                // Bypass Button
                if store.isBypassed {
                    Button("Activate EQ") {
                        store.isBypassed.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Bypass EQ") {
                        store.isBypassed.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                // Routing Button
                if store.routingStatus.isActive {
                    Button("Stop Routing") {
                        store.stopRouting()
                    }
                    .buttonStyle(.bordered)
                } else if case .error = store.routingStatus {
                    Button("Retry") {
                        store.reconfigureRouting()
                    }
                    .buttonStyle(.bordered)
                } else if store.routingStatus == .idle
                    && store.selectedInputDeviceID != nil
                    && store.selectedOutputDeviceID != nil
                {
                    Button("Start Routing") {
                        store.reconfigureRouting()
                    }
                    .buttonStyle(.borderedProminent)
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
        .padding(16)
        .frame(width: 280, height: 340)
    }

    private var statusColor: Color {
        switch store.routingStatus {
        case .idle:
            return .gray
        case .starting:
            return .orange
        case .active:
            return .green
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
            return "Running"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualizerStore())
}
