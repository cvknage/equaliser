import SwiftUI

struct DevicePresetsButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Device Presets", systemImage: "list.bullet.rectangle")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Device presets")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DevicePresetsView()
        }
    }
}

struct DevicePresetsView: View {
    @EnvironmentObject var store: EqualiserStore

    private var viewModel: DevicePresetsViewModel {
        DevicePresetsViewModel(store: store)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device Presets")
                .font(.headline)

            Divider()

            if viewModel.devices.isEmpty {
                Text("No output devices")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.devices) { device in
                            HStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: device.isAvailable ? "speaker.wave.2" : "speaker.slash")
                                        .foregroundStyle(device.isSelected ? Color.accentColor : .secondary)
                                        .frame(width: 16)
                                    Text(device.name)
                                        .foregroundStyle(device.isAvailable ? .primary : .secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .help(device.name + (device.isSelected ? " (current output)" : device.isAvailable ? "" : " (unavailable)") + "\n" + device.uid)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                DevicePresetPicker(
                                    names: viewModel.presets.map { $0.metadata.name },
                                    selection: Binding(
                                        get: { viewModel.presetName(for: device.uid) },
                                        set: { viewModel.updatePreset(named: $0, for: device.uid) }
                                    ),
                                    label: "Preset for \(device.name)"
                                )
                                .frame(width: 160, height: 24)
                            }
                            .frame(height: 36)
                        }
                    }
                }
                .frame(height: min(CGFloat(viewModel.devices.count) * 36, 252))
            }
        }
        .padding(14)
        .frame(width: 400)
    }
}
