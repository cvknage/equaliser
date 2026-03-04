import SwiftUI

/// The menu bar popover content - quick access controls.
struct MenuBarContentView: View {
    @EnvironmentObject var store: EqualizerStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                Text("Equalizer")
                    .font(.headline)
                Spacer()
            }

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

            // Controls
            Toggle("Bypass EQ", isOn: $store.isBypassed)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            // EQ Settings Button
            Button("Open EQ Settings...") {
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
        .padding(12)
        .frame(width: 240, height: 340)
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
            return "Idle"
        case .starting:
            return "Starting..."
        case .active:
            return "Active"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualizerStore())
}
