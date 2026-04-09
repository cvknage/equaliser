import SwiftUI

enum DevicePickerLayout {
    case horizontal
    case vertical
}

struct DevicePickerView: View {
    var layout: DevicePickerLayout = .horizontal

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
            InputDevicePickerView(layout: .horizontal)
            OutputDevicePickerView(layout: .horizontal)
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            InputDevicePickerView(layout: .vertical)
            OutputDevicePickerView(layout: .vertical)
        }
    }
}

struct InputDevicePickerView: View {
    enum Layout {
        case horizontal
        case vertical
    }

    @EnvironmentObject var store: EqualiserStore
    var layout: Layout
    
    /// View model for device selection.
    private var viewModel: RoutingViewModel {
        RoutingViewModel(store: store)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Input")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Input", selection: binding(for: $store.selectedInputDeviceID)) {
                ForEach(viewModel.inputDevices) { device in
                    Text(device.displayName).tag(device.uid)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var verticalLayout: some View {
        HStack {
            Text("Input")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Section {
                    Text("Select Input")
                }
                Section {
                    ForEach(viewModel.inputDevices) { device in
                        Button {
                            viewModel.selectInputDevice(device.uid)
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if viewModel.selectedInputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(viewModel.inputDeviceName)
            }
        }
    }

    private func binding(for selection: Binding<String?>) -> Binding<String> {
        Binding {
            selection.wrappedValue ?? ""
        } set: { value in
            selection.wrappedValue = value.isEmpty ? nil : value
        }
    }
}

struct OutputDevicePickerView: View {
    enum Layout {
        case horizontal
        case vertical
    }

    @EnvironmentObject var store: EqualiserStore
    var layout: Layout
    
    /// View model for device selection.
    private var viewModel: RoutingViewModel {
        RoutingViewModel(store: store)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Output")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Output", selection: binding(for: $store.selectedOutputDeviceID)) {
                ForEach(viewModel.outputDevices) { device in
                    Text(device.displayName).tag(device.uid)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var verticalLayout: some View {
        HStack {
            Text("Output")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Section {
                    Text("Select Output")
                }
                Section {
                    ForEach(viewModel.outputDevices) { device in
                        Button {
                            viewModel.selectOutputDevice(device.uid)
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if viewModel.selectedOutputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(viewModel.outputDeviceName)
            }
        }
    }

    private func binding(for selection: Binding<String?>) -> Binding<String> {
        Binding {
            selection.wrappedValue ?? ""
        } set: { value in
            selection.wrappedValue = value.isEmpty ? nil : value
        }
    }
}
