import SwiftUI
import Combine

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject var store: EqualiserStore
    @StateObject private var driverManager = DriverManager.shared
    @State private var showCompareHelp = false
    @State private var metersEnabledUI = false
    @State private var showDriverSheet = true

    /// Whether the driver installation overlay should be shown.
    private var needsDriverInstallation: Bool {
        !driverManager.isReady && !store.routingCoordinator.manualModeEnabled
    }
    
    /// Whether the driver needs updating (outdated version).
    private var needsDriverUpdate: Bool {
        store.showDriverUpdateRequired && !store.routingCoordinator.manualModeEnabled
    }

    /// View model for routing status.
    private var routingViewModel: RoutingViewModel {
        RoutingViewModel(store: store)
    }

    /// View model for EQ configuration.
    private var eqViewModel: EQViewModel {
        EQViewModel(store: store)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Level meters + unified control panel
            HStack(alignment: .top, spacing: 0) {
                LevelMetersView(meterStore: store.meterStore)
                    .layoutPriority(1)
                    .offset(x: -8)

                Spacer(minLength: 64)

                GainControlsView(
                    inputGain: store.inputGain,
                    outputGain: store.outputGain,
                    onInputGainChange: { store.updateInputGain($0) },
                    onOutputGainChange: { store.updateOutputGain($0) }
                )

                Spacer()

                // Unified control panel - device pickers, status, and buttons grouped together
                VStack(alignment: .trailing, spacing: 8) {
                    // Device picker - only show in manual mode
                    if routingViewModel.manualModeEnabled {
                        DevicePickerView()
                    }

                    RoutingStatusView(viewModel: routingViewModel)
                        .frame(width: 376)

                    // Routing controls
                    VStack(alignment: .trailing, spacing: 8) {
                        // Meters toggle with CPU usage help
                        ToggleWithHelp(
                            label: "Meters",
                            isOn: $metersEnabledUI,
                            helpText: "Level meters add slight CPU overhead. They pause automatically when the window is closed or minimized. Disable here to reduce CPU while the window is open."
                        )
                        .id("meters-toggle")
                        .onAppear {
                            metersEnabledUI = store.meterStore.metersEnabled
                        }
                        .onChange(of: metersEnabledUI) { _, newValue in
                            store.meterStore.metersEnabled = newValue
                        }
                        .onReceive(store.meterStore.$metersEnabled.removeDuplicates()) { value in
                            if metersEnabledUI != value {
                                metersEnabledUI = value
                            }
                        }

                        SystemEQToggleView()
                            .id("system-eq-toggle")

                        // Audio Routing toggle - only shown in manual mode
                        // In automatic mode, routing starts automatically when driver is installed
                        if routingViewModel.manualModeEnabled {
                            ToggleWithHelp(
                                label: "Audio Routing",
                                isOn: Binding(
                                    get: { routingViewModel.isActive },
                                    set: { newValue in
                                        if newValue {
                                            store.reconfigureRouting()
                                        } else {
                                            store.stopRouting()
                                        }
                                    }
                                ),
                                helpText: "Enable or disable audio routing between the selected input and output devices. Both devices must be selected to enable routing."
                            )
                            .disabled(!routingViewModel.canToggleRouting)
                            .errorTint({
                                if case .error = store.routingStatus { return true }
                                return false
                            }())
                            .id("audio-routing-toggle")
                        }
                    }
                }
                .frame(minWidth: 376)
            }

            Divider()

            // Preset and band controls toolbar
            HStack(alignment: .top) {
                // Preset controls on left
                PresetToolbar()
                    .frame(minWidth: 280, maxWidth: 280, alignment: .leading)

                Spacer()

                // Bands control centered
                VStack(spacing: 4) {
                    Text("Bands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BandCountControl()
                }

                Spacer()

                // Channel mode control (Linked/Stereo + L/R)
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text("Channel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $store.channelMode) {
                            Text("Linked").tag(ChannelMode.linked)
                            Text("Stereo").tag(ChannelMode.stereo)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 100)
                    }

                    // L/R toggle - only visible in stereo mode
                    if store.channelMode == .stereo {
                        VStack(spacing: 4) {
                            Text("Edit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $store.channelFocus) {
                                Text("L").tag(ChannelFocus.left)
                                Text("R").tag(ChannelFocus.right)
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(width: 60)
                        }
                    }
                }

                Spacer()

                // Compare mode + Reset on right
                HStack(spacing: 12) {
                    // Compare Mode segmented control
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text("Compare")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                showCompareHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showCompareHelp, arrowEdge: .trailing) {
                                Text("A/B comparison: Switch between your EQ curve and a flat response at matched volume. Useful for comparing your EQ adjustments against the original sound. Automatically reverts to EQ after 5 minutes.")
                                    .font(.caption)
                                    .padding(12)
                                    .frame(width: 250)
                            }
                        }

                        Picker("", selection: $store.compareMode) {
                            Text("EQ").tag(CompareMode.eq)
                            Text("Flat").tag(CompareMode.flat)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 80)
                    }

                    VStack(spacing: 4) {
                        Text("Flatten")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(0)
                        Button {
                            store.flattenBands()
                        } label: {
                            Text("Flatten")
                                .frame(width: 50, height: 16)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reset all gains to 0 dB while keeping current band configuration")
                    }
                }
                .frame(minWidth: 280, maxWidth: 280, alignment: .trailing)
            }
            .padding(.vertical, 4)

            // EQ sliders
            EQBandGridView()
        }
        .padding(12)
        .frame(minWidth: 1060, minHeight: 530)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .background(
            WindowAccessor { window in
                store.setEqualiserWindow(window)
            }
        )
        .onAppear {
            store.meterStore.windowBecameVisible()
        }
        .onDisappear {
            store.meterStore.windowBecameHidden()
        }
        .sheet(isPresented: $showDriverSheet) {
            DriverInstallationView(
                onInstall: {
                    store.handleDriverInstalled()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .environmentObject(store)
            .frame(minWidth: 500, minHeight: 400)
        }
        .onChange(of: needsDriverInstallation) { _, newValue in
            showDriverSheet = newValue
        }
        .onChange(of: needsDriverUpdate) { _, newValue in
            if newValue {
                // Open Settings to Driver tab when driver needs updating
                openSettings()
            }
        }
        .onAppear {
            showDriverSheet = needsDriverInstallation
            if needsDriverUpdate {
                openSettings()
            }
        }
    }
}

struct SystemEQToggleView: View {
    enum Style {
        case standard
        case menuBar
    }

    @EnvironmentObject var store: EqualiserStore
    var style: Style = .standard

    var body: some View {
        switch style {
        case .standard:
            ToggleWithHelp(
                label: "System EQ",
                isOn: binding,
                helpText: "Enable or disable the equalizer processing. When disabled, audio passes through without EQ applied."
            )
        case .menuBar:
            Toggle("System EQ", isOn: binding)
                .controlSize(.small)
                .toggleStyle(.switch)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { !store.isBypassed },
            set: { store.isBypassed = !$0 }
        )
    }
}

#Preview("EQ Window") {
    EQWindowView()
        .environmentObject(EqualiserStore())
}
