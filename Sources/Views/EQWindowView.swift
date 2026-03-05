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

                    RoutingStatusView(status: store.routingStatus, isBypassed: store.isBypassed)
                        .frame(width: 376)

                    // Routing controls
                    HStack(spacing: 16) {
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
                
                // Reset button on right
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
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 4)

            // EQ sliders
            EQBandGridView()
        }
        .padding(12)
        .frame(minWidth: 1060, minHeight: 530)
    }
}

#Preview("EQ Window") {
    EQWindowView()
        .environmentObject(EqualiserStore())
}
