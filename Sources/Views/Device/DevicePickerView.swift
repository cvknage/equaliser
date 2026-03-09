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
        HStack(spacing: 0) {
            InputDevicePickerView(layout: .horizontal)
                .frame(maxWidth: 180, alignment: .leading)
            Spacer()
            OutputDevicePickerView(layout: .horizontal)
                .frame(maxWidth: 180, alignment: .trailing)
        }
        .frame(width: 376)
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
            Menu {
                Section {
                    Text("Select Input")
                }
                Section {
                    ForEach(store.inputDevices) { device in
                        Button {
                            store.selectedInputDeviceID = device.uid
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if store.selectedInputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(displayInputText)
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Input")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Section {
                    Text("Select Input")
                }
                Section {
                    ForEach(store.inputDevices) { device in
                        Button {
                            store.selectedInputDeviceID = device.uid
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if store.selectedInputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(displayInputText)
            }
        }
    }

    private var displayInputText: String {
        if let uid = store.selectedInputDeviceID,
           let device = store.inputDevices.first(where: { $0.uid == uid }) {
            return device.displayName
        }
        return "Select Input"
    }
}

struct OutputDevicePickerView: View {
    enum Layout {
        case horizontal
        case vertical
    }

    @EnvironmentObject var store: EqualiserStore
    var layout: Layout

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
            Menu {
                Section {
                    Text("Select Output")
                }
                Section {
                    ForEach(store.outputDevices) { device in
                        Button {
                            store.selectedOutputDeviceID = device.uid
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if store.selectedOutputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(displayOutputText)
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Section {
                    Text("Select Output")
                }
                Section {
                    ForEach(store.outputDevices) { device in
                        Button {
                            store.selectedOutputDeviceID = device.uid
                        } label: {
                            HStack {
                                Text(device.displayName)
                                if store.selectedOutputDeviceID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(displayOutputText)
            }
        }
    }

    private var displayOutputText: String {
        if let uid = store.selectedOutputDeviceID,
           let device = store.outputDevices.first(where: { $0.uid == uid }) {
            return device.displayName
        }
        return "Select Output"
    }
}
