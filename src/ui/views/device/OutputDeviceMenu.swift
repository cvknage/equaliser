import SwiftUI

/// Compact menu for picking the output device that Equaliser routes to.
struct OutputDeviceMenu: View {
    let viewModel: RoutingViewModel

    var body: some View {
        Menu {
            Section("Output") {
                ForEach(viewModel.outputDevices.filter(\.isValidForSelection)) { device in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedOutputDeviceID == device.uid },
                        set: { if $0 { viewModel.selectOutputDevice(device.uid) } }
                    )) {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Output device")
        .accessibilityLabel("Output device")
    }
}
