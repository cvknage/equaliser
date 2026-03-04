import SwiftUI

enum DevicePickerLayout {
    case horizontal
    case vertical
}

struct DevicePickerView: View {
    @EnvironmentObject var store: EqualizerStore
    var layout: DevicePickerLayout = .horizontal

    private func binding(for selection: Binding<String?>) -> Binding<String> {
        Binding {
            selection.wrappedValue ?? ""
        } set: { value in
            selection.wrappedValue = value.isEmpty ? nil : value
        }
    }

    var body: some View {
        switch layout {
        case .horizontal:
            horizontalLayout
        case .vertical:
            verticalLayout
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Input", selection: binding(for: $store.selectedInputDeviceID)) {
                    ForEach(store.inputDevices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Output", selection: binding(for: $store.selectedOutputDeviceID)) {
                    ForEach(store.outputDevices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Input", selection: binding(for: $store.selectedInputDeviceID)) {
                    ForEach(store.inputDevices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Output", selection: binding(for: $store.selectedOutputDeviceID)) {
                    ForEach(store.outputDevices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }
                .labelsHidden()
            }
        }
    }
}
