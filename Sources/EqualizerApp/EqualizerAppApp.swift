import AVFoundation
import SwiftUI

@main
struct EqualizerAppMain: App {
    @StateObject private var store = EqualizerStore()

    init() {
        // Hide dock icon permanently - this is a menu bar app
        // Defer until NSApp is available (it's nil during init)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }

        // Request microphone access for audio routing
        AVAudioApplication.requestRecordPermission { granted in
            if !granted {
                print("Microphone access denied. Audio routing will be unavailable.")
            }
        }
    }

    var body: some Scene {
        // Main EQ settings window (hidden by default, opened on demand)
        Window("Equalizer Settings", id: "eq-settings") {
            EQWindowView()
                .environmentObject(store)
        }
        .defaultPosition(.center)
        .defaultSize(width: 1060, height: 630)
        .windowResizability(.contentMinSize)

        // Menu bar popover (always available)
        MenuBarExtra("Equalizer", systemImage: "slider.horizontal.3") {
            MenuBarContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

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

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        VStack(spacing: 12) {
            // Header: App title only
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Equalizer")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Parametric EQ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Level meters + unified control panel
            HStack(alignment: .top, spacing: 16) {
                LevelMetersView(
                    inputState: store.inputMeterLevel,
                    outputState: store.outputMeterLevel,
                    inputRMSState: store.inputMeterRMS,
                    outputRMSState: store.outputMeterRMS,
                    inputGain: $store.inputGain,
                    outputGain: $store.outputGain,
                    isActive: store.routingStatus.isActive
                )
                .frame(width: 620)
                .layoutPriority(1)

                Spacer()

                // Unified control panel - device pickers, status, and buttons grouped together
                VStack(alignment: .trailing, spacing: 8) {
                    // Device pickers
                    DevicePickerView(layout: .horizontal)

                    RoutingStatusView(status: store.routingStatus)
                        .frame(width: 376)

                    // Routing action buttons
                    HStack(spacing: 8) {
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
                                    && store.selectedOutputDeviceID != nil {
                            Button("Start Routing") {
                                store.reconfigureRouting()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .frame(minWidth: 376)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Preset and band controls toolbar
            HStack {
                PresetToolbar()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Bands")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                BandCountControl()

                Button("Flatten") {
                    for i in 0..<store.bandCount {
                        store.updateBandGain(index: i, gain: 0)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // EQ sliders
            EQBandGridView()
        }
        .frame(minWidth: 1060, minHeight: 570)
    }
}

#Preview("Menu Bar") {
    MenuBarContentView()
        .environmentObject(EqualizerStore())
}

#Preview("EQ Window") {
    EQWindowView()
        .environmentObject(EqualizerStore())
}
