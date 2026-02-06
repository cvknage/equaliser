import SwiftUI

@main
struct EqualizerAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = EqualizerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    // Share the store with the app delegate for popover access
                    if appDelegate.store !== store {
                        appDelegate.store = store
                    }
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: EqualizerStore

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                Text("Equalizer")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)

            // Device Pickers
            DevicePickerView()

            // Routing Status
            RoutingStatusView(status: store.routingStatus)

            Divider()

            // Controls
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Bypass EQ", isOn: $store.isBypassed)
                    .toggleStyle(.checkbox)

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
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Footer
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280, height: 320)
    }
}

#Preview {
    ContentView()
        .environmentObject(EqualizerStore())
}
