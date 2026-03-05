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

                    RoutingStatusView(status: store.routingStatus, isBypassed: store.isBypassed)
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
