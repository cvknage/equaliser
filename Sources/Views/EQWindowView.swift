import SwiftUI
import Combine

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @EnvironmentObject var store: EqualiserStore
    @State private var showCompareHelp = false
    @State private var metersEnabledUI = false

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
                    onInputGainChange: { store.setInputGain($0) },
                    onOutputGainChange: { store.setOutputGain($0) }
                )

                Spacer()

                // Unified control panel - device pickers, status, and buttons grouped together
                VStack(alignment: .trailing, spacing: 8) {
                    // Device pickers
                    DevicePickerView(layout: .horizontal)

                    RoutingStatusView(status: store.routingStatus, isBypassed: store.isBypassed)
                        .frame(width: 376)

                    // Routing controls
                    VStack(alignment: .trailing, spacing: 8) {
                        // Meters toggle with CPU usage help
                        ToggleWithHelp(
                            label: "Meters",
                            isOn: $metersEnabledUI,
                            helpText: "Level meters update at 30 FPS and can increase CPU usage. When this window is closed or minimized, meters stop rendering. Disable to reduce CPU while the window is open."
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

                        // Audio Routing toggle with help
                        ToggleWithHelp(
                            label: "Audio Routing",
                            isOn: Binding(
                                get: { store.routingStatus.isActive },
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
                        .disabled(store.routingStatus == .idle
                                  && (store.selectedInputDeviceID == nil
                                      || store.selectedOutputDeviceID == nil))
                        .errorTint({
                            if case .error = store.routingStatus { return true }
                            return false
                        }())
                        .id("audio-routing-toggle")
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
                        Text("Reset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(0)
                        Button {
                            store.resetToDefaults()
                        } label: {
                            Text("Reset")
                                .frame(width: 50, height: 16)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
        .background(
            WindowAccessor { window in
                store.setEqualiserWindow(window)
            }
        )
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
