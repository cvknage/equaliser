import SwiftUI

struct DevicePickerView: View {
    @EnvironmentObject var store: EqualizerStore

    private func binding(for selection: Binding<String?>) -> Binding<String> {
        Binding {
            selection.wrappedValue ?? ""
        } set: { value in
            selection.wrappedValue = value.isEmpty ? nil : value
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Input", selection: binding(for: $store.selectedInputDeviceID)) {
                ForEach(store.inputDevices) { device in
                    Text(device.displayName).tag(device.uid)
                }
            }

            Picker("Output", selection: binding(for: $store.selectedOutputDeviceID)) {
                ForEach(store.outputDevices) { device in
                    Text(device.displayName).tag(device.uid)
                }
            }
        }
    }
}
