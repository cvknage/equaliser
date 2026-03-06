import SwiftUI

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @EnvironmentObject var store: EqualiserStore

    var body: some View {
        VStack(spacing: 12) {
            // Level meters + unified control panel
            HStack(alignment: .top, spacing: 0) {
                LevelMetersView(
                    inputState: store.inputMeterLevel,
                    outputState: store.outputMeterLevel,
                    inputRMSState: store.inputMeterRMS,
                    outputRMSState: store.outputMeterRMS
                )
                .layoutPriority(1)
                .offset(x: -8)

                Spacer(minLength: 64)

                GainControlsView(
                    inputGain: $store.inputGain,
                    outputGain: $store.outputGain
                )

                Spacer()

                // Unified control panel - device pickers, status, and buttons grouped together
                VStack(alignment: .trailing, spacing: 8) {
                    // Device pickers
                    DevicePickerView(layout: .horizontal)

                    RoutingStatusView(status: store.routingStatus, isBypassed: store.isBypassed, compareMode: store.compareMode)
                        .frame(width: 376)

                    // Routing controls
                    VStack(alignment: .trailing, spacing: 8) {
                        // Meters toggle with CPU usage help
                        ToggleWithHelp(
                            label: "Meters",
                            isOn: $store.metersEnabled,
                            helpText: "Level meters update at 30 FPS and can increase CPU usage. When this window is closed or minimized, meters stop rendering. Disable to reduce CPU while the window is open."
                        )

                        // System EQ toggle with help
                        ToggleWithHelp(
                            label: "System EQ",
                            isOn: Binding(
                                get: { !store.isBypassed },
                                set: { store.isBypassed = !$0 }
                            ),
                            helpText: "Enable or disable the equalizer processing. When disabled, audio passes through without EQ applied."
                        )

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
                    }
                }
                .frame(minWidth: 376)
            }

            Divider()

            // Preset and band controls toolbar
            ZStack(alignment: .top) {
                // Preset controls on left
                PresetToolbar()
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Bands control centered
                VStack(spacing: 4) {
                    Text("Bands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BandCountControl()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // Compare mode + Reset on right
                HStack(spacing: 12) {
                    // Compare Mode segmented control
                    VStack(spacing: 4) {
                        Text("Compare")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $store.compareMode) {
                            Text("EQ").tag(CompareMode.eq)
                            Text("Flat").tag(CompareMode.flat)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 80)
                        .disabled(store.isBypassed)
                        .opacity(store.isBypassed ? 0.5 : 1.0)
                        .help("A/B comparison: EQ vs Flat at matched volume. Disabled when System EQ is off.")
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
                .frame(maxWidth: .infinity, alignment: .trailing)
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

#Preview("EQ Window") {
    EQWindowView()
        .environmentObject(EqualiserStore())
}
