import SwiftUI

/// The main EQ settings window - detailed controls.
struct EQWindowView: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        VStack(spacing: 12) {
            // Header: App title only
            HStack {
                Image(systemName: "slider.vertical.3")
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

                Button("Reset") {
                    store.resetToDefaults()
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

#Preview("EQ Window") {
    EQWindowView()
        .environmentObject(EqualizerStore())
}
